// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/protocol/rewarder/lendingpool/Rewarder.sol";
import "contracts/protocol/core/Oracle.sol";
import "contracts/misc/Cod3xLendDataProvider.sol";
import "contracts/misc/Treasury.sol";
import "contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
import "contracts/protocol/core/lendingpool/logic/GenericLogic.sol";
import "contracts/protocol/core/lendingpool/logic/ValidationLogic.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import
    "contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import
    "contracts/protocol/core/interestRateStrategies/lendingpool/PiReserveInterestRateStrategy.sol";
import "contracts/protocol/core/lendingpool/LendingPool.sol";
import "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import "contracts/protocol/core/minipool/MiniPool.sol";
import "contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import "contracts/protocol/core/minipool/FlowLimiter.sol";

import "contracts/deployments/ATokensAndRatesHelper.sol";
import "contracts/protocol/tokenization/ERC20/AToken.sol";
import "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import "contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import "contracts/mocks/tokens/MintableERC20.sol";
import "contracts/mocks/tokens/WETH9Mocked.sol";
import "contracts/mocks/oracle/MockAggregator.sol";
import "contracts/mocks/tokens/MockVault.sol";
import "contracts/mocks/tokens/ExternalContract.sol";
import "contracts/mocks/dependencies/IStrategy.sol";
import "contracts/mocks/dependencies/IExternalContract.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import "contracts/mocks/oracle/PriceOracle.sol";
import "./DeployDataTypes.s.sol";
import {DataTypes} from "../contracts/protocol/libraries/types/DataTypes.sol";
import {Rewarder6909} from "contracts/protocol/rewarder/minipool/Rewarder6909.sol";

import "forge-std/console.sol";

