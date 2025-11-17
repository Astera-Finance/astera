// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {
    ReserveConfiguration
} from "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {
    UserConfiguration
} from "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {IOracle} from "../../../../../contracts/interfaces/IOracle.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title GenericLogic library
 * @author Conclave
 * @notice Implements protocol-level logic to calculate and validate the state of a user.
 * @dev Contains core functions for calculating user account data and health factors.
 */
library GenericLogic {
    using ReserveLogic for DataTypes.ReserveData;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /// @dev The minimum health factor value before liquidation can occur.
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether;

    /**
     * @dev Struct containing local variables used in balance decrease calculations.
     * @param decimals Token decimals.
     * @param liquidationThreshold Asset's liquidation threshold.
     * @param totalCollateralInETH Total collateral value in ETH.
     * @param totalDebtInETH Total debt value in ETH.
     * @param avgLiquidationThreshold Average liquidation threshold across all collateral.
     * @param amountToDecreaseInETH Amount to decrease in ETH terms.
     * @param collateralBalanceAfterDecrease Remaining collateral after decrease.
     * @param liquidationThresholdAfterDecrease New liquidation threshold after decrease.
     */
    struct balanceDecreaseAllowedLocalVars {
        uint256 decimals;
        uint256 liquidationThreshold;
        uint256 totalCollateralInETH;
        uint256 totalDebtInETH;
        uint256 avgLiquidationThreshold;
        uint256 amountToDecreaseInETH;
        uint256 collateralBalanceAfterDecrease;
        uint256 liquidationThresholdAfterDecrease;
    }

    /**
     * @notice Checks if a specific balance decrease is allowed.
     * @dev Validates that the balance decrease won't bring the health factor below liquidation threshold.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Boolean indicating if reserve is boosted by a vault.
     * @param user The address of the user.
     * @param amount The amount to decrease.
     * @param reserves The data of all the reserves.
     * @param userConfig The user configuration.
     * @param reservesList The list of all the active reserves.
     * @param reservesCount The count of initialized reserves.
     * @param oracle The address of the oracle contract.
     * @return true if the decrease of the balance is allowed.
     */
    function balanceDecreaseAllowed(
        address asset,
        bool reserveType,
        address user,
        uint256 amount,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        uint256 reservesCount,
        address oracle
    ) external view returns (bool) {
        if (
            !userConfig.isBorrowingAny()
                || !userConfig.isUsingAsCollateral(reserves[asset][reserveType].id)
        ) {
            return true;
        }

        balanceDecreaseAllowedLocalVars memory vars;

        (, vars.liquidationThreshold,, vars.decimals,) =
            reserves[asset][reserveType].configuration.getParams();

        if (vars.liquidationThreshold == 0) {
            return true;
        }

        (vars.totalCollateralInETH, vars.totalDebtInETH,, vars.avgLiquidationThreshold,) =
            calculateUserAccountData(
                user, reserves, userConfig, reservesList, reservesCount, oracle
            );

        if (vars.totalDebtInETH == 0) {
            return true;
        }

        vars.amountToDecreaseInETH = getAmountToDecreaseInEth(oracle, asset, amount, vars.decimals);

        vars.collateralBalanceAfterDecrease = vars.totalCollateralInETH - vars.amountToDecreaseInETH;

        // If there is a borrow, there can't be 0 collateral.
        if (vars.collateralBalanceAfterDecrease == 0) {
            return false;
        }

        vars.liquidationThresholdAfterDecrease =
            ((vars.totalCollateralInETH * vars.avgLiquidationThreshold)
                    - (vars.amountToDecreaseInETH * vars.liquidationThreshold))
                / vars.collateralBalanceAfterDecrease;

        uint256 healthFactorAfterDecrease = calculateHealthFactorFromBalances(
            vars.collateralBalanceAfterDecrease,
            vars.totalDebtInETH,
            vars.liquidationThresholdAfterDecrease
        );

        return healthFactorAfterDecrease >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice Calculates the ETH value of an amount to be decreased.
     * @dev Converts token amount to ETH value using oracle price.
     * @param oracle The price oracle address.
     * @param asset The asset address.
     * @param amount The amount to convert.
     * @param decimals The decimals of the asset.
     * @return The ETH value of the amount.
     */
    function getAmountToDecreaseInEth(
        address oracle,
        address asset,
        uint256 amount,
        uint256 decimals
    ) internal view returns (uint256) {
        return WadRayMath.divUp(IOracle(oracle).getAssetPrice(asset) * amount, 10 ** decimals);
    }

    /**
     * @dev Struct containing local variables used in user account data calculations.
     * @param reserveUnitPrice Current price of reserve unit.
     * @param tokenUnit Base unit of token (10^decimals).
     * @param compoundedLiquidityBalance User's compounded liquidity balance.
     * @param compoundedBorrowBalance User's compounded borrow balance.
     * @param decimals Token decimals.
     * @param ltv Loan to value ratio.
     * @param liquidationThreshold Liquidation threshold.
     * @param i Loop counter.
     * @param healthFactor Calculated health factor.
     * @param totalCollateralInETH Total collateral in ETH.
     * @param totalDebtInETH Total debt in ETH.
     * @param avgLtv Average loan to value.
     * @param avgLiquidationThreshold Average liquidation threshold.
     * @param currentReserveAddress Current reserve being processed.
     * @param currentReserveType Type of current reserve.
     */
    struct CalculateUserAccountDataLocalVars {
        uint256 reserveUnitPrice;
        uint256 tokenUnit;
        uint256 compoundedLiquidityBalance;
        uint256 compoundedBorrowBalance;
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 i;
        uint256 healthFactor;
        uint256 totalCollateralInETH;
        uint256 totalDebtInETH;
        uint256 avgLtv;
        uint256 avgLiquidationThreshold;
        address currentReserveAddress;
        bool currentReserveType;
    }

    /**
     * @notice Calculates the user data across all reserves.
     * @dev Computes total liquidity/collateral/borrow balances in ETH, average LTV, liquidation ratio, and health factor.
     * @param user The address of the user.
     * @param reserves Data of all the reserves.
     * @param userConfig The configuration of the user.
     * @param reservesList The list of the available reserves.
     * @param reservesCount The count of initialized reserves.
     * @param oracle The price oracle address.
     * @return totalCollateralETH Total collateral in ETH.
     * @return totalDebtETH Total debt in ETH.
     * @return avgLtv Average loan to value ratio.
     * @return avgLiquidationThreshold Average liquidation threshold.
     * @return healthFactor User's health factor.
     */
    function calculateUserAccountData(
        address user,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        DataTypes.UserConfigurationMap memory userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        uint256 reservesCount,
        address oracle
    ) public view returns (uint256, uint256, uint256, uint256, uint256) {
        CalculateUserAccountDataLocalVars memory vars;

        if (userConfig.isEmpty()) {
            return (0, 0, 0, 0, type(uint256).max);
        }
        for (vars.i = 0; vars.i < reservesCount; vars.i++) {
            if (!userConfig.isUsingAsCollateralOrBorrowing(vars.i)) {
                continue;
            }

            vars.currentReserveAddress = reservesList[vars.i].asset;
            vars.currentReserveType = reservesList[vars.i].reserveType;
            DataTypes.ReserveData storage currentReserve =
                reserves[vars.currentReserveAddress][vars.currentReserveType];

            (vars.ltv, vars.liquidationThreshold,, vars.decimals,) =
                currentReserve.configuration.getParams();

            vars.tokenUnit = 10 ** vars.decimals;
            vars.reserveUnitPrice = IOracle(oracle).getAssetPrice(vars.currentReserveAddress);

            if (vars.liquidationThreshold != 0 && userConfig.isUsingAsCollateral(vars.i)) {
                vars.compoundedLiquidityBalance =
                    IERC20(currentReserve.aTokenAddress).balanceOf(user);

                uint256 liquidityBalanceETH =
                    vars.reserveUnitPrice * vars.compoundedLiquidityBalance / vars.tokenUnit;

                vars.totalCollateralInETH = vars.totalCollateralInETH + liquidityBalanceETH;

                vars.avgLtv = vars.avgLtv + (liquidityBalanceETH * vars.ltv);
                vars.avgLiquidationThreshold = vars.avgLiquidationThreshold
                    + (liquidityBalanceETH * vars.liquidationThreshold);
            }

            if (userConfig.isBorrowing(vars.i)) {
                vars.compoundedBorrowBalance =
                    IERC20(currentReserve.variableDebtTokenAddress).balanceOf(user);

                vars.totalDebtInETH = vars.totalDebtInETH
                    + WadRayMath.divUp(
                        vars.reserveUnitPrice * vars.compoundedBorrowBalance, vars.tokenUnit
                    );
            }
        }

        vars.avgLtv = vars.totalCollateralInETH > 0 ? vars.avgLtv / vars.totalCollateralInETH : 0;
        vars.avgLiquidationThreshold = vars.totalCollateralInETH > 0
            ? vars.avgLiquidationThreshold / vars.totalCollateralInETH
            : 0;

        vars.healthFactor = calculateHealthFactorFromBalances(
            vars.totalCollateralInETH, vars.totalDebtInETH, vars.avgLiquidationThreshold
        );
        return (
            vars.totalCollateralInETH,
            vars.totalDebtInETH,
            vars.avgLtv,
            vars.avgLiquidationThreshold,
            vars.healthFactor
        );
    }

    /**
     * @notice Calculates the health factor from the corresponding balances.
     * @dev Health factor is the ratio between the total collateral weighted by liquidation threshold and total debt.
     * @param totalCollateralInETH The total collateral in ETH.
     * @param totalDebtInETH The total debt in ETH.
     * @param liquidationThreshold The avg liquidation threshold.
     * @return The health factor calculated from the balances provided.
     */
    function calculateHealthFactorFromBalances(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 liquidationThreshold
    ) internal pure returns (uint256) {
        if (totalDebtInETH == 0) return type(uint256).max;

        return (totalCollateralInETH.percentMul(liquidationThreshold)).wadDiv(totalDebtInETH);
    }

    /**
     * @notice Calculates the equivalent amount in ETH that a user can borrow.
     * @dev Determines borrowing power based on collateral and average LTV.
     * @param totalCollateralInETH The total collateral in ETH.
     * @param totalDebtInETH The total borrow balance.
     * @param ltv The average loan to value.
     * @return The amount available to borrow in ETH for the user.
     */
    function calculateAvailableBorrowsETH(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 ltv
    ) public pure returns (uint256) {
        uint256 availableBorrowsETH = totalCollateralInETH.percentMul(ltv);

        if (availableBorrowsETH < totalDebtInETH) {
            return 0;
        }

        availableBorrowsETH = availableBorrowsETH - totalDebtInETH;
        return availableBorrowsETH;
    }
}
