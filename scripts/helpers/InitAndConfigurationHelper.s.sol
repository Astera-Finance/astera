// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";
import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/protocol/core/Oracle.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";

import "contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";

import "contracts/protocol/tokenization/ERC20/AToken.sol";
import "contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import "contracts/misc/Cod3xLendDataProvider.sol";
import "../DeployDataTypes.sol";

import "forge-std/console2.sol";

contract InitAndConfigurationHelper {
    address constant FOUNDRY_DEFAULT = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    uint256 constant PRICE_FEED_DECIMALS = 8;
    DeployedContracts contracts;

    function _initAndConfigureReserves(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig,
        General memory _general
    ) internal {
        ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
            new ILendingPoolConfigurator.InitReserveInput[](_reservesConfig.length);
        if (_contracts.lendingPool.paused()) {
            _contracts.lendingPoolConfigurator.setPoolPause(false);
        }
        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            bool assetExist = false;
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];
            require(
                contracts.oracle.getSourceOfAsset(reserveConfig.tokenAddress) != address(0),
                "Oracle config not compliant"
            );
            string memory tmpSymbol = ERC20(reserveConfig.tokenAddress).symbol();

            address interestStrategy = _determineInterestStrat(_contracts, reserveConfig);

            initInputParams[idx] = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: address(_contracts.aToken),
                variableDebtTokenImpl: address(_contracts.variableDebtToken),
                underlyingAssetDecimals: ERC20(reserveConfig.tokenAddress).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: reserveConfig.tokenAddress,
                reserveType: reserveConfig.reserveType,
                treasury: _general.treasury,
                incentivesController: address(0),
                underlyingAssetName: tmpSymbol,
                aTokenName: string.concat(_general.aTokenNamePrefix, tmpSymbol),
                aTokenSymbol: string.concat(_general.aTokenSymbolPrefix, tmpSymbol),
                variableDebtTokenName: string.concat(_general.debtTokenNamePrefix, tmpSymbol),
                variableDebtTokenSymbol: string.concat(_general.debtTokenSymbolPrefix, tmpSymbol),
                params: bytes(reserveConfig.params)
            });
        }
        console2.log("Batch init");
        _contracts.lendingPoolConfigurator.batchInitReserve(initInputParams);

        _configureReserves(_contracts, _reservesConfig, _general.usdBootstrapAmount);
        if (!_contracts.lendingPool.paused()) {
            _contracts.lendingPoolConfigurator.setPoolPause(true);
        }
    }

    function _configureReserves(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig,
        uint256 usdBootstrapAmount
    ) internal {
        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];

            _contracts.lendingPoolConfigurator.disableBorrowingOnReserve(
                reserveConfig.tokenAddress, reserveConfig.reserveType
            );
            _contracts.lendingPoolConfigurator.configureReserveAsCollateral(
                reserveConfig.tokenAddress,
                reserveConfig.reserveType,
                reserveConfig.baseLtv,
                reserveConfig.liquidationThreshold,
                reserveConfig.liquidationBonus
            );

            uint256 tokenPrice = _contracts.oracle.getAssetPrice(reserveConfig.tokenAddress);
            uint256 tokenAmount = usdBootstrapAmount * contracts.oracle.BASE_CURRENCY_UNIT()
                * 10 ** IERC20Detailed(reserveConfig.tokenAddress).decimals() / tokenPrice;

            console2.log(
                "Bootstrap amount: %s %s for price: %s",
                tokenAmount,
                IERC20Detailed(reserveConfig.tokenAddress).symbol(),
                tokenPrice
            );
            IERC20Detailed(reserveConfig.tokenAddress).approve(
                address(_contracts.lendingPool), tokenAmount
            );
            if (msg.sender != FOUNDRY_DEFAULT) {
                _contracts.lendingPool.deposit(
                    reserveConfig.tokenAddress,
                    reserveConfig.reserveType,
                    tokenAmount,
                    _contracts.lendingPoolAddressesProvider.getPoolAdmin()
                );
                DataTypes.ReserveData memory reserveData = _contracts.lendingPool.getReserveData(
                    reserveConfig.tokenAddress, reserveConfig.reserveType
                );
                require(
                    IERC20Detailed(reserveData.aTokenAddress).totalSupply() == tokenAmount,
                    "TotalSupply not equal to deposited amount!"
                );

                _contracts.lendingPoolConfigurator.enableBorrowingOnReserve(
                    reserveConfig.tokenAddress, reserveConfig.reserveType
                );
                _contracts.lendingPool.borrow(
                    reserveConfig.tokenAddress,
                    reserveConfig.reserveType,
                    tokenAmount / 2,
                    _contracts.lendingPoolAddressesProvider.getPoolAdmin()
                );
                reserveData = _contracts.lendingPool.getReserveData(
                    reserveConfig.tokenAddress, reserveConfig.reserveType
                );
                require(
                    IERC20Detailed(reserveData.variableDebtTokenAddress).totalSupply()
                        == tokenAmount / 2,
                    "TotalSupply of debt not equal to borrowed amount!"
                );

                if (!reserveConfig.borrowingEnabled) {
                    _contracts.lendingPoolConfigurator.disableBorrowingOnReserve(
                        reserveConfig.tokenAddress, reserveConfig.reserveType
                    );
                }
            }

            _contracts.lendingPoolConfigurator.setCod3xReserveFactor(
                reserveConfig.tokenAddress, reserveConfig.reserveType, reserveConfig.reserveFactor
            );
            _contracts.lendingPoolConfigurator.enableFlashloan(
                reserveConfig.tokenAddress, reserveConfig.reserveType
            );
        }
    }

    function _initAndConfigureMiniPoolReserves(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig,
        uint256 _miniPoolId,
        uint256 _usdBootstrapAmount
    ) internal returns (address aToken, address miniPool) {
        IMiniPoolConfigurator.InitReserveInput[] memory initInputParams =
            new IMiniPoolConfigurator.InitReserveInput[](_reservesConfig.length);
        address mp = _contracts.miniPoolAddressesProvider.getMiniPool(_miniPoolId);
        console2.log("MiniPool to configure: ", mp);
        if (_contracts.lendingPool.paused()) {
            _contracts.lendingPoolConfigurator.setPoolPause(false);
        }
        if (IMiniPool(mp).paused()) {
            _contracts.miniPoolConfigurator.setPoolPause(false, IMiniPool(mp));
        }
        console2.log("Getting ERC6909");
        address aTokensErc6909Addr = _contracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(mp);
        console2.log("_reservesConfig LENGTH: ", _reservesConfig.length);
        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];
            string memory tmpSymbol = ERC20(reserveConfig.tokenAddress).symbol();
            string memory tmpName = ERC20(reserveConfig.tokenAddress).name();

            address interestStrategy = _determineMiniPoolInterestStrat(_contracts, reserveConfig);

            initInputParams[idx] = IMiniPoolConfigurator.InitReserveInput({
                underlyingAssetDecimals: ERC20(reserveConfig.tokenAddress).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: reserveConfig.tokenAddress,
                underlyingAssetName: tmpName,
                underlyingAssetSymbol: tmpSymbol
            });
        }
        console2.log("Batching ... ");
        console2.log("length initInputParams: ", initInputParams.length);
        _contracts.miniPoolConfigurator.batchInitReserve(initInputParams, IMiniPool(mp));
        console2.log("Configuring");
        _configureMiniPoolReserves(_contracts, _reservesConfig, mp, _usdBootstrapAmount);
        if (_contracts.lendingPool.paused()) {
            _contracts.lendingPoolConfigurator.setPoolPause(true);
        }
        if (IMiniPool(mp).paused()) {
            _contracts.miniPoolConfigurator.setPoolPause(true, IMiniPool(mp));
        }
        return (aTokensErc6909Addr, mp);
    }

    function _configureMiniPoolReserves(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig,
        address _mp,
        uint256 _usdBootstrapAmount
    ) internal {
        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];
            _contracts.miniPoolConfigurator.disableBorrowingOnReserve(
                reserveConfig.tokenAddress, IMiniPool(_mp)
            );

            _contracts.miniPoolConfigurator.configureReserveAsCollateral(
                reserveConfig.tokenAddress,
                reserveConfig.baseLtv,
                reserveConfig.liquidationThreshold,
                reserveConfig.liquidationBonus,
                IMiniPool(_mp)
            );
            console2.log("Configured");
            _contracts.miniPoolConfigurator.activateReserve(
                reserveConfig.tokenAddress, IMiniPool(_mp)
            );

            uint256 tokenPrice = _contracts.oracle.getAssetPrice(reserveConfig.tokenAddress);
            uint256 tokenAmount = _usdBootstrapAmount * contracts.oracle.BASE_CURRENCY_UNIT()
                * 10 ** IERC20Detailed(reserveConfig.tokenAddress).decimals() / tokenPrice;
            console2.log(
                "MiniPool Bootstrap amount: %s %s for price: %s",
                tokenAmount,
                IERC20Detailed(reserveConfig.tokenAddress).symbol(),
                tokenPrice
            );
            console2.log(
                "Balance of %s: %s",
                _contracts.miniPoolAddressesProvider.getPoolAdmin(
                    _contracts.miniPoolAddressesProvider.getMiniPoolId(_mp)
                ),
                IERC20Detailed(reserveConfig.tokenAddress).balanceOf(
                    _contracts.miniPoolAddressesProvider.getPoolAdmin(
                        _contracts.miniPoolAddressesProvider.getMiniPoolId(_mp)
                    )
                )
            );
            console2.log("Token address: ", reserveConfig.tokenAddress);
            // DataTypes.ReserveData memory reserveData = _contracts.lendingPool.getReserveData(
            //     reserveConfig.tokenAddress, reserveConfig.reserveType
            // );
            IERC20Detailed(reserveConfig.tokenAddress).approve(address(_mp), tokenAmount);
            IMiniPool(_mp).deposit(
                reserveConfig.tokenAddress,
                false,
                tokenAmount,
                _contracts.miniPoolAddressesProvider.getPoolAdmin(
                    _contracts.miniPoolAddressesProvider.getMiniPoolId(_mp)
                )
            );
            DataTypes.MiniPoolReserveData memory miniPoolReserveData =
                IMiniPool(_mp).getReserveData(reserveConfig.tokenAddress);
            require(
                IAERC6909(miniPoolReserveData.aErc6909).totalSupply(miniPoolReserveData.aTokenID)
                    == tokenAmount,
                "TotalSupply not equal to deposited amount!"
            );

            _contracts.miniPoolConfigurator.enableBorrowingOnReserve(
                reserveConfig.tokenAddress, IMiniPool(_mp)
            );
            IMiniPool(_mp).borrow(
                reserveConfig.tokenAddress,
                false,
                tokenAmount / 2,
                _contracts.miniPoolAddressesProvider.getPoolAdmin(
                    _contracts.miniPoolAddressesProvider.getMiniPoolId(_mp)
                )
            );
            miniPoolReserveData = IMiniPool(_mp).getReserveData(reserveConfig.tokenAddress);
            require(
                IAERC6909(miniPoolReserveData.aErc6909).totalSupply(
                    miniPoolReserveData.variableDebtTokenID
                ) == tokenAmount / 2,
                "TotalSupply of debt not equal to borrowed amount!"
            );

            if (!reserveConfig.borrowingEnabled) {
                _contracts.miniPoolConfigurator.disableBorrowingOnReserve(
                    reserveConfig.tokenAddress, IMiniPool(_mp)
                );
            }
            _contracts.miniPoolConfigurator.setCod3xReserveFactor(
                reserveConfig.tokenAddress, reserveConfig.reserveFactor, IMiniPool(_mp)
            );
            _contracts.miniPoolConfigurator.setMinipoolOwnerReserveFactor(
                reserveConfig.tokenAddress, reserveConfig.miniPoolOwnerFee, IMiniPool(_mp)
            );
            _contracts.miniPoolConfigurator.enableFlashloan(
                reserveConfig.tokenAddress, IMiniPool(_mp)
            );
        }
    }

    function _determineInterestStrat(
        DeployedContracts memory _contracts,
        PoolReserversConfig memory _reserveConfig
    ) internal returns (address) {
        address interestStrategy;
        if (keccak256(bytes(_reserveConfig.interestStrat)) == keccak256(bytes("PI"))) {
            require(
                _contracts.piStrategies[_reserveConfig.interestStratId]._asset()
                    == _reserveConfig.tokenAddress,
                "Pi strat has different asset address than reserve"
            );
            interestStrategy = address(_contracts.piStrategies[_reserveConfig.interestStratId]);
        } else {
            require(
                (
                    keccak256(bytes(_reserveConfig.interestStrat)) == keccak256(bytes("VOLATILE"))
                        && _contracts.volatileStrategies.length > _reserveConfig.interestStratId
                )
                    || (
                        keccak256(bytes(_reserveConfig.interestStrat)) == keccak256(bytes("STABLE"))
                            && _contracts.stableStrategies.length > _reserveConfig.interestStratId
                    ),
                "Lengths of strats not enough"
            );
            interestStrategy = keccak256(bytes(_reserveConfig.interestStrat))
                == keccak256(bytes("VOLATILE"))
                ? address(_contracts.volatileStrategies[_reserveConfig.interestStratId])
                : address(_contracts.stableStrategies[_reserveConfig.interestStratId]);
        }
        return interestStrategy;
    }

    function _determineMiniPoolInterestStrat(
        DeployedContracts memory _contracts,
        PoolReserversConfig memory _reserveConfig
    ) internal returns (address) {
        address interestStrategy;
        if (keccak256(bytes(_reserveConfig.interestStrat)) == keccak256(bytes("PI"))) {
            require(
                _contracts.miniPoolPiStrategies.length > _reserveConfig.interestStratId,
                "miniPoolPiStrategies length too short"
            );
            require(
                _contracts.miniPoolPiStrategies[_reserveConfig.interestStratId]._asset()
                    == _reserveConfig.tokenAddress,
                "Mini pool Pi strat has different asset address than reserve"
            );
            interestStrategy =
                address(_contracts.miniPoolPiStrategies[_reserveConfig.interestStratId]);
        } else {
            console2.log("LINEAR");
            if (keccak256(bytes(_reserveConfig.interestStrat)) == keccak256(bytes("VOLATILE"))) {
                require(
                    _contracts.miniPoolVolatileStrategies.length > _reserveConfig.interestStratId,
                    "miniPoolVolatileStrategies length too short"
                );
                interestStrategy =
                    address(_contracts.miniPoolVolatileStrategies[_reserveConfig.interestStratId]);
            } else {
                require(
                    _contracts.miniPoolStableStrategies.length > _reserveConfig.interestStratId,
                    "miniPoolStableStrategies length too short"
                );
                interestStrategy =
                    address(_contracts.miniPoolStableStrategies[_reserveConfig.interestStratId]);
            }
        }
        return interestStrategy;
    }

    function _changeStrategies(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig
    ) public {
        console2.log("_reservesConfig.length: ", _reservesConfig.length);
        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            console2.log("Idx: ", idx);
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];
            console2.log("Determining");
            address interestStrategy = _determineInterestStrat(_contracts, reserveConfig);
            console2.log("%s. Setting reserve interest: %s", idx, interestStrategy);
            _contracts.lendingPoolConfigurator.setReserveInterestRateStrategyAddress(
                reserveConfig.tokenAddress, reserveConfig.reserveType, interestStrategy
            );
        }
    }

    function _changeMiniPoolStrategies(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig,
        address _miniPool
    ) public {
        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];
            address interestStrategy = _determineMiniPoolInterestStrat(_contracts, reserveConfig);
            _contracts.miniPoolConfigurator.setReserveInterestRateStrategyAddress(
                reserveConfig.tokenAddress, interestStrategy, IMiniPool(_miniPool)
            );
        }
    }
}
