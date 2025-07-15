// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "contracts/misc/AsteraLendDataProvider2.sol";

import
    "contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import
    "contracts/protocol/core/interestRateStrategies/lendingpool/PiReserveInterestRateStrategy.sol";
import "contracts/protocol/core/lendingpool/LendingPool.sol";
import "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";

import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

import "scripts/helpers/InitAndConfigurationHelper.s.sol";

contract LendingPoolHelper is InitAndConfigurationHelper {
    function deployLendingPoolInfra(
        General memory _general,
        LinearStrategy[] memory _volatileStrats,
        LinearStrategy[] memory _stableStrats,
        PiStrategy[] memory _piStrategies,
        PoolReserversConfig[] memory _poolReserversConfig,
        OracleConfig memory _oracleConfig,
        address _deployer,
        address _wethGateway
    ) public {
        _deployLendingPoolContracts(_deployer, _general, _wethGateway, _oracleConfig);

        _deployStrategies(
            contracts.lendingPoolAddressesProvider, _volatileStrats, _stableStrats, _piStrategies
        );
        _deployTokensAndUtils(contracts.lendingPoolAddressesProvider);

        _initAndConfigureReserves(contracts, _poolReserversConfig, _general);
    }

    function _deployLendingPoolContracts(
        address deployer,
        General memory general,
        address wethGateway,
        OracleConfig memory _oracleConfig
    ) internal {
        contracts.lendingPoolAddressesProvider = new LendingPoolAddressesProvider();
        console2.log("provider's owner: ", contracts.lendingPoolAddressesProvider.owner());

        contracts.lendingPool = new LendingPool();
        // contracts.lendingPool.initialize(
        //     ILendingPoolAddressesProvider(contracts.lendingPoolAddressesProvider)
        // );
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

        /* Pause the pool for the time of the deployment */
        contracts.lendingPoolAddressesProvider.setEmergencyAdmin(deployer); // temporary the deployer
        contracts.lendingPoolAddressesProvider.setPoolAdmin(deployer);

        contracts.oracle = _deployOracle(_oracleConfig);
        contracts.lendingPoolAddressesProvider.setPriceOracle(address(contracts.oracle));
        contracts.asteraLendDataProvider = new AsteraLendDataProvider2(
            general.networkBaseTokenAggregator, general.marketReferenceCurrencyAggregator
        );
        contracts.asteraLendDataProvider.setLendingPoolAddressProvider(
            address(contracts.lendingPoolAddressesProvider)
        );
        contracts.wethGateway = new WETHGateway(wethGateway);
        contracts.wethGateway.authorizeLendingPool(address(contracts.lendingPool));
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

    function _deployTokensAndUtils(LendingPoolAddressesProvider lendingPoolAddressesProvider)
        internal
    {
        contracts.aToken = new AToken();
        contracts.variableDebtToken = new VariableDebtToken();
        // contracts.treasury = new Treasury(lendingPoolAddressesProvider);
    }

    function _deployOracle(OracleConfig memory oracleConfig) internal returns (Oracle) {
        Oracle oracle = new Oracle(
            oracleConfig.assets,
            oracleConfig.sources,
            oracleConfig.timeouts,
            oracleConfig.fallbackOracle,
            oracleConfig.baseCurrency,
            oracleConfig.baseCurrencyUnit,
            address(contracts.lendingPoolAddressesProvider)
        );
        return oracle;
    }
}
