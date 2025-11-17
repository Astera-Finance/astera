// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IReserveInterestRateStrategy} from
    "../../../../../contracts/interfaces/IReserveInterestRateStrategy.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {ILendingPoolAddressesProvider} from
    "../../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title FixReserveInterestRateStrategy contract.
 * @notice Implements fix interest rate strategy.
 * @dev The rate is controlled by `updateBorrowRate` (an admin restricted function).
 * @author Conclave - Beirao
 */
contract FixReserveInterestRateStrategy is IReserveInterestRateStrategy {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    /// @dev The interest rate.
    uint256 public immutable OPTIMAL_UTILIZATION_RATE;

    /**
     * @notice Initializes the interest rate strategy contract.
     * @param borrowRate The initial borrow rate.
     */
    constructor(uint256 borrowRate) {
        OPTIMAL_UTILIZATION_RATE = borrowRate;
    }

    /// @dev Only for compatibility with data providers.
    function variableRateSlope1() external view returns (uint256) {
        return 0;
    }

    /// @dev Only for compatibility with data providers.
    function variableRateSlope2() external view returns (uint256) {
        return 0;
    }

    /// @notice Returns the base variable borrow rate.
    function baseVariableBorrowRate() external view override returns (uint256) {
        return OPTIMAL_UTILIZATION_RATE;
    }

    /// @notice Returns the maximum variable borrow rate.
    function getMaxVariableBorrowRate() external view override returns (uint256) {
        return OPTIMAL_UTILIZATION_RATE;
    }

    /**
     * @notice Calculates the interest rates depending on the reserve's state and configurations.
     * @param asset The address of the asset.
     * @param aToken The address of the reserve aToken.
     * @param liquidityAdded The liquidity added during the operation.
     * @param liquidityTaken The liquidity taken during the operation.
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate.
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market.
     * @return The liquidity rate and the variable borrow rate.
     */
    function calculateInterestRates(
        address asset,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external view override returns (uint256, uint256) {
        uint256 availableLiquidity = IAToken(aToken).getTotalManagedAssets();
        if (availableLiquidity + liquidityAdded < liquidityTaken) {
            revert(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW);
        }
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;

        return calculateInterestRates(asset, availableLiquidity, totalVariableDebt, reserveFactor);
    }

    /**
     * @notice Calculates the interest rates depending on the reserve's state and configurations.
     * @dev This function is kept for compatibility with the previous DefaultInterestRateStrategy interface.
     * New protocol implementation uses the new calculateInterestRates() interface.
     * @param availableLiquidity The liquidity available in the corresponding aToken.
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate.
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market.
     * @return The liquidity rate and the variable borrow rate.
     */
    function calculateInterestRates(
        address,
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) public view returns (uint256, uint256) {
        uint256 currentBorrowRate = OPTIMAL_UTILIZATION_RATE;
        uint256 utilizationRate = totalVariableDebt == 0
            ? 0
            : totalVariableDebt.rayDiv(availableLiquidity + totalVariableDebt);

        uint256 currentLiquidityRate = currentBorrowRate.rayMul(utilizationRate).percentMul(
            PercentageMath.PERCENTAGE_FACTOR - reserveFactor
        );

        return (currentLiquidityRate, currentBorrowRate);
    }
}
