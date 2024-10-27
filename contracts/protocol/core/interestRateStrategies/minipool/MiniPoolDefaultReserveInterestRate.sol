// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IMiniPoolReserveInterestRateStrategy} from
    "../../../../../contracts/interfaces/IMiniPoolReserveInterestRateStrategy.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {ILendingPoolAddressesProvider} from
    "../../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IFlowLimiter} from "../../../../../contracts/interfaces/IFlowLimiter.sol";
import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {IAERC6909} from "../../../../../contracts/interfaces/IAERC6909.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {MathUtils} from "../../../../../contracts/protocol/libraries/math/MathUtils.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {ILendingPool} from "../../../../../contracts/interfaces/ILendingPool.sol";

/**
 * @title DefaultReserveInterestRateStrategy contract
 * @notice Implements the calculation of the interest rates depending on the reserve state
 * @dev The model of interest rate is based on 2 slopes, one before the `OPTIMAL_UTILIZATION_RATE`
 * point of utilization and another from that one to 100%
 * - An instance of this same contract, can't be used across different Aave markets, due to the caching
 *   of the MiniPoolAddressesProvider
 * @author Cod3x
 *
 */
contract MiniPoolDefaultReserveInterestRateStrategy is IMiniPoolReserveInterestRateStrategy {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 public constant DELTA_TIME_MARGIN = 5 days;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /**
     * @dev this constant represents the utilization rate at which the pool aims to obtain most competitive borrow rates.
     * Expressed in ray
     *
     */
    uint256 public immutable OPTIMAL_UTILIZATION_RATE;

    /**
     * @dev This constant represents the excess utilization rate above the optimal. It's always equal to
     * 1-optimal utilization rate. Added as a constant here for gas optimizations.
     * Expressed in ray
     *
     */
    uint256 public immutable EXCESS_UTILIZATION_RATE;

    IMiniPoolAddressesProvider public immutable _addressesProvider;

    // Base variable borrow rate when Utilization rate = 0. Expressed in ray
    uint256 internal immutable _baseVariableBorrowRate;

    // Slope of the variable interest curve when utilization rate > 0 and <= OPTIMAL_UTILIZATION_RATE. Expressed in ray
    uint256 internal immutable _variableRateSlope1;

    // Slope of the variable interest curve when utilization rate > OPTIMAL_UTILIZATION_RATE. Expressed in ray
    uint256 internal immutable _variableRateSlope2;

    constructor(
        IMiniPoolAddressesProvider provider_,
        uint256 optimalUtilizationRate_,
        uint256 baseVariableBorrowRate_,
        uint256 variableRateSlope1_,
        uint256 variableRateSlope2_
    ) {
        OPTIMAL_UTILIZATION_RATE = optimalUtilizationRate_;
        EXCESS_UTILIZATION_RATE = WadRayMath.ray() - optimalUtilizationRate_;
        _addressesProvider = provider_;
        _baseVariableBorrowRate = baseVariableBorrowRate_;
        _variableRateSlope1 = variableRateSlope1_;
        _variableRateSlope2 = variableRateSlope2_;
    }

    function variableRateSlope1() external view returns (uint256) {
        return _variableRateSlope1;
    }

    function variableRateSlope2() external view returns (uint256) {
        return _variableRateSlope2;
    }

    function baseVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate;
    }

    function getMaxVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate + _variableRateSlope1 + _variableRateSlope2;
    }

    struct CalcInterestRatesLocalVars1 {
        uint256 availableLiquidity;
        address underlying;
        uint256 currentFlow;
        bool isTranched;
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations
     * @param reserve The address of the reserve
     * @param aToken The address of the reserve aToken
     * @param liquidityAdded The liquidity added during the operation
     * @param liquidityTaken The liquidity taken during the operation
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
     * @return The liquidity rate and the variable borrow rate
     *
     */
    function calculateInterestRates(
        address reserve,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external view override returns (uint256, uint256) {
        CalcInterestRatesLocalVars1 memory vars;

        (,, vars.isTranched,) = IAERC6909(aToken).getIdForUnderlying(reserve);
        if (vars.isTranched) {
            IFlowLimiter flowLimiter = IFlowLimiter(_addressesProvider.getFlowLimiter());
            vars.underlying = IAToken(reserve).UNDERLYING_ASSET_ADDRESS();
            address minipool = IAERC6909(aToken).MINIPOOL_ADDRESS();
            vars.currentFlow = flowLimiter.currentFlow(vars.underlying, minipool);

            vars.availableLiquidity = IERC20(reserve).balanceOf(aToken)
                + IAToken(reserve).convertToShares(flowLimiter.getFlowLimit(vars.underlying, minipool))
                - IAToken(reserve).convertToShares(vars.currentFlow);
        } else {
            vars.availableLiquidity = IERC20(reserve).balanceOf(aToken);
        }

        if (vars.availableLiquidity + liquidityAdded < liquidityTaken) {
            revert(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW);
        }

        //avoid stack too deep
        vars.availableLiquidity = vars.availableLiquidity + liquidityAdded - liquidityTaken;

        return calculateInterestRates(
            vars.underlying,
            vars.currentFlow,
            vars.availableLiquidity,
            totalVariableDebt,
            reserveFactor
        );
    }

    struct CalcInterestRatesLocalVars2 {
        uint256 totalDebt;
        uint256 currentVariableBorrowRate;
        uint256 currentLiquidityRate;
        uint256 utilizationRate;
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations.
     * NOTE This function is kept for compatibility with the previous DefaultInterestRateStrategy interface.
     * New protocol implementation uses the new calculateInterestRates() interface
     * @param underlying Underlying asset if reserve is an aToken.
     * @param currentFlow Current minipool Flow.
     * @param availableLiquidity The liquidity available in the corresponding aToken
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
     * @return The liquidity rateand the variable borrow rate
     *
     */
    function calculateInterestRates(
        address underlying,
        uint256 currentFlow,
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) public view returns (uint256, uint256) {
        CalcInterestRatesLocalVars2 memory vars;

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

        // Here we make sure that the minipool can always repay its debt to the lendingpool.
        // https://www.desmos.com/calculator/3bigkgqbqg
        if (currentFlow != 0) {
            DataTypes.ReserveData memory r =
                ILendingPool(_addressesProvider.getLendingPool()).getReserveData(underlying, true);

            uint256 minLiquidityRate = (
                MathUtils.calculateCompoundedInterest(
                    r.currentVariableBorrowRate, uint40(block.timestamp - DELTA_TIME_MARGIN)
                ) - r.currentLiquidityRate * DELTA_TIME_MARGIN / SECONDS_PER_YEAR - WadRayMath.ray()
            ).rayDiv(
                DELTA_TIME_MARGIN
                    * (
                        (r.currentLiquidityRate * DELTA_TIME_MARGIN / SECONDS_PER_YEAR)
                            + WadRayMath.ray()
                    ) / SECONDS_PER_YEAR
            ).percentMul(10_100); // * 101% => +1% safety margin.

            // `&& vars.utilizationRate != 0` to avoid 0 division. It's safe since the minipool flow is
            // always owed to a user. Since the debt is repaid as soon as possible if
            // `vars.utilizationRate != 0` then `currentFlow == 0` by the end of the transaction.
            if (vars.currentLiquidityRate < minLiquidityRate && vars.utilizationRate != 0) {
                vars.currentLiquidityRate = minLiquidityRate;
                vars.currentVariableBorrowRate = vars.currentLiquidityRate.rayDiv(
                    vars.utilizationRate.percentMul(
                        PercentageMath.PERCENTAGE_FACTOR - reserveFactor
                    )
                );
            }
        }

        return (vars.currentLiquidityRate, vars.currentVariableBorrowRate);
    }
}
