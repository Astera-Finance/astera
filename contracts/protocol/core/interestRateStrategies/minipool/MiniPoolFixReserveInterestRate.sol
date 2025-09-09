// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IMiniPoolReserveInterestRateStrategy} from
    "../../../../../contracts/interfaces/IMiniPoolReserveInterestRateStrategy.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {IAERC6909} from "../../../../../contracts/interfaces/IAERC6909.sol";
import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";

/**
 * @title FixReserveInterestRateStrategy contract.
 * @notice Implements fix interest rate strategy.
 * @dev The rate is controlled by `updateBorrowRate` (an admin restricted function).
 * @dev ATTENTION: THIS STRATEGY IS NOT COMPATIBLE WITH TRANCHED ASSETS.
 * @author Conclave - Beirao
 */
contract MiniPoolFixReserveInterestRate is IMiniPoolReserveInterestRateStrategy {
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
        (,, bool isTranched) = IAERC6909(aToken).getIdForUnderlying(asset);

        uint256 availableLiquidity = IERC20(asset).balanceOf(aToken);

        if (isTranched) {
            revert(Errors.VL_TRANCHED_ASSETS_NOT_SUPPORTED_WITH_FIX_RATE);
        }

        if (availableLiquidity + liquidityAdded < liquidityTaken) {
            revert(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW);
        }

        //avoid stack too deep
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;

        return calculateInterestRates(
            address(0), 0, availableLiquidity, totalVariableDebt, reserveFactor
        );
    }

    /**
     * @notice Calculates the interest rates depending on the reserve's state and configurations.
     * @dev This function is kept for compatibility with the previous DefaultInterestRateStrategy interface.
     * New protocol implementation uses the new calculateInterestRates() interface.
     * @param underlying Underlying asset if reserve is an aToken.
     * @param currentFlow Current minipool Flow.
     * @param availableLiquidity The liquidity available in the corresponding aToken.
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate.
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market.
     * @return The liquidity rate and the variable borrow rate.
     */
    function calculateInterestRates(
        address underlying,
        uint256 currentFlow,
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) public view returns (uint256, uint256) {
        uint256 utilizationRate = totalVariableDebt == 0
            ? 0
            : totalVariableDebt.rayDiv(availableLiquidity + totalVariableDebt);

        uint256 currentLiquidityRate = OPTIMAL_UTILIZATION_RATE.rayMul(utilizationRate).percentMul(
            PercentageMath.PERCENTAGE_FACTOR - reserveFactor
        );

        if (currentFlow != 0 || underlying != address(0)) {
            revert(Errors.VL_TRANCHED_ASSETS_NOT_SUPPORTED_WITH_FIX_RATE);
        }

        return (currentLiquidityRate, OPTIMAL_UTILIZATION_RATE);
    }
}
