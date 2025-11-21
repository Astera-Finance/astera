// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {
    SafeERC20
} from "../../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "../../../../../contracts/interfaces/IVariableDebtToken.sol";
import {
    IReserveInterestRateStrategy
} from "../../../../../contracts/interfaces/IReserveInterestRateStrategy.sol";
import {
    ReserveConfiguration
} from "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {MathUtils} from "../../../../../contracts/protocol/libraries/math/MathUtils.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {IMiniPool} from "../../../../../contracts/interfaces/IMiniPool.sol";
import {
    ILendingPoolAddressesProvider
} from "../../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IFlowLimiter} from "../../../../../contracts/interfaces/base/IFlowLimiter.sol";
import {
    EnumerableSet
} from "../../../../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ReserveLogic library
 * @author Conclave
 * @notice Implements the logic to update the reserves state.
 * @dev Contains core functions for managing reserve state updates and calculations.
 */
library ReserveLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev Emitted when the state of a reserve is updated.
     * @param asset The address of the underlying asset of the reserve.
     * @param liquidityRate The new liquidity rate.
     * @param variableBorrowRate The new variable borrow rate.
     * @param liquidityIndex The new liquidity index.
     * @param variableBorrowIndex The new variable borrow index.
     */
    event ReserveDataUpdated(
        address indexed asset,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /**
     * @dev Returns the ongoing normalized income for the reserve.
     * A value of 1e27 means there is no income. As time passes, the income is accrued.
     * A value of 2*1e27 means for each unit of asset one unit of income has been accrued.
     * @param reserve The reserve object.
     * @return The normalized income expressed in ray.
     */
    function getNormalizedIncome(DataTypes.ReserveData storage reserve)
        internal
        view
        returns (uint256)
    {
        uint40 timestamp = reserve.lastUpdateTimestamp;

        // If the index was updated in the same block, no need to perform any calculation.
        if (timestamp == uint40(block.timestamp)) {
            return reserve.liquidityIndex;
        }

        uint256 cumulated = MathUtils.calculateLinearInterest(
                reserve.currentLiquidityRate, timestamp
            ).rayMul(reserve.liquidityIndex);

        return cumulated;
    }

    /**
     * @dev Returns the ongoing normalized variable debt for the reserve.
     * A value of 1e27 means there is no debt. As time passes, the income is accrued.
     * A value of 2*1e27 means that for each unit of debt, one unit worth of interest has been accumulated.
     * @param reserve The reserve object.
     * @return The normalized variable debt expressed in ray.
     */
    function getNormalizedDebt(DataTypes.ReserveData storage reserve)
        internal
        view
        returns (uint256)
    {
        uint40 timestamp = reserve.lastUpdateTimestamp;

        // If the index was updated in the same block, no need to perform any calculation.
        if (timestamp == uint40(block.timestamp)) {
            return reserve.variableBorrowIndex;
        }

        uint256 cumulated = MathUtils.calculateCompoundedInterest(
                reserve.currentVariableBorrowRate, timestamp
            ).rayMul(reserve.variableBorrowIndex);

        return cumulated;
    }

    /**
     * @dev Updates the liquidity cumulative index and the variable borrow index.
     * @param reserve The reserve object to update.
     */
    function updateState(DataTypes.ReserveData storage reserve) internal {
        uint256 scaledVariableDebt =
            IVariableDebtToken(reserve.variableDebtTokenAddress).scaledTotalSupply();
        uint256 previousVariableBorrowIndex = reserve.variableBorrowIndex;
        uint256 previousLiquidityIndex = reserve.liquidityIndex;
        uint40 lastUpdatedTimestamp = reserve.lastUpdateTimestamp;

        (uint256 newLiquidityIndex, uint256 newVariableBorrowIndex) = _updateIndexes(
            reserve,
            scaledVariableDebt,
            previousLiquidityIndex,
            previousVariableBorrowIndex,
            lastUpdatedTimestamp
        );

        _mintToTreasury(
            reserve,
            scaledVariableDebt,
            previousVariableBorrowIndex,
            newLiquidityIndex,
            newVariableBorrowIndex,
            lastUpdatedTimestamp
        );
    }

    /**
     * @dev Initializes a reserve.
     * @param reserve The reserve object.
     * @param aTokenAddress The address of the overlying atoken contract.
     * @param variableDebtTokenAddress The address of the variable debt token.
     * @param interestRateStrategyAddress The address of the interest rate strategy contract.
     */
    function init(
        DataTypes.ReserveData storage reserve,
        address aTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress
    ) internal {
        require(reserve.aTokenAddress == address(0), Errors.RL_RESERVE_ALREADY_INITIALIZED);

        reserve.liquidityIndex = uint128(WadRayMath.ray());
        reserve.variableBorrowIndex = uint128(WadRayMath.ray());
        reserve.lastDayLiquidityIndex = uint128(WadRayMath.ray());
        reserve.lastDayVariableBorrowIndex = uint128(WadRayMath.ray());
        reserve.lastDayTimestamp = uint40(block.timestamp);
        reserve.aTokenAddress = aTokenAddress;
        reserve.variableDebtTokenAddress = variableDebtTokenAddress;
        reserve.interestRateStrategyAddress = interestRateStrategyAddress;
    }

    struct UpdateInterestRatesLocalVars {
        uint256 newLiquidityRate;
        uint256 newVariableRate;
        uint256 totalVariableDebt;
    }

    /**
     * @dev Updates the current variable borrow rate and the current liquidity rate.
     * @param reserve The address of the reserve to be updated.
     * @param reserveAddress The address of the reserve.
     * @param aTokenAddress The address of the aToken.
     * @param liquidityAdded The amount of liquidity added to the protocol (deposit or repay) in the previous action.
     * @param liquidityTaken The amount of liquidity taken from the protocol (redeem or borrow).
     */
    function updateInterestRates(
        DataTypes.ReserveData storage reserve,
        EnumerableSet.AddressSet storage minipoolFlowBorrowing,
        address reserveAddress,
        address aTokenAddress,
        uint256 liquidityAdded,
        uint256 liquidityTaken
    ) internal {
        UpdateInterestRatesLocalVars memory vars;

        // Calculates the total variable debt locally using the scaled total supply instead
        // of totalSupply(), as it's noticeably cheaper. Also, the index has been
        // updated by the previous updateState() call.
        vars.totalVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress)
            .scaledTotalSupply().rayMul(reserve.variableBorrowIndex);

        (vars.newLiquidityRate, vars.newVariableRate) = IReserveInterestRateStrategy(
                reserve.interestRateStrategyAddress
            )
            .calculateInterestRates(
                reserveAddress,
                aTokenAddress,
                liquidityAdded,
                liquidityTaken,
                vars.totalVariableDebt,
                reserve.configuration.getAsteraReserveFactor()
            );
        require(vars.newLiquidityRate <= type(uint128).max, Errors.RL_LIQUIDITY_RATE_OVERFLOW);
        require(vars.newVariableRate <= type(uint128).max, Errors.RL_VARIABLE_BORROW_RATE_OVERFLOW);

        reserve.currentLiquidityRate = uint128(vars.newLiquidityRate);
        reserve.currentVariableBorrowRate = uint128(vars.newVariableRate);

        // Sync minipools state that has "flow borrowing" to ensure that the LendingPool
        // liquidity rate of an asset is always greater than the borrowing rate of minipools.
        // Only `syncState()` if `reserveType` is `true`.
        IAToken aToken = IAToken(aTokenAddress);
        if (aToken.RESERVE_TYPE()) {
            for (uint256 i = 0; i < minipoolFlowBorrowing.length(); i++) {
                IMiniPool minipool = IMiniPool(minipoolFlowBorrowing.at(i));
                minipool.syncState(aToken.WRAPPER_ADDRESS());
            }
        }

        emit ReserveDataUpdated(
            reserveAddress,
            vars.newLiquidityRate,
            vars.newVariableRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex
        );
    }

    struct MintToTreasuryLocalVars {
        uint256 currentVariableDebt;
        uint256 previousVariableDebt;
        uint256 totalDebtAccrued;
        uint256 amountToMint;
        uint256 reserveFactor;
    }

    /**
     * @dev Mints part of the repaid interest to the reserve treasury based on the reserveFactor.
     * @param reserve The reserve to be updated.
     * @param scaledVariableDebt The current scaled total variable debt.
     * @param previousVariableBorrowIndex The variable borrow index before the last accumulation of interest.
     * @param newLiquidityIndex The new liquidity index.
     * @param newVariableBorrowIndex The variable borrow index after the last accumulation of interest.
     */
    function _mintToTreasury(
        DataTypes.ReserveData storage reserve,
        uint256 scaledVariableDebt,
        uint256 previousVariableBorrowIndex,
        uint256 newLiquidityIndex,
        uint256 newVariableBorrowIndex,
        uint40
    ) internal {
        MintToTreasuryLocalVars memory vars;

        vars.reserveFactor = reserve.configuration.getAsteraReserveFactor();

        if (vars.reserveFactor == 0) {
            return;
        }

        // Calculate the last principal variable debt.
        vars.previousVariableDebt = scaledVariableDebt.rayMul(previousVariableBorrowIndex);

        // Calculate the new total supply after accumulation of the index.
        vars.currentVariableDebt = scaledVariableDebt.rayMul(newVariableBorrowIndex);

        // Debt accrued is the sum of the current debt minus the sum of the debt at the last update.
        vars.totalDebtAccrued = vars.currentVariableDebt - vars.previousVariableDebt;

        vars.amountToMint = vars.totalDebtAccrued.percentMul(vars.reserveFactor);

        if (vars.amountToMint != 0) {
            IAToken(reserve.aTokenAddress)
                .mintToAsteraTreasury(vars.amountToMint, newLiquidityIndex);
        }
    }

    /**
     * @dev Updates the reserve indexes and the timestamp of the update.
     * @param reserve The reserve to be updated.
     * @param scaledVariableDebt The scaled variable debt.
     * @param liquidityIndex The last stored liquidity index.
     * @param variableBorrowIndex The last stored variable borrow index.
     * @param timestamp The timestamp of the last update.
     * @return The new liquidity index and variable borrow index.
     */
    function _updateIndexes(
        DataTypes.ReserveData storage reserve,
        uint256 scaledVariableDebt,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex,
        uint40 timestamp
    ) internal returns (uint256, uint256) {
        uint256 currentLiquidityRate = reserve.currentLiquidityRate;

        uint256 newLiquidityIndex = liquidityIndex;
        uint256 newVariableBorrowIndex = variableBorrowIndex;

        // Only cumulating if there is any income being produced.
        if (currentLiquidityRate != 0) {
            uint256 cumulatedLiquidityInterest =
                MathUtils.calculateLinearInterest(currentLiquidityRate, timestamp);
            newLiquidityIndex = cumulatedLiquidityInterest.rayMul(liquidityIndex);
            require(newLiquidityIndex <= type(uint128).max, Errors.RL_LIQUIDITY_INDEX_OVERFLOW);
            uint256 dailyIndexExtrapolationRate = _dailyIndexLinearExtrapolation(
                reserve.lastDayTimestamp,
                reserve.lastDayLiquidityIndex,
                block.timestamp,
                uint128(newLiquidityIndex)
            );
            uint256 dailyLiquidityIndexThreshold =
                reserve.configuration.getDailyLiquidityIndexThreshold();
            require(
                dailyIndexExtrapolationRate <= dailyLiquidityIndexThreshold,
                Errors.RL_LIQUIDITY_INDEX_THRESHOLD_EXCEEDED
            );
            reserve.liquidityIndex = uint128(newLiquidityIndex);
        }

        if (scaledVariableDebt != 0) {
            uint256 cumulatedVariableBorrowInterest =
                MathUtils.calculateCompoundedInterest(reserve.currentVariableBorrowRate, timestamp);
            newVariableBorrowIndex = cumulatedVariableBorrowInterest.rayMul(variableBorrowIndex);
            require(
                newVariableBorrowIndex <= type(uint128).max,
                Errors.RL_VARIABLE_BORROW_INDEX_OVERFLOW
            );
            uint256 dailyIndexExtrapolationRate = _dailyIndexLinearExtrapolation(
                reserve.lastDayTimestamp,
                reserve.lastDayVariableBorrowIndex,
                block.timestamp,
                uint128(newVariableBorrowIndex)
            );
            uint256 dailyBorrowIndexThreshold = reserve.configuration.getDailyBorrowIndexThreshold();
            require(
                dailyIndexExtrapolationRate <= dailyBorrowIndexThreshold,
                Errors.RL_BORROW_INDEX_THRESHOLD_EXCEEDED
            );
            reserve.variableBorrowIndex = uint128(newVariableBorrowIndex);
        }

        // Don't have to be exactly 1 day, linear extrapolation works even for > 1 day
        if (reserve.lastDayTimestamp + 1 days <= block.timestamp) {
            reserve.lastDayTimestamp = uint40(block.timestamp);
            reserve.lastDayLiquidityIndex = reserve.liquidityIndex;
            reserve.lastDayVariableBorrowIndex = reserve.variableBorrowIndex;
        }

        reserve.lastUpdateTimestamp = uint40(block.timestamp);
        return (newLiquidityIndex, newVariableBorrowIndex);
    }

    function _dailyIndexLinearExtrapolation(
        uint256 previousValueTimestamp,
        uint256 previousValue,
        uint256 currentValueTimestamp,
        uint256 currentValue
    ) internal pure returns (uint256 dailyChangeAmount) {
        require(currentValueTimestamp >= previousValueTimestamp, Errors.RL_WRONG_TIMESTAMPS);
        require(currentValue >= previousValue, Errors.RL_WRONG_INDEX_VALUES);

        // Calculate time difference in seconds
        uint256 secondsElapsed = currentValueTimestamp - previousValueTimestamp;

        // Calculate change in value (absolute)
        uint256 valueChange;
        valueChange = currentValue - previousValue;

        // If no change, daily change is 0
        if (valueChange == 0) {
            return 0;
        }

        // Linear extrapolation: dailyChange = 86400 * valueChange / secondsElapsed
        uint256 dailyChange = (valueChange * 1 days) / secondsElapsed;

        // Convert to basis points: (dailyChange / previousValue) * 10000
        // Usually the rate change is so small that it's floored to 0
        return (dailyChange * 10_000) / previousValue;
    }
}
