// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";
import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/protocol/core/Oracle.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";

import "contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";

import "contracts/deployments/ATokensAndRatesHelper.sol";
import "contracts/protocol/tokenization/ERC20/AToken.sol";
import "contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import "../DeployDataTypes.sol";

import "forge-std/console.sol";

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
        console.log("Batch init");
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

            _contracts.lendingPoolConfigurator.configureReserveAsCollateral(
                reserveConfig.tokenAddress,
                reserveConfig.reserveType,
                reserveConfig.baseLtv,
                reserveConfig.liquidationThreshold,
                reserveConfig.liquidationBonus
            );

            if (reserveConfig.borrowingEnabled) {
                _contracts.lendingPoolConfigurator.enableBorrowingOnReserve(
                    reserveConfig.tokenAddress, reserveConfig.reserveType
                );
            }
            _contracts.lendingPoolConfigurator.setCod3xReserveFactor(
                reserveConfig.tokenAddress, reserveConfig.reserveType, reserveConfig.reserveFactor
            );

            uint256 tokenPrice = _contracts.oracle.getAssetPrice(reserveConfig.tokenAddress);
            if (usdBootstrapAmount > tokenPrice) {
                uint256 tokenAmount = (usdBootstrapAmount / tokenPrice) * 10 ** PRICE_FEED_DECIMALS
                    / (10 ** (18 - IERC20Detailed(reserveConfig.tokenAddress).decimals()));
                console.log(
                    "Bootstrap amount: %s %s for price: %s",
                    tokenAmount,
                    IERC20Detailed(reserveConfig.tokenAddress).symbol(),
                    tokenPrice
                );
                IERC20Detailed(reserveConfig.tokenAddress).approve(
                    address(_contracts.lendingPool), tokenAmount
                );
                _contracts.lendingPool.deposit(
                    reserveConfig.tokenAddress,
                    true,
                    tokenAmount,
                    contracts.lendingPoolAddressesProvider.getPoolAdmin()
                );
                DataTypes.ReserveData memory reserveData = contracts.lendingPool.getReserveData(
                    reserveConfig.tokenAddress, reserveConfig.reserveType
                );
                require(
                    IERC20Detailed(reserveData.aTokenAddress).totalSupply() == tokenAmount,
                    "TotalSupply not equal to deposited amount!"
                );
            }

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
        console.log("MiniPool to configure: ", mp);
        if (_contracts.lendingPool.paused()) {
            _contracts.lendingPoolConfigurator.setPoolPause(false);
        }
        if (IMiniPool(mp).paused()) {
            _contracts.miniPoolConfigurator.setPoolPause(false, IMiniPool(mp));
        }
        console.log("Getting ERC6909");
        address aTokensErc6909Addr = _contracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(mp);
        console.log("_reservesConfig LENGTH: ", _reservesConfig.length);
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
        console.log("Batching ... ");
        console.log("length initInputParams: ", initInputParams.length);
        _contracts.miniPoolConfigurator.batchInitReserve(initInputParams, IMiniPool(mp));
        console.log("Configuring");
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
            _contracts.miniPoolConfigurator.configureReserveAsCollateral(
                reserveConfig.tokenAddress,
                reserveConfig.baseLtv,
                reserveConfig.liquidationThreshold,
                reserveConfig.liquidationBonus,
                IMiniPool(_mp)
            );
            console.log("Configured");
            _contracts.miniPoolConfigurator.activateReserve(
                reserveConfig.tokenAddress, IMiniPool(_mp)
            );

            if (reserveConfig.borrowingEnabled) {
                _contracts.miniPoolConfigurator.enableBorrowingOnReserve(
                    reserveConfig.tokenAddress, IMiniPool(_mp)
                );
            }

            uint256 tokenPrice = _contracts.oracle.getAssetPrice(reserveConfig.tokenAddress);
            if (_usdBootstrapAmount > tokenPrice) {
                uint256 tokenAmount = (_usdBootstrapAmount / tokenPrice) * 10 ** PRICE_FEED_DECIMALS
                    / (10 ** (18 - IERC20Detailed(reserveConfig.tokenAddress).decimals()));
                console.log(
                    "MiniPool Bootstrap amount: %s %s for price: %s",
                    tokenAmount,
                    IERC20Detailed(reserveConfig.tokenAddress).symbol(),
                    tokenPrice
                );
                console.log(
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
                console.log("Token address: ", reserveConfig.tokenAddress);
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
                    IAERC6909(miniPoolReserveData.aErc6909).totalSupply(
                        miniPoolReserveData.aTokenID
                    ) == tokenAmount,
                    "TotalSupply not equal to deposited amount!"
                );
                console.log("Token ID: ", miniPoolReserveData.aTokenID);
                console.log("aErc6909: ", miniPoolReserveData.aErc6909);
                console.log("id: ", miniPoolReserveData.id);
                console.log("lastUpdateTimestamp: ", miniPoolReserveData.lastUpdateTimestamp);
                console.log("variableDebtTokenID: ", miniPoolReserveData.variableDebtTokenID);
            }
            console.log("Configuration for:", reserveConfig.tokenAddress);
            DataTypes.MiniPoolReserveData memory miniPoolReserveData =
                IMiniPool(_mp).getReserveData(reserveConfig.tokenAddress);
            console.log("Token ID: ", miniPoolReserveData.aTokenID);
            console.log("aErc6909: ", miniPoolReserveData.aErc6909);
            console.log("id: ", miniPoolReserveData.id);
            console.log("lastUpdateTimestamp: ", miniPoolReserveData.lastUpdateTimestamp);
            console.log("variableDebtTokenID: ", miniPoolReserveData.variableDebtTokenID);

            (address[] memory reserveList,) = IMiniPool(_mp).getReservesList();
            for (uint8 i = 0; i < reserveList.length; i++) {
                console.log("Reserve %s: %s", i, reserveList[i]);
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
            console.log("LINEAR");
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
        console.log("_reservesConfig.length: ", _reservesConfig.length);
        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            console.log("Idx: ", idx);
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];
            console.log("Determining");
            address interestStrategy = _determineInterestStrat(_contracts, reserveConfig);
            console.log("%s. Setting reserve interest: %s", idx, interestStrategy);
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
