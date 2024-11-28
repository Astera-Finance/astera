// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IAERC6909} from "../../../../../contracts/interfaces/IAERC6909.sol";
import {MiniPoolReserveLogic} from "./MiniPoolReserveLogic.sol";
import {ReserveConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {IOracle} from "../../../../../contracts/interfaces/IOracle.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title MiniPoolGenericLogic library
 * @author Cod3x
 * @notice Implements protocol-level logic to calculate and validate the state of a user's positions.
 * @dev Contains core functions for health factor calculations and user account data management.
 */
library MiniPoolGenericLogic {
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /// @notice The minimum health factor threshold that triggers liquidation, represented in WAD (1e18).
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether;

    /**
     * @dev Local variables struct used in balanceDecreaseAllowed function to avoid stack too deep errors.
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
     * @notice Validates if a balance decrease is allowed based on the user's health factor.
     * @dev Checks if reducing collateral would bring health factor below liquidation threshold.
     * @param asset The address of the underlying asset of the reserve.
     * @param user The address of the user.
     * @param amount The amount to decrease.
     * @param reserves The data of all the reserves.
     * @param userConfig The user configuration.
     * @param reservesList The list of all the active reserves.
     * @param oracle The address of the oracle contract.
     * @return True if the decrease of the balance is allowed, false otherwise.
     */
    function balanceDecreaseAllowed(
        address asset,
        address user,
        uint256 amount,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reservesList,
        uint256 reservesCount,
        address oracle
    ) external view returns (bool) {
        if (!userConfig.isBorrowingAny() || !userConfig.isUsingAsCollateral(reserves[asset].id)) {
            return true;
        }

        balanceDecreaseAllowedLocalVars memory vars;

        (, vars.liquidationThreshold,, vars.decimals,) = reserves[asset].configuration.getParams();

        if (vars.liquidationThreshold == 0) {
            return true;
        }

        (vars.totalCollateralInETH, vars.totalDebtInETH,, vars.avgLiquidationThreshold,) =
        calculateUserAccountData(user, reserves, userConfig, reservesList, reservesCount, oracle);

        if (vars.totalDebtInETH == 0) {
            return true;
        }

        vars.amountToDecreaseInETH = getAmountToDecreaseInEth(oracle, asset, amount, vars.decimals);

        vars.collateralBalanceAfterDecrease = vars.totalCollateralInETH - vars.amountToDecreaseInETH;

        // If there is a borrow, there can't be 0 collateral.
        if (vars.collateralBalanceAfterDecrease == 0) {
            return false;
        }

        vars.liquidationThresholdAfterDecrease = (
            (vars.totalCollateralInETH * vars.avgLiquidationThreshold)
                - (vars.amountToDecreaseInETH * vars.liquidationThreshold)
        ) / vars.collateralBalanceAfterDecrease;

        uint256 healthFactorAfterDecrease = calculateHealthFactorFromBalances(
            vars.collateralBalanceAfterDecrease,
            vars.totalDebtInETH,
            vars.liquidationThresholdAfterDecrease
        );

        return healthFactorAfterDecrease >= MiniPoolGenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice Converts an asset amount to its ETH equivalent value.
     * @param oracle The address of the price oracle.
     * @param asset The address of the asset.
     * @param amount The amount to convert.
     * @param decimals The decimals of the asset.
     * @return The equivalent amount in ETH.
     */
    function getAmountToDecreaseInEth(
        address oracle,
        address asset,
        uint256 amount,
        uint256 decimals
    ) internal view returns (uint256) {
        return IOracle(oracle).getAssetPrice(asset) * amount / (10 ** decimals);
    }

    /**
     * @dev Local variables struct used in calculateUserAccountData function to avoid stack too deep errors.
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
    }

    /**
     * @notice Calculates comprehensive user account data across all reserves.
     * @dev Computes total liquidity, collateral, borrow balances in ETH, average LTV, liquidation ratio, and health factor.
     * @param user The address of the user.
     * @param reserves Data of all the reserves.
     * @param userConfig The configuration of the user.
     * @param reservesList The list of the available reserves.
     * @param oracle The price oracle address.
     * @return totalCollateralInETH Total collateral in ETH.
     * @return totalDebtInETH Total debt in ETH.
     * @return avgLtv Average loan to value ratio.
     * @return avgLiquidationThreshold Average liquidation threshold.
     * @return healthFactor Current health factor.
     */
    function calculateUserAccountData(
        address user,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves,
        DataTypes.UserConfigurationMap memory userConfig,
        mapping(uint256 => address) storage reservesList,
        uint256 reservesCount,
        address oracle
    ) internal view returns (uint256, uint256, uint256, uint256, uint256) {
        CalculateUserAccountDataLocalVars memory vars;

        if (userConfig.isEmpty()) {
            return (0, 0, 0, 0, type(uint256).max);
        }
        for (vars.i = 0; vars.i < reservesCount; vars.i++) {
            if (!userConfig.isUsingAsCollateralOrBorrowing(vars.i)) {
                continue;
            }

            vars.currentReserveAddress = reservesList[vars.i];
            DataTypes.MiniPoolReserveData storage currentReserve =
                reserves[vars.currentReserveAddress];

            (vars.ltv, vars.liquidationThreshold,, vars.decimals,) =
                currentReserve.configuration.getParams();

            vars.tokenUnit = 10 ** vars.decimals;

            vars.reserveUnitPrice = IOracle(oracle).getAssetPrice(vars.currentReserveAddress);

            if (vars.liquidationThreshold != 0 && userConfig.isUsingAsCollateral(vars.i)) {
                vars.compoundedLiquidityBalance =
                    IAERC6909(currentReserve.aTokenAddress).balanceOf(user, currentReserve.aTokenID);
                uint256 liquidityBalanceETH =
                    vars.reserveUnitPrice * vars.compoundedLiquidityBalance / vars.tokenUnit;

                vars.totalCollateralInETH = vars.totalCollateralInETH + liquidityBalanceETH;

                vars.avgLtv = vars.avgLtv + (liquidityBalanceETH * vars.ltv);
                vars.avgLiquidationThreshold =
                    vars.avgLiquidationThreshold + (liquidityBalanceETH * vars.liquidationThreshold);
            }

            if (userConfig.isBorrowing(vars.i)) {
                vars.compoundedBorrowBalance = IAERC6909(currentReserve.aTokenAddress).balanceOf(
                    user, currentReserve.variableDebtTokenID
                );

                vars.totalDebtInETH = vars.totalDebtInETH
                    + (vars.reserveUnitPrice * vars.compoundedBorrowBalance / vars.tokenUnit);
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
     * @param totalCollateralInETH The total collateral in ETH.
     * @param totalDebtInETH The total debt in ETH.
     * @param liquidationThreshold The average liquidation threshold.
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
     * @dev Calculation depends on the available collateral and the average Loan To Value.
     * @param totalCollateralInETH The total collateral in ETH.
     * @param totalDebtInETH The total borrow balance.
     * @param ltv The average loan to value.
     * @return The amount available to borrow in ETH for the user.
     */
    function calculateAvailableBorrowsETH(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 ltv
    ) internal pure returns (uint256) {
        uint256 availableBorrowsETH = totalCollateralInETH.percentMul(ltv);

        if (availableBorrowsETH < totalDebtInETH) {
            return 0;
        }

        availableBorrowsETH = availableBorrowsETH - totalDebtInETH;
        return availableBorrowsETH;
    }
}
