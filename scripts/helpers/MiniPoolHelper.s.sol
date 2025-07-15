// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolPiReserveInterestRateStrategy.sol";
import "contracts/protocol/core/lendingpool/LendingPool.sol";
import "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import "contracts/protocol/core/minipool/MiniPool.sol";
import "contracts/protocol/core/minipool/FlowLimiter.sol";
import "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import "scripts/helpers/InitAndConfigurationHelper.s.sol";

contract MiniPoolHelper is InitAndConfigurationHelper {
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
        console2.log("Mini pool addresses Provider: ", address(contracts.miniPoolAddressesProvider));
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
            contracts.asteraLendDataProvider.setMiniPoolAddressProvider(
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
}