contract DeploymentUtils {
    address constant FOUNDRY_DEFAULT = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    DeployedContracts contracts;

    function deployLendingPoolInfra(
        General memory _general,
        LinearStrategy[] memory _volatileStrats,
        LinearStrategy[] memory _stableStrats,
        PiStrategy[] memory _piStrategies,
        PoolReserversConfig[] memory _poolReserversConfig,
        address deployer
    ) public {
        _deployLendingPoolContracts(deployer);

        _deployStrategies(
            contracts.lendingPoolAddressesProvider, _volatileStrats, _stableStrats, _piStrategies
        );
        _deployTokensAndUtils(contracts.lendingPoolAddressesProvider);

        _initAndConfigureReserves(contracts, _poolReserversConfig, _general);
    }

    function deployMiniPoolInfra(
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

        _initAndConfigureMiniPoolReserves(contracts, _poolReserversConfig, miniPoolId);
    }

    function _deployStrategies(
        ILendingPoolAddressesProvider _provider,
        LinearStrategy[] memory _volatileStrats,
        LinearStrategy[] memory _stableStrats,
        PiStrategy[] memory _piStrats
    ) internal {
        for (uint8 idx = 0; idx < _volatileStrats.length; idx++) {
            contracts.volatileStrategies.push(
                _deployDefaultStrategy(_provider, _volatileStrats[idx])
            );
        }
        for (uint8 idx = 0; idx < _stableStrats.length; idx++) {
            contracts.stableStrategies.push(_deployDefaultStrategy(_provider, _stableStrats[idx]));
        }
        for (uint8 idx = 0; idx < _piStrats.length; idx++) {
            contracts.piStrategies.push(_deployPiInterestStrategy(_provider, _piStrats[idx]));
        }
    }

    function _deployDefaultStrategy(
        ILendingPoolAddressesProvider _provider,
        LinearStrategy memory _strat
    ) internal returns (DefaultReserveInterestRateStrategy) {
        return new DefaultReserveInterestRateStrategy(
            _provider,
            _strat.optimalUtilizationRate,
            _strat.baseVariableBorrowRate,
            _strat.variableRateSlope1,
            _strat.variableRateSlope2
        );
    }

    function _deployPiInterestStrategy(
        ILendingPoolAddressesProvider _provider,
        PiStrategy memory _strategy
    ) internal returns (PiReserveInterestRateStrategy) {
        return new PiReserveInterestRateStrategy(
            address(_provider),
            _strategy.tokenAddress,
            _strategy.assetReserveType,
            _strategy.minControllerError,
            _strategy.maxITimeAmp,
            _strategy.optimalUtilizationRate,
            _strategy.kp,
            _strategy.ki
        );
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

    function _deployOracle(OracleConfig memory oracleConfig) internal returns (Oracle) {
        Oracle oracle = new Oracle(
            oracleConfig.assets,
            oracleConfig.sources,
            oracleConfig.timeouts,
            oracleConfig.fallbackOracle,
            oracleConfig.baseCurrency,
            oracleConfig.baseCurrencyUnit
        );
        return oracle;
    }

    function _deployTokensAndUtils(LendingPoolAddressesProvider lendingPoolAddressesProvider)
        internal
    {
        contracts.aToken = new AToken();
        contracts.variableDebtToken = new VariableDebtToken();
        // contracts.treasury = new Treasury(lendingPoolAddressesProvider);
    }

    function _deployLendingPoolContracts(address deployer) internal {
        contracts.lendingPoolAddressesProvider = new LendingPoolAddressesProvider();
        console.log("provider's owner: ", contracts.lendingPoolAddressesProvider.owner());

        contracts.lendingPool = new LendingPool();
        contracts.lendingPool.initialize(
            ILendingPoolAddressesProvider(contracts.lendingPoolAddressesProvider)
        );
        contracts.lendingPoolAddressesProvider.setLendingPoolImpl(address(contracts.lendingPool));
        address lendingPoolProxy = address(contracts.lendingPoolAddressesProvider.getLendingPool());
        contracts.lendingPool = LendingPool(lendingPoolProxy);

        contracts.lendingPoolConfigurator = new LendingPoolConfigurator();
        contracts.lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(
            address(contracts.lendingPoolConfigurator)
        );
        address lendingPoolConfiguratorProxy =
            contracts.lendingPoolAddressesProvider.getLendingPoolConfigurator();
        contracts.lendingPoolConfigurator = LendingPoolConfigurator(lendingPoolConfiguratorProxy);
        contracts.aTokensAndRatesHelper = new ATokensAndRatesHelper(
            payable(lendingPoolProxy),
            address(contracts.lendingPoolAddressesProvider),
            lendingPoolConfiguratorProxy
        );

        /* Pause the pool for the time of the deployment */
        contracts.lendingPoolAddressesProvider.setEmergencyAdmin(deployer); // temporary the deployer
        contracts.lendingPoolAddressesProvider.setPoolAdmin(deployer);

        contracts.lendingPoolAddressesProvider.setPriceOracle(address(contracts.oracle));
        contracts.cod3xLendDataProvider = new Cod3xLendDataProvider();
        contracts.cod3xLendDataProvider.setLendingPoolAddressProvider(
            address(contracts.lendingPoolAddressesProvider)
        );
    }

    function _deployMiniPoolContracts(address deployer) internal returns (uint256) {
        contracts.miniPoolImpl.push(new MiniPool());
        contracts.aTokenErc6909.push(new ATokenERC6909());
        uint256 miniPoolId;
        console.log("Mini pool addresses Provider: ", address(contracts.miniPoolAddressesProvider));
        if (address(contracts.miniPoolAddressesProvider) == address(0)) {
            // First deployment so configure miniPool infra

            contracts.miniPoolAddressesProvider =
                new MiniPoolAddressesProvider(contracts.lendingPoolAddressesProvider);
            miniPoolId = contracts.miniPoolAddressesProvider.deployMiniPool(
                address(contracts.miniPoolImpl[contracts.miniPoolImpl.length - 1]),
                address(contracts.aTokenErc6909[contracts.aTokenErc6909.length - 1]),
                deployer
            );
            contracts.flowLimiter = new FlowLimiter(
                IMiniPoolAddressesProvider(address(contracts.miniPoolAddressesProvider)),
                contracts.lendingPool
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
                address(contracts.miniPoolImpl[contracts.miniPoolImpl.length - 1]),
                address(contracts.aTokenErc6909[contracts.aTokenErc6909.length - 1]),
                deployer
            );
        }

        return miniPoolId;
    }

    function _changeStrategies(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig
    ) public {
        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];
            address interestStrategy = _determineInterestStrat(_contracts, reserveConfig);
            _contracts.lendingPoolConfigurator.setReserveInterestRateStrategyAddress(
                reserveConfig.tokenAddress, reserveConfig.reserveType, interestStrategy
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

    function _initAndConfigureReserves(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig,
        General memory _general
    ) internal {
        ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
            new ILendingPoolConfigurator.InitReserveInput[](_reservesConfig.length);

        _contracts.lendingPoolConfigurator.setPoolPause(false);

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

        _configureReserves(_contracts, _reservesConfig);

        _contracts.lendingPoolConfigurator.setPoolPause(true);
    }

    function _configureReserves(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig
    ) internal {
        ATokensAndRatesHelper.ConfigureReserveInput[] memory inputConfigParams =
            new ATokensAndRatesHelper.ConfigureReserveInput[](_reservesConfig.length);

        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];
            inputConfigParams[idx] = ATokensAndRatesHelper.ConfigureReserveInput({
                asset: reserveConfig.tokenAddress,
                reserveType: reserveConfig.reserveType,
                baseLTV: reserveConfig.baseLtv,
                liquidationThreshold: reserveConfig.liquidationThreshold,
                liquidationBonus: reserveConfig.liquidationBonus,
                reserveFactor: reserveConfig.reserveFactor,
                borrowingEnabled: reserveConfig.borrowingEnabled
            });

            _contracts.lendingPoolConfigurator.enableFlashloan(
                reserveConfig.tokenAddress, reserveConfig.reserveType
            );
        }
        address tmpPoolAdmin = _contracts.lendingPoolAddressesProvider.getPoolAdmin();
        _contracts.lendingPoolAddressesProvider.setPoolAdmin(
            address(_contracts.aTokensAndRatesHelper)
        );
        _contracts.aTokensAndRatesHelper.configureReserves(inputConfigParams);
        _contracts.lendingPoolAddressesProvider.setPoolAdmin(tmpPoolAdmin);
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

    function _determineMiniPoolInterestStrat(
        DeployedContracts memory _contracts,
        PoolReserversConfig memory _reserveConfig
    ) internal returns (address) {
        address interestStrategy;
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

    function _initAndConfigureMiniPoolReserves(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig,
        uint256 _miniPoolId
    ) internal returns (address aToken, address miniPool) {
        IMiniPoolConfigurator.InitReserveInput[] memory initInputParams =
            new IMiniPoolConfigurator.InitReserveInput[](_reservesConfig.length);
        address mp = _contracts.miniPoolAddressesProvider.getMiniPool(_miniPoolId);
        console.log("MiniPool to configure: ", mp);
        _contracts.lendingPoolConfigurator.setPoolPause(false);
        _contracts.miniPoolConfigurator.setPoolPause(false, IMiniPool(mp));
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
        _contracts.miniPoolConfigurator.batchInitReserve(initInputParams, IMiniPool(mp));
        console.log("Configuring");
        _configureMiniPoolReserves(_contracts, _reservesConfig, mp);
        _contracts.lendingPoolConfigurator.setPoolPause(true);
        _contracts.miniPoolConfigurator.setPoolPause(true, IMiniPool(mp));
        return (aTokensErc6909Addr, mp);
    }

    function _configureMiniPoolReserves(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig,
        address _mp
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

            _contracts.miniPoolConfigurator.activateReserve(
                reserveConfig.tokenAddress, IMiniPool(_mp)
            );

            _contracts.miniPoolConfigurator.enableBorrowingOnReserve(
                reserveConfig.tokenAddress, IMiniPool(_mp)
            );
            _contracts.miniPoolConfigurator.enableFlashloan(
                reserveConfig.tokenAddress, IMiniPool(_mp)
            );
            _contracts.miniPoolConfigurator.setCod3xReserveFactor(
                reserveConfig.tokenAddress, reserveConfig.reserveFactor, IMiniPool(_mp)
            );
            _contracts.miniPoolConfigurator.setMinipoolOwnerReserveFactor(
                reserveConfig.tokenAddress, reserveConfig.miniPoolOwnerFee, IMiniPool(_mp)
            );
        }
    }

    function _transferOwnershipsAndRenounceRoles(Roles memory roles) internal {
        contracts.lendingPoolAddressesProvider.setPoolAdmin(roles.poolAdmin);
        contracts.aTokensAndRatesHelper.transferOwnership(roles.poolAdmin);
        contracts.lendingPoolAddressesProvider.setEmergencyAdmin(roles.emergencyAdmin);
        contracts.lendingPoolAddressesProvider.transferOwnership(roles.addressesProviderOwner);
        contracts.miniPoolAddressesProvider.transferOwnership(roles.addressesProviderOwner);
        contracts.rewarder.transferOwnership(roles.rewarderOwner);
        contracts.rewarder6909.transferOwnership(roles.rewarderOwner);
        contracts.oracle.transferOwnership(roles.oracleOwner);

        for (uint256 idx = 0; idx < contracts.piStrategies.length; idx++) {
            contracts.piStrategies[idx].transferOwnership(roles.piInterestStrategiesOwner);
        }
        for (uint256 idx = 0; idx < contracts.miniPoolPiStrategies.length; idx++) {
            contracts.miniPoolPiStrategies[idx].transferOwnership(roles.piInterestStrategiesOwner);
        }
    }

    function _transferMiniPoolOwnership(MiniPoolRole memory miniPoolRole) internal {
        IMiniPool mp =
            IMiniPool(contracts.miniPoolAddressesProvider.getMiniPool(miniPoolRole.miniPoolId));
        contracts.miniPoolConfigurator.setMinipoolOwnerTreasuryToMiniPool(
            miniPoolRole.poolOwnerTreasury, mp
        );
        contracts.miniPoolConfigurator.setPoolAdmin(miniPoolRole.newPoolOwner, mp);
    }

    function _deployERC20Mocks(
        string[] memory names,
        string[] memory symbols,
        uint8[] memory decimals,
        int256[] memory prices
    ) internal returns (address[] memory, Oracle) {
        address[] memory tokens = new address[](names.length);
        address[] memory aggregators = new address[](names.length);
        uint256[] memory timeouts = new uint256[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            tokens[i] = address(_deployERC20Mock(names[i], symbols[i], decimals[i]));
            aggregators[i] = address(_deployMockAggregator(tokens[i], prices[i]));
            timeouts[i] = type(uint256).max;
        }
        //mock tokens, mock aggregators, fallbackOracle, baseCurrency, baseCurrencyUnit
        Oracle oracle =
            _deployOracle(tokens, aggregators, timeouts, address(0), address(0), 100000000);
        return (tokens, oracle);
    }

    function _deployERC20Mock(string memory name, string memory symbol, uint8 decimals)
        internal
        returns (MintableERC20)
    {
        MintableERC20 token = new MintableERC20(name, symbol, decimals);
        return token;
    }

    function _deployWETH9Mocked() internal returns (WETH9Mocked) {
        WETH9Mocked weth = new WETH9Mocked();
        return weth;
    }

    function _deployMockAggregator(address token, int256 price) internal returns (MockAggregator) {
        MockAggregator aggregator =
            new MockAggregator(price, int256(int8(MintableERC20(token).decimals())));
        return aggregator;
    }

    function _deployOracle(
        address[] memory assets,
        address[] memory sources,
        uint256[] memory timeouts,
        address fallbackOracle,
        address baseCurrency,
        uint256 baseCurrencyUnit
    ) internal returns (Oracle) {
        Oracle oracle =
            new Oracle(assets, sources, timeouts, fallbackOracle, baseCurrency, baseCurrencyUnit);
        return oracle;
    }

    function _updateOracle(
        Oracle oracle,
        address[] memory assets,
        uint256[] memory timeouts,
        address[] memory sources
    ) internal {
        oracle.setAssetSources(assets, sources, timeouts);
    }

    function _changePeripherials(
        NewPeripherial[] memory treasury,
        NewMiniPoolPeripherial[] memory cod3xTreasury,
        NewPeripherial[] memory vault,
        NewPeripherial[] memory rewarder,
        NewPeripherial[] memory rewarder6909,
        uint256 _miniPoolId
    ) internal {
        require(treasury.length == vault.length, "Lengths of settings must be the same");
        require(treasury.length == rewarder.length, "Lengths settings must be the same");

        for (uint8 idx = 0; idx < treasury.length; idx++) {
            if (treasury[idx].configure == true) {
                (address[] memory list,) = contracts.lendingPool.getReservesList();
                for (uint256 i = 0; i < list.length; i++) {
                    console.log("%s. Address: %s", i, list[i]);
                }
                DataTypes.ReserveData memory data = contracts.lendingPool.getReserveData(
                    treasury[idx].tokenAddress, treasury[idx].reserveType
                );
                require(
                    data.aTokenAddress != address(0), "tokenAddress not available in lendingPool"
                );
                contracts.lendingPoolConfigurator.setTreasury(
                    treasury[idx].tokenAddress, treasury[idx].reserveType, treasury[idx].newAddress
                );
            }
            if (cod3xTreasury[idx].configure == true) {
                IMiniPool tmpMiniPool =
                    IMiniPool(contracts.miniPoolAddressesProvider.getMiniPool(_miniPoolId));
                contracts.miniPoolConfigurator.setCod3xTreasuryToMiniPool(
                    cod3xTreasury[idx].newAddress, tmpMiniPool
                );
            }
            if (vault[idx].configure == true) {
                DataTypes.ReserveData memory data = contracts.lendingPool.getReserveData(
                    vault[idx].tokenAddress, vault[idx].reserveType
                );
                require(
                    data.aTokenAddress != address(0), "tokenAddress not available in lendingPool"
                );
                contracts.lendingPoolConfigurator.setVault(
                    data.aTokenAddress, vault[idx].newAddress
                );
            }
            if (rewarder[idx].configure == true) {
                DataTypes.ReserveData memory data = contracts.lendingPool.getReserveData(
                    rewarder[idx].tokenAddress, rewarder[idx].reserveType
                );
                require(
                    data.aTokenAddress != address(0), "tokenAddress not available in lendingPool"
                );
                if (address(AToken(data.aTokenAddress).getIncentivesController()) == address(0)) {
                    if (address(contracts.rewarder) == address(0)) {
                        // There is no rewarder -> deploy new one
                        contracts.rewarder = new Rewarder(); // @issue: Rewarder NOT SAFE
                    }

                    contracts.lendingPoolConfigurator.setRewarderForReserve(
                        rewarder[idx].tokenAddress,
                        rewarder[idx].reserveType,
                        address(contracts.rewarder)
                    );
                } else {
                    // Set rewarder defined in config
                    contracts.lendingPoolConfigurator.setRewarderForReserve(
                        rewarder[idx].tokenAddress,
                        rewarder[idx].reserveType,
                        rewarder[idx].newAddress
                    );
                }
            }
            if (rewarder6909[idx].configure == true) {
                address mp = contracts.miniPoolAddressesProvider.getMiniPool(_miniPoolId);
                DataTypes.MiniPoolReserveData memory data =
                    IMiniPool(mp).getReserveData(rewarder6909[idx].tokenAddress);
                require(
                    data.aTokenAddress != address(0), "tokenAddress not available in lendingPool"
                );
                if (
                    address(ATokenERC6909(data.aTokenAddress).getIncentivesController())
                        == address(0)
                ) {
                    if (address(contracts.rewarder6909) == address(0)) {
                        // There is no rewarder -> deploy new one
                        contracts.rewarder6909 = new Rewarder6909();
                    }
                    contracts.miniPoolConfigurator.setRewarderForReserve(
                        rewarder6909[idx].tokenAddress,
                        address(contracts.rewarder6909),
                        IMiniPool(mp)
                    );
                } else {
                    // Set rewarder defined in config
                    contracts.miniPoolConfigurator.setRewarderForReserve(
                        rewarder6909[idx].tokenAddress,
                        address(rewarder6909[idx].newAddress),
                        IMiniPool(mp)
                    );
                }
            }
        }
    }

    function _turnOnRehypothecation(Rehypothecation[] memory rehypothecationSettings) internal {
        for (uint8 idx = 0; idx < rehypothecationSettings.length; idx++) {
            Rehypothecation memory rehypothecationSetting = rehypothecationSettings[idx];
            if (rehypothecationSetting.configure == true) {
                DataTypes.ReserveData memory reserveData = contracts.lendingPool.getReserveData(
                    rehypothecationSetting.tokenAddress, rehypothecationSetting.reserveType
                );
                require(
                    reserveData.aTokenAddress != address(0),
                    "aTokenAddress not available in lendingPool"
                );
                if (address(AToken(reserveData.aTokenAddress).vault()) == address(0)) {
                    contracts.lendingPoolConfigurator.setVault(
                        reserveData.aTokenAddress, rehypothecationSetting.vault
                    );
                }

                contracts.lendingPoolConfigurator.setFarmingPct(
                    reserveData.aTokenAddress, rehypothecationSetting.farmingPct
                );
                contracts.lendingPoolConfigurator.setClaimingThreshold(
                    reserveData.aTokenAddress, rehypothecationSetting.claimingThreshold
                );
                contracts.lendingPoolConfigurator.setFarmingPctDrift(
                    reserveData.aTokenAddress, rehypothecationSetting.drift
                );
                contracts.lendingPoolConfigurator.setProfitHandler(
                    reserveData.aTokenAddress, rehypothecationSetting.profitHandler
                );
            }
        }
    }
}
