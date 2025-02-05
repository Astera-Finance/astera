// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

/**
 * @title Errors library
 * @author Cod3x
 * @notice Defines the error messages emitted by the different contracts of the Cod3x Lend protocol
 * @dev Error messages prefix glossary:
 *  - VL   :: ValidationLogic
 *  - MATH :: Math libraries
 *  - AT   :: AToken/AToken6909
 *  - LP   :: Pool
 *  - RL   :: ReserveLogic
 *  - LPCM :: Liquidation
 *  - DP   :: DataProvider
 *  - O    :: Oracle
 *  - PAP  :: PoolAddressesProvider
 *  - RC   :: Reserve configuration
 *  - R    :: Rewarder
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
    /// @notice Inconsistent flashloan parameters.
    string public constant VL_INCONSISTENT_FLASHLOAN_PARAMS = "16";
    /// @notice Deposit cap reached.
    string public constant VL_DEPOSIT_CAP_REACHED = "17";
    /// @notice Reserve is inactive.
    string public constant VL_RESERVE_INACTIVE = "18";
    /// @notice Flashloan is disabled.
    string public constant VL_FLASHLOAN_DISABLED = "19";
    /// @notice Tranched asset cannot be flashloaned.
    string public constant VL_TRANCHED_ASSET_CANNOT_BE_FLASHLOAN = "20";
    /// @notice The caller must be the pool admin.
    string public constant VL_CALLER_NOT_POOL_ADMIN = "21";
    /// @notice U0 is greater than RAY.
    string public constant VL_U0_GREATER_THAN_RAY = "22";
    /// @notice Access restricted to lending pool.
    string public constant VL_ACCESS_RESTRICTED_TO_LENDING_POOL = "23";
    /// @notice The liquidity of the reserve needs to be 0.
    string public constant VL_RESERVE_LIQUIDITY_NOT_0 = "24";
    /// @notice Invalid risk parameters for the reserve.
    string public constant VL_INVALID_CONFIGURATION = "25";
    /// @notice The caller must be the emergency admin.
    string public constant VL_CALLER_NOT_EMERGENCY_ADMIN = "26";
    /// @notice Invalid flashloan premium.
    string public constant VL_FLASHLOAN_PREMIUM_INVALID = "27";
    /// @notice Invalid interest rate mode.
    string public constant VL_INVALID_INTEREST_RATE_MODE = "28";

    /// @notice Division by zero.
    string public constant MATH_DIVISION_BY_ZERO = "29";
    /// @notice Multiplication overflow.
    string public constant MATH_MULTIPLICATION_OVERFLOW = "30";

    /// @notice Invalid amount to mint.
    string public constant AT_INVALID_MINT_AMOUNT = "31";
    /// @notice Invalid amount to burn.
    string public constant AT_INVALID_BURN_AMOUNT = "32";
    /// @notice The caller of this function must be a lending pool.
    string public constant AT_CALLER_MUST_BE_LENDING_POOL = "33";
    /// @notice Vault not initialized.
    string public constant AT_VAULT_NOT_INITIALIZED = "34";
    /// @notice Invalid address.
    string public constant AT_INVALID_ADDRESS = "35";
    /// @notice Invalid amount.
    string public constant AT_INVALID_AMOUNT = "36";
    /// @notice Invalid aToken ID.
    string public constant AT_INVALID_ATOKEN_ID = "37";
    /// @notice Invalid aToken address.
    string public constant AT_INVALID_ATOKEN_ADDRESS = "38";
    /// @notice Vault is not empty.
    string public constant AT_VAULT_NOT_EMPTY = "39";
    /// @notice Invalid controller address.
    string public constant AT_INVALID_CONTROLLER = "40";
    /// @notice Caller is not wrapper.
    string public constant AT_CALLER_NOT_WRAPPER = "41";
    /// @notice User borrows on behalf, but allowance is too small.
    string public constant AT_BORROW_ALLOWANCE_NOT_ENOUGH = "42";
    /// @notice The permit has expired.
    string public constant AT_INVALID_EXPIRATION = "43";
    /// @notice The signature is invalid.
    string public constant AT_INVALID_SIGNATURE = "44";
    /// @notice Profit handler not set.
    string public constant AT_PROFIT_HANDLER_SET = "45";

    /// @notice There is not enough liquidity available to borrow.
    string public constant LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW = "46";
    /// @notice The caller of the function is not the lending pool configurator.
    string public constant LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR = "47";
    /// @notice Caller must be an aToken.
    string public constant LP_CALLER_MUST_BE_AN_ATOKEN = "48";
    /// @notice Pool is paused.
    string public constant LP_IS_PAUSED = "49";
    /// @notice No more reserves allowed.
    string public constant LP_NO_MORE_RESERVES_ALLOWED = "50";
    /// @notice Invalid flash loan executor return.
    string public constant LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN = "51";
    /// @notice Not a contract.
    string public constant LP_NOT_CONTRACT = "52";
    /// @notice Caller is not minipool.
    string public constant LP_CALLER_NOT_MINIPOOL = "53";
    /// @notice Base borrow rate can't be negative.
    string public constant LP_BASE_BORROW_RATE_CANT_BE_NEGATIVE = "54";
    /// @notice Invalid index.
    string public constant LP_INVALID_INDEX = "55";
    /// @notice Reserve has already been added.
    string public constant LP_RESERVE_ALREADY_ADDED = "56";

    /// @notice Reserve has already been initialized.
    string public constant RL_RESERVE_ALREADY_INITIALIZED = "57";
    /// @notice Reserve is not initialized.
    string public constant RL_RESERVE_NOT_INITIALIZED = "58";
    /// @notice Liquidity index overflows uint128.
    string public constant RL_LIQUIDITY_INDEX_OVERFLOW = "59";
    /// @notice Variable borrow index overflows uint128.
    string public constant RL_VARIABLE_BORROW_INDEX_OVERFLOW = "60";
    /// @notice Liquidity rate overflows uint128.
    string public constant RL_LIQUIDITY_RATE_OVERFLOW = "61";
    /// @notice Variable borrow rate overflows uint128.
    string public constant RL_VARIABLE_BORROW_RATE_OVERFLOW = "62";

    /// @notice Health factor is not below the threshold.
    string public constant LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD = "63";
    /// @notice The collateral chosen cannot be liquidated.
    string public constant LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED = "64";
    /// @notice User did not borrow the specified currency.
    string public constant LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER = "65";
    /// @notice There is not enough liquidity available to liquidate.
    string public constant LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE = "66";

    /// @notice Inconsistent parameters length.
    string public constant O_INCONSISTENT_PARAMS_LENGTH = "67";
    /// @notice Price feed inconsistency.
    string public constant O_PRICE_FEED_INCONSISTENCY = "68";

    /// @notice No mini pool ID for address.
    string public constant PAP_NO_MINI_POOL_ID_FOR_ADDRESS = "69";
    /// @notice Pool ID out of range.
    string public constant PAP_POOL_ID_OUT_OF_RANGE = "70";

    /// @notice Invalid LTV.
    string public constant RC_INVALID_LTV = "71";
    /// @notice Invalid liquidation threshold.
    string public constant RC_INVALID_LIQ_THRESHOLD = "72";
    /// @notice Invalid liquidation bonus.
    string public constant RC_INVALID_LIQ_BONUS = "73";
    /// @notice Invalid decimals.
    string public constant RC_INVALID_DECIMALS = "74";
    /// @notice Invalid reserve factor.
    string public constant RC_INVALID_RESERVE_FACTOR = "75";
    /// @notice Invalid deposit cap.
    string public constant RC_INVALID_DEPOSIT_CAP = "76";
    /// @notice LendingPool not set.
    string public constant DP_LENDINGPOOL_NOT_SET = "77";
    /// @notice Reserve is not configured.
    string public constant DP_RESERVE_NOT_CONFIGURED = "78";

    /// @notice Not registered.
    string public constant R_NOT_REGISTERED = "79";
    /// @notice Too many reward tokens.
    string public constant R_TOO_MANY_REWARD_TOKENS = "80";
    /// @notice No forwarder set.
    string public constant R_NO_FORWARDER_SET = "81";
    /// @notice Claimer unauthorized.
    string public constant R_CLAIMER_UNAUTHORIZED = "82";
    /// @notice Invalid address.
    string public constant R_INVALID_ADDRESS = "83";
    /// @notice Already set.
    string public constant R_ALREADY_SET = "84";
    /// @notice Transfer error.
    string public constant R_TRANSFER_ERROR = "85";
    /// @notice Rewarder not set.
    string public constant R_REWARDER_NOT_SET = "86";
}
