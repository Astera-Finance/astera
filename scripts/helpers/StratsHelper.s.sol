// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import
    "contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import
    "contracts/protocol/core/interestRateStrategies/lendingpool/PiReserveInterestRateStrategy.sol";

import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import "contracts/mocks/oracle/PriceOracle.sol";
import "../DeployDataTypes.sol";

import "forge-std/console.sol";

contract StratsHelper {
    address constant FOUNDRY_DEFAULT = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    DeployedContracts contracts;

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
}
