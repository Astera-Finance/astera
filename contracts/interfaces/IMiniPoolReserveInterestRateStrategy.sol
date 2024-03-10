// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

/**
 * @title IReserveInterestRateStrategyInterface interface
 * @dev Interface for the calculation of the interest rates
 * @author Aave
 */
interface IMiniPoolReserveInterestRateStrategy {
  function baseVariableBorrowRate() external view returns (uint256);

  function getMaxVariableBorrowRate() external view returns (uint256);

  function calculateInterestRates(
    address reserve,
    uint256 availableLiquidity,
    uint256 totalVariableDebt,
    uint256 reserveFactor
  )
    external
    view
    returns (
      uint256,
      uint256
    );

  function calculateInterestRates(
    address reserve,
    address aToken,
    uint256 liquidityAdded,
    uint256 liquidityTaken,
    uint256 totalVariableDebt,
    uint256 reserveFactor
  )
    external
    view
    returns (
      uint256 liquidityRate,
      uint256 variableBorrowRate
    );

struct augmentedInterestRateParams{
    uint256 totalVariableDebt;
    uint256 availableLiquidity;
    uint256 totalAvailableBackstopLiquidity;
    uint256 utilizedBackstopLiquidity;
    uint128 underlyingLiqRate;
    uint128 underlyingVarRate;
    uint256 reserveFactor;
  }

function calculateAugmentedInterestRate(
    augmentedInterestRateParams memory params
  ) external view returns (uint256, uint256);
}
