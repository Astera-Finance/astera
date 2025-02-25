// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/protocol/core/Oracle.sol";
import "contracts/misc/Cod3xLendDataProvider.sol";
// import "contracts/misc/Treasury.sol";

import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolPiReserveInterestRateStrategy.sol";
import "contracts/protocol/core/lendingpool/LendingPool.sol";
import "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import "contracts/protocol/core/minipool/MiniPool.sol";
import "contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import "contracts/protocol/core/minipool/FlowLimiter.sol";
import "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import "../DeployDataTypes.sol";
import "forge-std/console.sol";

contract MiniPoolHelper {
    address constant FOUNDRY_DEFAULT = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    uint256 constant PRICE_FEED_DECIMALS = 8;
    DeployedContracts contracts;

    function deployMiniPoolInfra(
        General memory _general,
        LinearStrategy[] memory _volatileStrats,
        LinearStrategy[] memory _stableStrats,
        PiStrategy[] memory _piStrats,
        PoolReserversConfig[] memory _poolReserversConfig,
        address _deployer,
        bool _usePreviousStrats
    ) public {
        uint256 miniPoolId = _deployMiniPoolContracts(_deployer);

        if (!_usePreviousStrats) {
            _deployMiniPoolStrategies(
                contracts.miniPoolAddressesProvider,
                miniPoolId,
                _volatileStrats,
                _stableStrats,
                _piStrats
            );
        }

        _initAndConfigureMiniPoolReserves(
            contracts, _poolReserversConfig, miniPoolId, _general.usdBootstrapAmount
        );
    }

    function _deployMiniPoolContracts(address deployer) internal returns (uint256) {
        if (address(contracts.miniPoolImpl) == address(0)) {
            contracts.miniPoolImpl = new MiniPool();
        }
        if (address(contracts.aTokenErc6909Impl) == address(0)) {
            contracts.aTokenErc6909Impl = new ATokenERC6909();
        }
        uint256 miniPoolId;
        console.log("Mini pool addresses Provider: ", address(contracts.miniPoolAddressesProvider));
        if (address(contracts.miniPoolAddressesProvider) == address(0)) {
            // First deployment so configure miniPool infra

            contracts.miniPoolAddressesProvider =
                new MiniPoolAddressesProvider(contracts.lendingPoolAddressesProvider);
            miniPoolId = contracts.miniPoolAddressesProvider.deployMiniPool(
                address(contracts.miniPoolImpl), address(contracts.aTokenErc6909Impl), deployer
            );
            contracts.flowLimiter = new FlowLimiter(
                IMiniPoolAddressesProvider(address(contracts.miniPoolAddressesProvider))
            );
            contracts.miniPoolConfigurator = new MiniPoolConfigurator();
            contracts.miniPoolAddressesProvider.setMiniPoolConfigurator(
                address(contracts.miniPoolConfigurator)
            );
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(contracts.miniPoolAddressesProvider.getMiniPoolConfigurator());
            contracts.lendingPoolAddressesProvider.setMiniPoolAddressesProvider(
                address(contracts.miniPoolAddressesProvider)
            );
            contracts.lendingPoolAddressesProvider.setFlowLimiter(address(contracts.flowLimiter));
            contracts.cod3xLendDataProvider.setMiniPoolAddressProvider(
                address(contracts.miniPoolAddressesProvider)
            );
        } else {
            miniPoolId = contracts.miniPoolAddressesProvider.deployMiniPool(
                address(contracts.miniPoolImpl), address(contracts.aTokenErc6909Impl), deployer
            );
        }

        return miniPoolId;
    }

    function _deployMiniPoolStrategies(
        IMiniPoolAddressesProvider _provider,
        uint256 miniPoolId,
        LinearStrategy[] memory _volatileStrats,
        LinearStrategy[] memory _stableStrats,
        PiStrategy[] memory _piStrats
    ) internal {
        for (uint8 idx = 0; idx < _volatileStrats.length; idx++) {
            contracts.miniPoolVolatileStrategies.push(
                _deployMiniPoolStrategy(_provider, _volatileStrats[idx])
            );
        }
        for (uint8 idx = 0; idx < _stableStrats.length; idx++) {
            contracts.miniPoolStableStrategies.push(
                _deployMiniPoolStrategy(_provider, _stableStrats[idx])
            );
        }
        for (uint8 idx = 0; idx < _piStrats.length; idx++) {
            contracts.miniPoolPiStrategies.push(
                _deployMiniPoolPiInterestStrategy(_provider, miniPoolId, _piStrats[idx])
            );
        }
    }

    function _deployMiniPoolStrategy(
        IMiniPoolAddressesProvider _provider,
        LinearStrategy memory _strat
    ) internal returns (MiniPoolDefaultReserveInterestRateStrategy) {
        return new MiniPoolDefaultReserveInterestRateStrategy(
            _provider,
            _strat.optimalUtilizationRate,
            _strat.baseVariableBorrowRate,
            _strat.variableRateSlope1,
            _strat.variableRateSlope2
        );
    }

    function _deployMiniPoolPiInterestStrategy(
        IMiniPoolAddressesProvider _provider,
        uint256 miniPoolId,
        PiStrategy memory _strategy
    ) internal returns (MiniPoolPiReserveInterestRateStrategy) {
        return new MiniPoolPiReserveInterestRateStrategy(
            address(_provider),
            miniPoolId,
            _strategy.tokenAddress,
            _strategy.assetReserveType,
            _strategy.minControllerError,
            _strategy.maxITimeAmp,
            _strategy.optimalUtilizationRate,
            _strategy.kp,
            _strategy.ki
        );
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
        if (!_contracts.lendingPool.paused()) {
            _contracts.lendingPoolConfigurator.setPoolPause(true);
        }
        if (!IMiniPool(mp).paused()) {
            _contracts.miniPoolConfigurator.setPoolPause(true, IMiniPool(mp));
        }
        return (aTokensErc6909Addr, mp);
    }

    function _determineMiniPoolInterestStrat(
        DeployedContracts memory _contracts,
        PoolReserversConfig memory _reserveConfig
    ) internal returns (address) {
        address interestStrategy;
        console.log("STRAT LENGTH: ", _contracts.miniPoolVolatileStrategies.length);
        if (keccak256(bytes(_reserveConfig.interestStrat)) == keccak256(bytes("PI"))) {
            require(
                _contracts.miniPoolPiStrategies[_reserveConfig.interestStratId]._asset()
                    == _reserveConfig.tokenAddress,
                "Mini pool Pi strat has different asset address than reserve"
            );
            interestStrategy =
                address(_contracts.miniPoolPiStrategies[_reserveConfig.interestStratId]);
        } else {
            interestStrategy = keccak256(bytes(_reserveConfig.interestStrat))
                == keccak256(bytes("VOLATILE"))
                ? address(_contracts.miniPoolVolatileStrategies[_reserveConfig.interestStratId])
                : address(_contracts.miniPoolStableStrategies[_reserveConfig.interestStratId]);
        }
        return interestStrategy;
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

            _contracts.miniPoolConfigurator.activateReserve(
                reserveConfig.tokenAddress, IMiniPool(_mp)
            );

            uint256 tokenPrice = _contracts.oracle.getAssetPrice(reserveConfig.tokenAddress);
            uint256 tokenAmount = (_usdBootstrapAmount * 10 ** PRICE_FEED_DECIMALS) / tokenPrice
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
                IAERC6909(miniPoolReserveData.aErc6909).totalSupply(miniPoolReserveData.aTokenID)
                    == tokenAmount,
                "TotalSupply not equal to deposited amount!"
            );

            if (reserveConfig.borrowingEnabled) {
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
}
