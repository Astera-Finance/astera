// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Users are defined in users
// Admin is address(this)
contract MarketParams {
    uint256 internal constant BPS = 10000;

    // Market config
    string internal constant MARKET_ID = "Cod3x Lend";
    address internal constant FALLBACK_ORACLE = address(0);
    address internal constant BASE_CURRENCY = address(0);
    uint256 internal constant BASE_CURRENCY_UNIT = 100000000;

    // Default rate strategies
    uint256 internal constant DEFAULT_OPTI_UTILIZATION_RATE = 0.45e27;
    uint256 internal constant DEFAULT_BASE_VARIABLE_BORROW_RATE = 0;
    uint256 internal constant DEFAULT_VARIABLE_RATE_SLOPE1 = 0.07e27;
    uint256 internal constant DEFAULT_VARIABLE_RATE_SLOPE2 = 3e27;

    // Pi rate strategies
    int256 internal constant DEFAULT_MIN_CONTROLLER_ERROR = 0;
    int256 internal constant DEFAULT_MAX_I_TIME_AMP = 0;
    uint256 internal constant DEFAULT_KP = 0;
    uint256 internal constant DEFAULT_KI = 0;

    // Lending pool Default reserve config
    uint256 internal constant DEFAULT_BASE_LTV = 8000;
    uint256 internal constant DEFAULT_LIQUIDATION_THRESHOLD = 8500;
    uint256 internal constant DEFAULT_LIQUIDATION_BONUS = 10500;
    uint256 internal constant DEFAULT_RESERVE_FACTOR = 1500;

    // Rehypothecation
    uint256 internal constant DEFAULT_FARMING_PCT = 9000; // 90%
    uint256 internal constant DEFAULT_CLAIMING_THRESHOLD = 100_000; // 100,000 wei of assets
    uint256 internal constant DEFAULT_FARMING_PCT_DRIFT = 100; // 1%
}
