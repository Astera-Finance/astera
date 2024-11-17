// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IMiniPoolAddressesProvider} from
    "../../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IAERC6909} from "../../../../../contracts/interfaces/IAERC6909.sol";
import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {IMiniPool} from "../../../../../contracts/interfaces/IMiniPool.sol";
import {IFlowLimiter} from "../../../../../contracts/interfaces/IFlowLimiter.sol";
import {IMiniPoolReserveInterestRateStrategy} from
    "../../../../../contracts/interfaces/IMiniPoolReserveInterestRateStrategy.sol";
import {
    BasePiReserveRateStrategy,
    WadRayMath,
    PercentageMath,
    DataTypes
} from "../../../../../contracts/protocol/core/interestRateStrategies/BasePiReserveRateStrategy.sol";
import {MathUtils} from "../../../../../contracts/protocol/libraries/math/MathUtils.sol";
import {ILendingPool} from "../../../../../contracts/interfaces/ILendingPool.sol";
/**
 * @title PiReserveInterestRateStrategy contract
 * @notice Implements the calculation of the interest rates using control theory.
 * @dev The model of interest rate is based Proportional Integrator (PI).
 * Admin needs to set an optimal utilization rate and this strategy will automatically
 * automatically adjust the interest rate according to the `Kp` and `Ki` variables.
 * @dev ATTENTION, this contract must no be used as a library. One PiReserveInterestRateStrategy
 * needs to be associated with only one market.
 * @author Cod3x
 */

contract MiniPoolPiReserveInterestRateStrategy is
    BasePiReserveRateStrategy,
    IMiniPoolReserveInterestRateStrategy
{
    using WadRayMath for uint256;
    using WadRayMath for int256;
    using PercentageMath for uint256;

    uint256 public constant DELTA_TIME_MARGIN = 5 days;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    uint256 public _minipoolId;

    constructor(
        address provider,
        uint256 minipoolId,
        address asset,
        bool assetReserveType,
        int256 minControllerError,
        int256 maxITimeAmp,
        uint256 optimalUtilizationRate,
        uint256 kp,
        uint256 ki
    )
        BasePiReserveRateStrategy(
            provider,
            asset,
            assetReserveType,
            minControllerError,
            maxITimeAmp,
            optimalUtilizationRate,
            kp,
            ki
        )
    {
        _minipoolId = minipoolId;
    }

    function _getLendingPool() internal view override returns (address) {
        return IMiniPoolAddressesProvider(_addressProvider).getMiniPool(_minipoolId);
    }

    function getAvailableLiquidity(address asset, address aToken)
        public
        view
        override
        returns (uint256 availableLiquidity, address underlying, uint256 currentFlow)
    {
        (,, bool isTranched) = IAERC6909(aToken).getIdForUnderlying(asset);

        if (isTranched) {
            IFlowLimiter flowLimiter =
                IFlowLimiter(IMiniPoolAddressesProvider(_addressProvider).getFlowLimiter());
            underlying = IAToken(asset).UNDERLYING_ASSET_ADDRESS();
            address minipool = IAERC6909(aToken).MINIPOOL_ADDRESS();
            currentFlow = flowLimiter.currentFlow(underlying, minipool);

            availableLiquidity = IERC20(asset).balanceOf(aToken)
                + IAToken(asset).convertToShares(flowLimiter.getFlowLimit(underlying, minipool))
                - IAToken(asset).convertToShares(currentFlow);
        } else {
            availableLiquidity = IERC20(asset).balanceOf(aToken);
        }
    }

    // ----------- view -----------

    /**
     * @notice The view version of `calculateInterestRates()`.
     * @return currentLiquidityRate
     * @return currentVariableBorrowRate
     * @return utilizationRate
     */
    function getCurrentInterestRates() public view override returns (uint256, uint256, uint256) {
        // utilization
        IAERC6909 aErc6909Token = IAERC6909(
            IMiniPoolAddressesProvider(_addressProvider).getMiniPoolToAERC6909(_getLendingPool())
        );
        DataTypes.MiniPoolReserveData memory reserve =
            IMiniPool(_getLendingPool()).getReserveData(_asset);
        uint256 availableLiquidity = IERC20(_asset).balanceOf(reserve.aTokenAddress);
        uint256 totalVariableDebt = aErc6909Token.totalSupply(reserve.variableDebtTokenID);
        uint256 utilizationRate = totalVariableDebt == 0
            ? 0
            : totalVariableDebt.rayDiv(availableLiquidity + totalVariableDebt);

        // borrow rate
        uint256 currentVariableBorrowRate =
            transferFunction(getControllerError(getNormalizedError(utilizationRate)));

        // liquity rate
        uint256 currentLiquidityRate = getLiquidityRate(
            currentVariableBorrowRate, utilizationRate, getCod3xReserveFactor(reserve.configuration)
        );
        return (currentLiquidityRate, currentVariableBorrowRate, utilizationRate);
    }

    // ----------- view -----------

    function baseVariableBorrowRate() public view override returns (uint256) {
        return uint256(transferFunction(type(int256).min));
    }

    function getMaxVariableBorrowRate() external pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations
     * @param asset The address of the asset
     * @param aToken The address of the reserve aToken
     * @param liquidityAdded The liquidity added during the operation
     * @param liquidityTaken The liquidity taken during the operation
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
     * @return currentLiquidityRate The liquidity rate
     * @return currentVariableBorrowRate The variable borrow rate
     */
    function calculateInterestRates(
        address asset,
        address aToken,
        uint256 liquidityAdded, //! since this function is not view anymore we need to make sure liquidityAdded is added at the end
        uint256 liquidityTaken, //! since this function is not view anymore we need to make sure liquidityTaken is removed at the end
        uint256 totalVariableDebt,
        uint256 reserveFactor
    )
        external
        override
        onlyLendingPool
        returns (uint256 currentLiquidityRate, uint256 currentVariableBorrowRate)
    {
        uint256 utilizationRate;
        address underlying;
        uint256 currentFlow;
        (currentLiquidityRate, currentVariableBorrowRate, utilizationRate, underlying, currentFlow)
        = _calculateInterestRates(
            asset, aToken, liquidityAdded, liquidityTaken, totalVariableDebt, reserveFactor
        );

        // Here we make sure that the minipool can always repay its debt to the lendingpool.
        // https://www.desmos.com/calculator/3bigkgqbqg
        if (currentFlow != 0) {
            DataTypes.ReserveData memory r = ILendingPool(
                IMiniPoolAddressesProvider(_addressProvider).getLendingPool()
            ).getReserveData(underlying, true);

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
            );

            // `&& utilizationRate != 0` to avoid 0 division. It's safe since the minipool flow is
            // always owed to a user. Since the debt is repaid as soon as possible if
            // `utilizationRate != 0` then `currentFlow == 0` by the end of the transaction.
            if (currentLiquidityRate < minLiquidityRate && utilizationRate != 0) {
                currentLiquidityRate = minLiquidityRate;
                currentVariableBorrowRate = currentLiquidityRate.rayDiv(
                    utilizationRate.percentMul(PercentageMath.PERCENTAGE_FACTOR - reserveFactor)
                );
            }
        }
    }
}
