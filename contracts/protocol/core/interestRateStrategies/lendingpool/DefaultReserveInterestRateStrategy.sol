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
 * @title DefaultReserveInterestRateStrategy contract.
 * @notice Implements the calculation of the interest rates depending on the reserve state.
 * @dev The model of interest rate is based on 2 slopes, one before the `OPTIMAL_UTILIZATION_RATE`
 * point of utilization and another from that one to 100%.
 * - An instance of this same contract, can't be used across different Astera markets, due to the caching
 *   of the `LendingPoolAddressesProvider`.
 * @author Conclave
 */
contract DefaultReserveInterestRateStrategy is IReserveInterestRateStrategy {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    /**
     * @dev This constant represents the utilization rate at which the pool aims to obtain most competitive borrow rates.
     * Expressed in ray.
     */
    uint256 public immutable OPTIMAL_UTILIZATION_RATE;

    /**
     * @dev This constant represents the excess utilization rate above the optimal. It's always equal to
     * 1-optimal utilization rate. Added as a constant here for gas optimizations.
     * Expressed in ray.
     */
    uint256 public immutable EXCESS_UTILIZATION_RATE;

    /// @dev Address of the lending pool addresses provider.
    ILendingPoolAddressesProvider public immutable addressesProvider;

    /// @dev Base variable borrow rate when Utilization rate = 0. Expressed in ray.
    uint256 internal immutable _baseVariableBorrowRate;

    /// @dev Slope of the variable interest curve when utilization rate > 0 and <= `OPTIMAL_UTILIZATION_RATE`. Expressed in ray.
    uint256 internal immutable _variableRateSlope1;

    /// @dev Slope of the variable interest curve when utilization rate > `OPTIMAL_UTILIZATION_RATE`. Expressed in ray.
    uint256 internal immutable _variableRateSlope2;

    /**
     * @notice Initializes the interest rate strategy contract.
     * @param provider_ Address of the lending pool addresses provider.
     * @param optimalUtilizationRate_ The optimal utilization rate.
     * @param baseVariableBorrowRate_ The base variable borrow rate.
     * @param variableRateSlope1_ The variable rate slope below optimal utilization.
     * @param variableRateSlope2_ The variable rate slope above optimal utilization.
     */
    constructor(
        ILendingPoolAddressesProvider provider_,
        uint256 optimalUtilizationRate_,
        uint256 baseVariableBorrowRate_,
        uint256 variableRateSlope1_,
        uint256 variableRateSlope2_
    ) {
        OPTIMAL_UTILIZATION_RATE = optimalUtilizationRate_;
        EXCESS_UTILIZATION_RATE = WadRayMath.ray() - optimalUtilizationRate_;
        addressesProvider = provider_;
        _baseVariableBorrowRate = baseVariableBorrowRate_;
        _variableRateSlope1 = variableRateSlope1_;
        _variableRateSlope2 = variableRateSlope2_;
    }

    /// @notice Returns the slope of the variable interest rate below optimal utilization.
    function variableRateSlope1() external view returns (uint256) {
        return _variableRateSlope1;
    }

    /// @notice Returns the slope of the variable interest rate above optimal utilization.
    function variableRateSlope2() external view returns (uint256) {
        return _variableRateSlope2;
    }

    /// @notice Returns the base variable borrow rate.
    function baseVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate;
    }

    /// @notice Returns the maximum variable borrow rate.
    function getMaxVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate + _variableRateSlope1 + _variableRateSlope2;
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
     * @dev Local variables struct used for interest rate calculation.
     */
    struct CalcInterestRatesLocalVars {
        uint256 totalDebt;
        uint256 currentVariableBorrowRate;
        uint256 currentLiquidityRate;
        uint256 utilizationRate;
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
        CalcInterestRatesLocalVars memory vars;

        vars.totalDebt = totalVariableDebt;
        vars.currentVariableBorrowRate = 0;
        vars.currentLiquidityRate = 0;

        vars.utilizationRate =
            vars.totalDebt == 0 ? 0 : vars.totalDebt.rayDiv(availableLiquidity + vars.totalDebt);

        if (vars.utilizationRate > OPTIMAL_UTILIZATION_RATE) {
            uint256 excessUtilizationRateRatio =
                (vars.utilizationRate - OPTIMAL_UTILIZATION_RATE).rayDiv(EXCESS_UTILIZATION_RATE);

            vars.currentVariableBorrowRate = _baseVariableBorrowRate + _variableRateSlope1
                + _variableRateSlope2.rayMul(excessUtilizationRateRatio);
        } else {
            vars.currentVariableBorrowRate = _baseVariableBorrowRate
                + vars.utilizationRate.rayMul(_variableRateSlope1).rayDiv(OPTIMAL_UTILIZATION_RATE);
        }

        vars.currentLiquidityRate = vars.currentVariableBorrowRate.rayMul(vars.utilizationRate)
            .percentMul(PercentageMath.PERCENTAGE_FACTOR - reserveFactor);

        return (vars.currentLiquidityRate, vars.currentVariableBorrowRate);
    }
}
