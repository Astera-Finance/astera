// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IMiniPoolAddressesProvider} from
    "../../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IAERC6909} from "../../../../../contracts/interfaces/IAERC6909.sol";
import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {IMiniPool} from "../../../../../contracts/interfaces/IMiniPool.sol";
import {IFlowLimiter} from "../../../../../contracts/interfaces/base/IFlowLimiter.sol";
import {IMiniPoolReserveInterestRateStrategy} from
    "../../../../../contracts/interfaces/IMiniPoolReserveInterestRateStrategy.sol";
import {BasePiReserveRateStrategy} from
    "../../../../../contracts/protocol/core/interestRateStrategies/BasePiReserveRateStrategy.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {MathUtils} from "../../../../../contracts/protocol/libraries/math/MathUtils.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {ILendingPool} from "../../../../../contracts/interfaces/ILendingPool.sol";
import {ReserveConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

/**
 * @title MiniPoolPiReserveInterestRateStrategy contract.
 * @notice Implements the calculation of the interest rates using control theory.
 * @dev The model of interest rate is based on Proportional Integrator (PI).
 * Admin needs to set an optimal utilization rate and this strategy will automatically
 * adjust the interest rate according to the `_kp` and `_ki` variables.
 * @dev ATTENTION: This contract must not be used as a library. One MiniPoolPiReserveInterestRateStrategy
 * needs to be associated with only one market.
 * @author Conclave
 */
contract MiniPoolPiReserveInterestRateStrategy is
    BasePiReserveRateStrategy,
    IMiniPoolReserveInterestRateStrategy
{
    using WadRayMath for uint256;
    using WadRayMath for int256;
    using PercentageMath for uint256;

    /// @dev Time margin used for interest rate calculations, set to 5 days.
    uint256 public constant DELTA_TIME_MARGIN = 5 days;

    /// @dev Number of seconds in a year.
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @dev ID of the minipool this strategy is associated with.
    uint256 public immutable _minipoolId;

    /**
     * @notice Initializes the MiniPoolPiReserveInterestRateStrategy contract.
     * @param provider Address of the lending pool provider.
     * @param minipoolId ID of the minipool this strategy is for.
     * @param asset Address of the asset this strategy is for.
     * @param assetReserveType Type of the asset reserve.
     * @param minControllerError Minimum allowed controller error.
     * @param maxITimeAmp Maximum integral time amplitude.
     * @param optimalUtilizationRate Target utilization rate.
     * @param kp Proportional gain coefficient.
     * @param ki Integral gain coefficient.
     */
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

    /// @inheritdoc BasePiReserveRateStrategy
    function _getLendingPool() internal view override returns (address) {
        return IMiniPoolAddressesProvider(_addressProvider).getMiniPool(_minipoolId);
    }

    /// @inheritdoc BasePiReserveRateStrategy
    function getAvailableLiquidity(address asset, address aToken)
        public
        view
        override
        returns (uint256 availableLiquidity, address underlying, uint256 currentFlow)
    {
        (,, bool isTranched) = IAERC6909(aToken).getIdForUnderlying(asset);

        availableLiquidity = IERC20(asset).balanceOf(aToken);

        if (isTranched) {
            IFlowLimiter flowLimiter =
                IFlowLimiter(IMiniPoolAddressesProvider(_addressProvider).getFlowLimiter());
            underlying = IAToken(asset).UNDERLYING_ASSET_ADDRESS();
            address minipool = IAERC6909(aToken).getMinipoolAddress();
            currentFlow = flowLimiter.currentFlow(underlying, minipool);
        }
    }

    // ----------- view -----------

    /// @inheritdoc BasePiReserveRateStrategy
    function getCurrentInterestRates() public view override returns (uint256, uint256, uint256) {
        // utilization
        IAERC6909 aErc6909Token = IAERC6909(
            IMiniPoolAddressesProvider(_addressProvider).getMiniPoolToAERC6909(_getLendingPool())
        );
        DataTypes.MiniPoolReserveData memory reserve =
            IMiniPool(_getLendingPool()).getReserveData(_asset);
        uint256 availableLiquidity = IERC20(_asset).balanceOf(reserve.aErc6909);
        uint256 totalVariableDebt = aErc6909Token.totalSupply(reserve.variableDebtTokenID);
        uint256 utilizationRate = totalVariableDebt == 0
            ? 0
            : totalVariableDebt.rayDiv(availableLiquidity + totalVariableDebt);

        // borrow rate
        uint256 currentVariableBorrowRate =
            transferFunction(_getControllerError(_getNormalizedError(utilizationRate)));

        // liquity rate
        uint256 currentLiquidityRate = _getLiquidityRate(
            currentVariableBorrowRate,
            utilizationRate,
            ReserveConfiguration.getAsteraReserveFactorMemory(reserve.configuration)
                + ReserveConfiguration.getMinipoolOwnerReserveMemory(reserve.configuration)
        );
        return (currentLiquidityRate, currentVariableBorrowRate, utilizationRate);
    }

    // ----------- view -----------

    /**
     * @notice Returns the base variable borrow rate.
     * @return The minimum variable borrow rate.
     */
    function baseVariableBorrowRate() public view override returns (uint256) {
        return uint256(transferFunction(type(int256).min));
    }

    /**
     * @notice Returns the maximum variable borrow rate.
     * @return The maximum allowed variable borrow rate.
     */
    function getMaxVariableBorrowRate() external pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Calculates the interest rates depending on the reserve's state and configurations.
     * @dev This function ensures the minipool can always repay its debt to the lending pool.
     * @param asset The address of the asset.
     * @param aToken The address of the reserve aToken.
     * @param liquidityAdded The liquidity added during the operation.
     * @param liquidityTaken The liquidity taken during the operation.
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate.
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market.
     * @return currentLiquidityRate The calculated liquidity rate.
     * @return currentVariableBorrowRate The calculated variable borrow rate.
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

            uint256 commonTerm =
                (r.currentLiquidityRate * DELTA_TIME_MARGIN / SECONDS_PER_YEAR) + WadRayMath.ray();
            uint256 minLiquidityRate = (
                MathUtils.calculateCompoundedInterest(
                    r.currentVariableBorrowRate, uint40(block.timestamp - DELTA_TIME_MARGIN)
                ) - commonTerm
            ).rayDiv(commonTerm * DELTA_TIME_MARGIN / SECONDS_PER_YEAR);

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
