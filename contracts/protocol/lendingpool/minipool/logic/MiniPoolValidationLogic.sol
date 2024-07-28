// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {SafeMath} from "../../../../dependencies/openzeppelin/contracts/SafeMath.sol";
import {IERC20} from "../../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {MiniPoolReserveLogic} from "./MiniPoolReserveLogic.sol";
import {MiniPoolGenericLogic} from "./MiniPoolGenericLogic.sol";
import {MiniPoolBorrowLogic} from "./MiniPoolBorrowLogic.sol";
import {WadRayMath} from "../../../libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../libraries/math/PercentageMath.sol";
import {SafeERC20} from "../../../../dependencies/openzeppelin/contracts/SafeERC20.sol";
import {ReserveConfiguration} from "../../../libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "../../../libraries/configuration/UserConfiguration.sol";
import {Errors} from "../../../libraries/helpers/Errors.sol";
import {Helpers} from "../../../libraries/helpers/Helpers.sol";
import {IReserveInterestRateStrategy} from "../../../../interfaces/IReserveInterestRateStrategy.sol";
import {DataTypes} from "../../../libraries/types/DataTypes.sol";
import {IAToken} from "../../../../interfaces/IAToken.sol";
import {IAERC6909} from "../../../../interfaces/IAERC6909.sol";

/**
 * @title ReserveLogic library
 * @author Aave
 * @notice Implements functions to validate the different actions of the protocol
 */
