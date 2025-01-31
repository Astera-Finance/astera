// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {BorrowLogic} from "./BorrowLogic.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {SafeERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {ReserveConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {Helpers} from "../../../../../contracts/protocol/libraries/helpers/Helpers.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title ValidationLogic library
 * @author Cod3x
 * @notice Implements functions to validate the different actions of the protocol.
 * @dev Contains validation functions for all protocol operations.
 */
library ValidationLogic {
    using ReserveLogic for DataTypes.ReserveData;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /**
     * @dev Validates a deposit action.
     * @param reserve The reserve object on which the user is depositing.
     * @param amount The amount to be deposited.
     * @notice Checks if deposit is allowed based on reserve status and deposit cap.
     * @notice Checks that:
     * - The reserve is active and not frozen.
     * - The deposit cap has not been reached.
     * - The amount is valid.
     */
    function validateDeposit(DataTypes.ReserveData storage reserve, uint256 amount) internal view {
        (bool isActive, bool isFrozen,) = reserve.configuration.getFlags();

        // Deposit cap check uses an approximation:
        // It uses the previous liquidity index instead of the next liquidity index.
        uint256 depositCap = reserve.configuration.getDepositCap();
        require(
            depositCap == 0
                || IERC20(reserve.aTokenAddress).totalSupply() + amount
                    < depositCap * (10 ** reserve.configuration.getDecimals()),
            Errors.VL_DEPOSIT_CAP_REACHED
        );

        require(amount != 0, Errors.VL_INVALID_AMOUNT);
        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);
        require(!isFrozen, Errors.VL_RESERVE_FROZEN);
    }

    /**
     * @dev Validates a withdraw action.
     * @param reserveAddress The address of the reserve.
     * @param amount The amount to be withdrawn.
     * @param userBalance The balance of the user.
     * @param reserves The reserves state.
     * @param userConfig The user configuration.
     * @param reserves The addresses of the reserves.
     * @param reservesCount The number of reserves.
     * @param oracle The price oracle.
     */
    struct ValidateWithdrawParams {
        address reserveAddress;
        bool reserveType;
        uint256 amount;
        uint256 userBalance;
        uint256 reservesCount;
        address oracle;
    }
    /**
     * @dev Validates a withdraw action by checking various conditions.
     * @param validateParams The parameters needed for validation including `reserveAddress`, `reserveType`, `amount`, `userBalance`, `reservesCount` and `oracle`.
     * @param reserves The state of all the reserves.
     * @param userConfig The user configuration containing the user's current state.
     * @param reservesList The list of all reserves in the protocol.
     * @notice Checks if:
     * - The withdrawal amount is valid and available in user balance.
     * - The reserve is active.
     * - The withdrawal would not put the user's health factor below threshold.
     */

    function validateWithdraw(
        ValidateWithdrawParams memory validateParams,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList
    ) internal view {
        require(validateParams.amount != 0, Errors.VL_INVALID_AMOUNT);
        require(
            validateParams.amount <= validateParams.userBalance,
            Errors.VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE
        );

        (bool isActive,,) = reserves[validateParams.reserveAddress][validateParams.reserveType]
            .configuration
            .getFlags();
        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);

        require(
            GenericLogic.balanceDecreaseAllowed(
                validateParams.reserveAddress,
                validateParams.reserveType,
                msg.sender,
                validateParams.amount,
                reserves,
                userConfig,
                reservesList,
                validateParams.reservesCount,
                validateParams.oracle
            ),
            Errors.VL_TRANSFER_NOT_ALLOWED
        );
    }

    /**
     * @dev Parameters for validating a borrow action.
     * @param userAddress The address of the user.
     * @param amount The amount to be borrowed.
     * @param amountInETH The amount to be borrowed, in ETH.
     * @param reservesCount The number of reserves.
     * @param oracle The price oracle address.
     */
    struct ValidateBorrowParams {
        address userAddress;
        uint256 amount;
        uint256 amountInETH;
        uint256 reservesCount;
        address oracle;
    }

    /**
     * @dev Local variables for borrow validation.
     */
    struct ValidateBorrowLocalVars {
        uint256 currentLtv;
        uint256 currentLiquidationThreshold;
        uint256 amountOfCollateralNeededETH;
        uint256 userCollateralBalanceETH;
        uint256 userBorrowBalanceETH;
        uint256 healthFactor;
        bool isActive;
        bool isFrozen;
        bool borrowingEnabled;
    }

    /**
     * @dev Validates a borrow action.
     * @param validateParams The parameters for validation.
     * @param reserve The reserve state from which the user is borrowing.
     * @param reserves The state of all the reserves.
     * @param userConfig The state of the user for the specific reserve.
     * @param reservesList The addresses of all the active reserves.
     * @notice Checks that:
     * - The reserve is active and not frozen.
     * - The amount is valid and not zero.
     * - Borrowing is enabled.
     * - The user has sufficient collateral.
     * - The resulting health factor is above the threshold.
     */
    function validateBorrow(
        ValidateBorrowParams memory validateParams,
        DataTypes.ReserveData storage reserve,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList
    ) internal view {
        ValidateBorrowLocalVars memory vars;
        BorrowLogic.CalculateUserAccountDataVolatileParams memory params;
        params.user = validateParams.userAddress;
        params.reservesCount = validateParams.reservesCount;
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
        ) = BorrowLogic.calculateUserAccountDataVolatile(params, reserves, userConfig, reservesList);

        require(vars.userCollateralBalanceETH > 0, Errors.VL_COLLATERAL_BALANCE_IS_0);

        require(
            vars.healthFactor >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.VL_HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
        );

        // Add the current already borrowed amount to the amount requested to calculate the total collateral needed.
        vars.amountOfCollateralNeededETH =
            (vars.userBorrowBalanceETH + validateParams.amountInETH).percentDivUp(vars.currentLtv); //LTV is calculated in percentage

        require(
            vars.amountOfCollateralNeededETH < vars.userCollateralBalanceETH,
            Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW
        );
    }

    /**
     * @dev Validates a repay action.
     * @param reserve The reserve state from which the user is repaying.
     * @param amountSent The amount sent for the repayment. Can be an actual value or uint(-1).
     * @param onBehalfOf The address of the user msg.sender is repaying for.
     * @param variableDebt The borrow balance of the user.
     * @notice Checks that:
     * - The reserve is active.
     * - The amount is valid and not zero.
     * - The user has a non-zero borrow balance.
     */
    function validateRepay(
        DataTypes.ReserveData storage reserve,
        uint256 amountSent,
        address onBehalfOf,
        uint256 variableDebt
    ) internal view {
        bool isActive = reserve.configuration.getActive();

        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);

        require(amountSent != 0, Errors.VL_INVALID_AMOUNT);

        require(variableDebt != 0, Errors.VL_NO_DEBT_OF_SELECTED_TYPE);

        require(
            amountSent != type(uint256).max || msg.sender == onBehalfOf,
            Errors.VL_NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF
        );
    }

    /**
     * @dev Validates the action of setting an asset as collateral.
     * @param reserve The state of the reserve that the user is enabling or disabling as collateral.
     * @param reserveAddress The address of the reserve.
     * @param reserves The data of all the reserves.
     * @param userConfig The state of the user for the specific reserve.
     * @param reservesList The addresses of all the active reserves.
     * @param oracle The price oracle.
     * @notice Checks that:
     * - The user has a non-zero balance of the reserve's aToken.
     * - The user's balance decrease is allowed for the reserve.
     */
    function validateSetUseReserveAsCollateral(
        DataTypes.ReserveData storage reserve,
        address reserveAddress,
        bool reserveType,
        bool useAsCollateral,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        uint256 reservesCount,
        address oracle
    ) internal view {
        uint256 underlyingBalance = IERC20(reserve.aTokenAddress).balanceOf(msg.sender);

        require(underlyingBalance > 0, Errors.VL_UNDERLYING_BALANCE_NOT_GREATER_THAN_0);

        require(
            useAsCollateral
                || GenericLogic.balanceDecreaseAllowed(
                    reserveAddress,
                    reserveType,
                    msg.sender,
                    underlyingBalance,
                    reserves,
                    userConfig,
                    reservesList,
                    reservesCount,
                    oracle
                ),
            Errors.VL_DEPOSIT_ALREADY_IN_USE
        );
    }

    /**
     * @dev Validates a flashloan action.
     * @param reserves The state of all the reserves.
     * @param assets The assets being flash-borrowed.
     * @param amounts The amounts for each asset being borrowed.
     * @notice Checks that:
     * - The number of assets and amounts are consistent.
     * - Each reserve is active and not frozen.
     * - Flash loans are enabled for each reserve.
     */
    function validateFlashloan(
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        bool[] memory reserveType,
        address[] memory assets,
        uint256[] memory amounts
    ) internal view {
        uint256 len = assets.length;
        require(len == amounts.length, Errors.VL_INCONSISTENT_FLASHLOAN_PARAMS);
        require(len == reserveType.length, Errors.VL_INCONSISTENT_FLASHLOAN_PARAMS);

        for (uint256 i = 0; i < assets.length; i++) {
            validateFlashloanSimple(reserves[assets[i]][reserveType[i]]);
        }
    }

    /**
     * @dev Validates a flashloan action for a single reserve.
     * @param reserve The state of the reserve.
     * @notice Checks that:
     * - The reserve is not frozen.
     * - The reserve is active.
     * - Flash loans are enabled for the reserve.
     */
    function validateFlashloanSimple(DataTypes.ReserveData storage reserve) internal view {
        DataTypes.ReserveConfigurationMap storage configuration = reserve.configuration;
        require(!configuration.getFrozen(), Errors.VL_RESERVE_FROZEN);
        require(configuration.getActive(), Errors.VL_RESERVE_INACTIVE);
        require(configuration.getFlashLoanEnabled(), Errors.VL_FLASHLOAN_DISABLED);
    }

    /**
     * @dev Validates the liquidation action.
     * @param collateralReserve The reserve data of the collateral.
     * @param principalReserve The reserve data of the principal.
     * @param userConfig The user configuration.
     * @param userHealthFactor The user's health factor.
     * @param userVariableDebt Total variable debt balance of the user.
     * @notice Checks that:
     * - Both collateral and principal reserves are active.
     * - The user's health factor is below the liquidation threshold.
     * - The collateral is enabled as collateral for the user.
     * - The user has a non-zero variable debt balance.
     */
    function validateLiquidationCall(
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage principalReserve,
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 userHealthFactor,
        uint256 userVariableDebt
    ) internal view {
        if (
            !collateralReserve.configuration.getActive()
                || !principalReserve.configuration.getActive()
        ) {
            revert(Errors.VL_NO_ACTIVE_RESERVE);
        }

        if (userHealthFactor >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {
            revert(Errors.LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD);
        }

        bool isCollateralEnabled = collateralReserve.configuration.getLiquidationThreshold() > 0
            && userConfig.isUsingAsCollateral(collateralReserve.id);

        // If collateral isn't enabled as collateral by user, it cannot be liquidated.
        if (!isCollateralEnabled) {
            revert(Errors.LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED);
        }

        if (userVariableDebt == 0) {
            revert(Errors.LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER);
        }
    }

    /**
     * @dev Validates an aToken transfer.
     * @param from The user from which the aTokens are being transferred.
     * @param reserves The state of all the reserves.
     * @param userConfig The state of the user for the specific reserve.
     * @param reservesList The addresses of all the active reserves.
     * @param oracle The price oracle.
     * @notice Checks that:
     * - The user's health factor is above the liquidation threshold.
     */
    function validateTransfer(
        address from,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        uint256 reservesCount,
        address oracle
    ) internal view {
        (,,,, uint256 healthFactor) = GenericLogic.calculateUserAccountData(
            from, reserves, userConfig, reservesList, reservesCount, oracle
        );

        require(
            healthFactor >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.VL_TRANSFER_NOT_ALLOWED
        );
    }
}
