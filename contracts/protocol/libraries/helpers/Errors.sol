// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

/**
 * @title Errors library
 * @author Cod3x
 * @notice Defines the error messages emitted by the different contracts of the Cod3x Lend protocol
 * @dev Error messages prefix glossary:
 *  - VL = ValidationLogic
 *  - MATH = Math libraries
 *  - CT = Common errors between tokens
 *  - AT = AToken
 *  - LP = LendingPool
 *  - LPC = LendingPoolConfiguration
 *  - RL = ReserveLogic
 *  - LPCM = Liquidation
 *  - P = Pausable
 *  - DP = DataProvider
 *  - O = Oracle
 *  - PAP = PoolAddressesProvider
 *  - IR = Interest rate strategies
 */
library Errors {
    /// @notice Amount must be greater than 0.
    string public constant VL_INVALID_INPUT = "0";
    /// @notice Amount must be greater than 0.
    string public constant VL_INVALID_AMOUNT = "1";
    /// @notice Action requires an active reserve.
    string public constant VL_NO_ACTIVE_RESERVE = "2";
    /// @notice Action cannot be performed because the reserve is frozen.
    string public constant VL_RESERVE_FROZEN = "3";
    /// @notice User cannot withdraw more than the available balance.
    string public constant VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE = "4";
    /// @notice Transfer cannot be allowed.
    string public constant VL_TRANSFER_NOT_ALLOWED = "5";
    /// @notice Borrowing is not enabled.
    string public constant VL_BORROWING_NOT_ENABLED = "6";
    /// @notice The collateral balance is 0.
    string public constant VL_COLLATERAL_BALANCE_IS_0 = "7";
    /// @notice Health factor is lesser than the liquidation threshold.
    string public constant VL_HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD = "8";
    /// @notice There is not enough collateral to cover a new borrow.
    string public constant VL_COLLATERAL_CANNOT_COVER_NEW_BORROW = "9";
    /// @notice Flow is not enough.
    string public constant VL_BORROW_FLOW_LIMIT_REACHED = "10";
    /// @notice Minipool position cannot be liquidated.
    string public constant VL_MINIPOOL_CANNOT_BE_LIQUIDATED = "11";
    /// @notice For repayment of stable debt, the user needs to have stable debt, otherwise, he needs to have variable debt.
    string public constant VL_NO_DEBT_OF_SELECTED_TYPE = "12";
    /// @notice To repay on behalf of a user an explicit amount to repay is needed.
    string public constant VL_NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF = "13";
    /// @notice The underlying balance needs to be greater than 0.
    string public constant VL_UNDERLYING_BALANCE_NOT_GREATER_THAN_0 = "14";
    /// @notice User deposit is already being used as collateral.
    string public constant VL_DEPOSIT_ALREADY_IN_USE = "15";
    /// @notice The caller must be the pool admin.
    string public constant CALLER_NOT_POOL_ADMIN = "16";
    /// @notice User borrows on behalf, but allowance is too small.
    string public constant BORROW_ALLOWANCE_NOT_ENOUGH = "17";
    /// @notice There is not enough liquidity available to borrow.
    string public constant LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW = "18";
    /// @notice The caller of the function is not the lending pool configurator.
    string public constant LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR = "19";
    /// @notice The caller of this function must be a lending pool.
    string public constant CT_CALLER_MUST_BE_LENDING_POOL = "20";
    /// @notice Reserve has already been initialized.
    string public constant RL_RESERVE_ALREADY_INITIALIZED = "21";
    /// @notice Reserve is not initialized.
    string public constant RL_RESERVE_NOT_INITIALIZED = "22";
    /// @notice The liquidity of the reserve needs to be 0.
    string public constant LPC_RESERVE_LIQUIDITY_NOT_0 = "23";
    /// @notice Invalid risk parameters for the reserve.
    string public constant LPC_INVALID_CONFIGURATION = "24";
    /// @notice The caller must be the emergency admin.
    string public constant LPC_CALLER_NOT_EMERGENCY_ADMIN = "25";
    /// @notice Health factor is not below the threshold.
    string public constant LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD = "26";
    /// @notice The collateral chosen cannot be liquidated.
    string public constant LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED = "27";
    /// @notice User did not borrow the specified currency.
    string public constant LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER = "28";
    /// @notice There is not enough liquidity available to liquidate.
    string public constant LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE = "29";
    /// @notice Multiplication overflow.
    string public constant MATH_MULTIPLICATION_OVERFLOW = "30";
    /// @notice Addition overflow.
    string public constant MATH_ADDITION_OVERFLOW = "31";
    /// @notice Division by zero.
    string public constant MATH_DIVISION_BY_ZERO = "32";
    /// @notice Liquidity index overflows uint128.
    string public constant RL_LIQUIDITY_INDEX_OVERFLOW = "33";
    /// @notice Variable borrow index overflows uint128.
    string public constant RL_VARIABLE_BORROW_INDEX_OVERFLOW = "34";
    /// @notice Liquidity rate overflows uint128.
    string public constant RL_LIQUIDITY_RATE_OVERFLOW = "35";
    /// @notice Variable borrow rate overflows uint128.
    string public constant RL_VARIABLE_BORROW_RATE_OVERFLOW = "36";
    /// @notice Invalid amount to mint.
    string public constant CT_INVALID_MINT_AMOUNT = "37";
    /// @notice Invalid amount to burn.
    string public constant CT_INVALID_BURN_AMOUNT = "38";
    /// @notice Caller must be an aToken.
    string public constant LP_CALLER_MUST_BE_AN_ATOKEN = "39";
    /// @notice Pool is paused.
    string public constant LP_IS_PAUSED = "40";
    /// @notice No more reserves allowed.
    string public constant LP_NO_MORE_RESERVES_ALLOWED = "41";
    /// @notice Invalid flash loan executor return.
    string public constant LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN = "42";
    /// @notice Invalid LTV.
    string public constant RC_INVALID_LTV = "43";
    /// @notice Invalid liquidation threshold.
    string public constant RC_INVALID_LIQ_THRESHOLD = "44";
    /// @notice Invalid liquidation bonus.
    string public constant RC_INVALID_LIQ_BONUS = "45";
    /// @notice Invalid decimals.
    string public constant RC_INVALID_DECIMALS = "46";
    /// @notice Invalid reserve factor.
    string public constant RC_INVALID_RESERVE_FACTOR = "47";
    /// @notice Inconsistent flashloan parameters.
    string public constant VL_INCONSISTENT_FLASHLOAN_PARAMS = "48";
    /// @notice Invalid index.
    string public constant UL_INVALID_INDEX = "49";
    /// @notice Not a contract.
    string public constant LP_NOT_CONTRACT = "50";
    /// @notice Vault not initialized.
    string public constant AT_VAULT_NOT_INITIALIZED = "51";
    /// @notice Invalid deposit cap.
    string public constant RC_INVALID_DEPOSIT_CAP = "52";
    /// @notice Deposit cap reached.
    string public constant VL_DEPOSIT_CAP_REACHED = "53";
    /// @notice Invalid address.
    string public constant AT_INVALID_ADDRESS = "54";
    /// @notice Invalid amount.
    string public constant AT_INVALID_AMOUNT = "55";
    /// @notice Invalid aToken ID.
    string public constant AT_INVALID_ATOKEN_ID = "56";
    /// @notice Caller is not minipool.
    string public constant LP_CALLER_NOT_MINIPOOL = "57";
    /// @notice Invalid aToken address.
    string public constant AT_INVALID_ATOKEN_ADDRESS = "58";
    /// @notice Reserve is inactive.
    string public constant VL_RESERVE_INACTIVE = "59";
    /// @notice Flashloan is disabled.
    string public constant VL_FLASHLOAN_DISABLED = "60";
    /// @notice Invalid flashloan premium.
    string public constant LPC_FLASHLOAN_PREMIUM_INVALID = "61";
    /// @notice Tranched asset cannot be flashloaned.
    string public constant VL_TRANCHED_ASSET_CANNOT_BE_FLASHLOAN = "62";
    /// @notice LendingPool not set.
    string public constant DP_LENDINGPOOL_NOT_SET = "63";
    /// @notice Inconsistent parameters length.
    string public constant O_INCONSISTENT_PARAMS_LENGTH = "64";
    /// @notice Price feed inconsistency.
    string public constant O_PRICE_FEED_INCONSISTENCY = "65";
    /// @notice No mini pool ID for address.
    string public constant PAP_NO_MINI_POOL_ID_FOR_ADDRESS = "66";
    /// @notice Pool ID out of range.
    string public constant PAP_POOL_ID_OUT_OF_RANGE = "67";
    /// @notice Vault is not empty.
    string public constant AT_VAULT_NOT_EMPTY = "68";
    /// @notice Invalid controller address.
    string public constant AT_INVALID_CONTROLLER = "69";
    /// @notice U0 is greater than RAY.
    string public constant IR_U0_GREATER_THAN_RAY = "70";
    /// @notice Base borrow rate can't be negative.
    string public constant IR_BASE_BORROW_RATE_CANT_BE_NEGATIVE = "71";
    /// @notice Access restricted to lending pool.
    string public constant IR_ACCESS_RESTRICTED_TO_LENDING_POOL = "72";
    /// @notice Reserve is not configured.
    string public constant DP_RESERVE_NOT_CONFIGURED = "73";
}