library MiniPoolValidationLogic {
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /**
     * @dev Validates a deposit action
     * @param reserve The reserve object on which the user is depositing
     * @param amount The amount to be deposited
     */
    function validateDeposit(DataTypes.MiniPoolReserveData storage reserve, uint256 amount)
        internal
        view
    {
        (bool isActive, bool isFrozen,) = reserve.configuration.getFlags();
        uint256 depositCapExponent = reserve.configuration.getDepositCap();
        uint256 depositCap =
            depositCapExponent != 0 ? 10 ** (depositCapExponent) : type(uint256).max;
        uint256 total = IAERC6909(reserve.aTokenAddress).totalSupply(reserve.aTokenID);
        uint256 newTotal = total + amount;
        require(amount != 0, Errors.VL_INVALID_AMOUNT);
        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);
        require(!isFrozen, Errors.VL_RESERVE_FROZEN);
        require(newTotal < depositCap, Errors.VL_DEPOSIT_CAP_REACHED);
    }

    /**
     * @dev Validates a withdraw action
     * @param reserveAddress The address of the reserve
     * @param amount The amount to be withdrawn
     * @param userBalance The balance of the user
     * @param reservesData The reserves state
     * @param userConfig The user configuration
     * @param reserves The addresses of the reserves
     * @param reservesCount The number of reserves
     * @param oracle The price oracle
     */
    struct ValidateWithdrawParams {
        address reserveAddress;
        bool reserveType;
        uint256 amount;
        uint256 userBalance;
        uint256 reservesCount;
        address oracle;
    }

    function validateWithdraw(
        ValidateWithdrawParams memory validateParams,
        mapping(address => DataTypes.MiniPoolReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reserves
    ) internal view {
        require(validateParams.amount != 0, Errors.VL_INVALID_AMOUNT);
        require(
            validateParams.amount <= validateParams.userBalance,
            Errors.VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE
        );

        (bool isActive,,) = reservesData[validateParams.reserveAddress].configuration.getFlags();
        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);

        require(
            MiniPoolGenericLogic.balanceDecreaseAllowed(
                validateParams.reserveAddress,
                validateParams.reserveType,
                msg.sender,
                validateParams.amount,
                reservesData,
                userConfig,
                reserves,
                validateParams.reservesCount,
                validateParams.oracle
            ),
            Errors.VL_TRANSFER_NOT_ALLOWED
        );
    }

    /**
     * @param asset The address of the asset to borrow
     * @param userAddress The address of the user
     * @param amount The amount to be borrowed
     * @param amountInETH The amount to be borrowed, in ETH
     * @param reservesCount
     * @param lendingUpdateTimestamp
     * @param oracle The price oracle
     */
    struct ValidateBorrowParams {
        address asset;
        address userAddress;
        uint256 amount;
        uint256 amountInETH;
        uint256 reservesCount;
        uint256 lendingUpdateTimestamp;
        address oracle;
    }

    struct ValidateBorrowLocalVars {
        uint256 currentLtv;
        uint256 currentLiquidationThreshold;
        uint256 amountOfCollateralNeededETH;
        uint256 userCollateralBalanceETH;
        uint256 userBorrowBalanceETH;
        uint256 availableLiquidity;
        uint256 healthFactor;
        uint256 amountOfCollateralNeededETHIsolated;
        uint256 userCollateralBalanceETHIsolated;
        uint256 userBorrowBalanceETHIsolated;
        uint256 currentLtvIsolated;
        uint256 currentLiquidationThresholdIsolated;
        uint256 healthFactorIsolated;
        bool isActive;
        bool isFrozen;
        bool borrowingEnabled;
    }

    /**
     * @dev Validates a borrow action
     * @param reserve The reserve state from which the user is borrowing
     * @param reservesData The state of all the reserves
     * @param userConfig The state of the user for the specific reserve
     * @param reserves The addresses of all the active reserves
     */
    function validateBorrow(
        ValidateBorrowParams memory validateParams,
        DataTypes.MiniPoolReserveData storage reserve,
        mapping(address => DataTypes.MiniPoolReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reserves,
        DataTypes.UserRecentBorrowMap storage userRecentBorrow
    ) internal view {
        ValidateBorrowLocalVars memory vars;
        MiniPoolBorrowLogic.CalculateUserAccountDataVolatileParams memory params;
        params.user = validateParams.userAddress;
        params.reservesCount = validateParams.reservesCount;
        params.lendingUpdateTimestamp = validateParams.lendingUpdateTimestamp;
        params.oracle = validateParams.oracle;

        (vars.isActive, vars.isFrozen, vars.borrowingEnabled) = reserve.configuration.getFlags();

        require(vars.isActive, Errors.VL_NO_ACTIVE_RESERVE);
        require(!vars.isFrozen, Errors.VL_RESERVE_FROZEN);
        require(validateParams.amount != 0, Errors.VL_INVALID_AMOUNT);
        require(vars.borrowingEnabled, Errors.VL_BORROWING_NOT_ENABLED);

        (
            vars.userCollateralBalanceETH,
            vars.userBorrowBalanceETH,
            vars.currentLtv,
            vars.currentLiquidationThreshold,
            vars.healthFactor
        ) = MiniPoolBorrowLogic.calculateUserAccountDataVolatile(
            params, reservesData, userConfig, userRecentBorrow, reserves
        );

        require(vars.userCollateralBalanceETH > 0, Errors.VL_COLLATERAL_BALANCE_IS_0);

        require(
            vars.healthFactor > MiniPoolGenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.VL_HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
        );

        //add the current already borrowed amount to the amount requested to calculate the total collateral needed.
        vars.amountOfCollateralNeededETH =
            vars.userBorrowBalanceETH.add(validateParams.amountInETH).percentDiv(vars.currentLtv); //LTV is calculated in percentage

        require(
            vars.amountOfCollateralNeededETH <= vars.userCollateralBalanceETH,
            Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW
        );
    }

    /**
     * @dev Validates a repay action
     * @param reserve The reserve state from which the user is repaying
     * @param amountSent The amount sent for the repayment. Can be an actual value or uint(-1)
     * @param onBehalfOf The address of the user msg.sender is repaying for
     * @param variableDebt The borrow balance of the user
     */
    function validateRepay(
        DataTypes.MiniPoolReserveData storage reserve,
        uint256 amountSent,
        address onBehalfOf,
        uint256 variableDebt
    ) internal view {
        bool isActive = reserve.configuration.getActive();

        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);

        require(amountSent > 0, Errors.VL_INVALID_AMOUNT);

        require(variableDebt > 0, Errors.VL_NO_DEBT_OF_SELECTED_TYPE);

        require(
            amountSent != type(uint256).max || msg.sender == onBehalfOf,
            Errors.VL_NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF
        );
    }

    /**
     * @dev Validates the action of setting an asset as collateral
     * @param reserve The state of the reserve that the user is enabling or disabling as collateral
     * @param reserveAddress The address of the reserve
     * @param reservesData The data of all the reserves
     * @param userConfig The state of the user for the specific reserve
     * @param reserves The addresses of all the active reserves
     * @param oracle The price oracle
     */
    function validateSetUseReserveAsCollateral(
        DataTypes.MiniPoolReserveData storage reserve,
        address reserveAddress,
        bool reserveType,
        bool useAsCollateral,
        mapping(address => DataTypes.MiniPoolReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reserves,
        uint256 reservesCount,
        address oracle
    ) internal view {
        //@issue: balanceOf shall be on IAERC6909 instead IERC20
        uint256 underlyingBalance =
            IAERC6909(reserve.aTokenAddress).balanceOf(msg.sender, reserve.aTokenID);

        require(underlyingBalance > 0, Errors.VL_UNDERLYING_BALANCE_NOT_GREATER_THAN_0);

        require(
            useAsCollateral
                || MiniPoolGenericLogic.balanceDecreaseAllowed(
                    reserveAddress,
                    reserveType,
                    msg.sender,
                    underlyingBalance,
                    reservesData,
                    userConfig,
                    reserves,
                    reservesCount,
                    oracle
                ),
            Errors.VL_DEPOSIT_ALREADY_IN_USE
        );
    }

    /**
     * @dev Validates a flashloan action
     * @param assets The assets being flashborrowed
     * @param amounts The amounts for each asset being borrowed
     *
     */
    function validateFlashloan(address[] memory assets, uint256[] memory amounts) internal pure {
        require(assets.length == amounts.length, Errors.VL_INCONSISTENT_FLASHLOAN_PARAMS);
    }

    /**
     * @dev Validates the liquidation action
     * @param collateralReserve The reserve data of the collateral
     * @param principalReserve The reserve data of the principal
     * @param userConfig The user configuration
     * @param userHealthFactor The user's health factor
     * @param userVariableDebt Total variable debt balance of the user
     *
     */
    function validateLiquidationCall(
        DataTypes.MiniPoolReserveData storage collateralReserve,
        DataTypes.MiniPoolReserveData storage principalReserve,
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 userHealthFactor,
        uint256 userVariableDebt
    ) internal view returns (uint256, string memory) {
        if (
            !collateralReserve.configuration.getActive()
                || !principalReserve.configuration.getActive()
        ) {
            return (
                uint256(Errors.CollateralManagerErrors.NO_ACTIVE_RESERVE),
                Errors.VL_NO_ACTIVE_RESERVE
            );
        }

        if (userHealthFactor >= MiniPoolGenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {
            return (
                uint256(Errors.CollateralManagerErrors.HEALTH_FACTOR_ABOVE_THRESHOLD),
                Errors.LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD
            );
        }

        bool isCollateralEnabled = collateralReserve.configuration.getLiquidationThreshold() > 0
            && userConfig.isUsingAsCollateral(collateralReserve.id);

        //if collateral isn't enabled as collateral by user, it cannot be liquidated
        if (!isCollateralEnabled) {
            return (
                uint256(Errors.CollateralManagerErrors.COLLATERAL_CANNOT_BE_LIQUIDATED),
                Errors.LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED
            );
        }

        if (userVariableDebt == 0) {
            return (
                uint256(Errors.CollateralManagerErrors.CURRRENCY_NOT_BORROWED),
                Errors.LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER
            );
        }

        return (uint256(Errors.CollateralManagerErrors.NO_ERROR), Errors.LPCM_NO_ERRORS);
    }

    /**
     * @dev Validates an aToken transfer
     * @param from The user from which the aTokens are being transferred
     * @param reservesData The state of all the reserves
     * @param userConfig The state of the user for the specific reserve
     * @param reserves The addresses of all the active reserves
     * @param oracle The price oracle
     */
    function validateTransfer(
        address from,
        mapping(address => DataTypes.MiniPoolReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reserves,
        uint256 reservesCount,
        address oracle
    ) internal view {
        (,,,, uint256 healthFactor) = MiniPoolGenericLogic.calculateUserAccountData(
            from, reservesData, userConfig, reserves, reservesCount, oracle
        );

        require(
            healthFactor >= MiniPoolGenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.VL_TRANSFER_NOT_ALLOWED
        );
    }
}
