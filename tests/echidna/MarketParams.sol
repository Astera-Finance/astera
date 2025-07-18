// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Users are defined in users
// Admin is address(this)
contract MarketParams {
    uint256 internal constant BPS = 10000;

    // Market config
    string internal constant MARKET_ID = "Astera";
    address internal constant FALLBACK_ORACLE = address(0);
    address internal constant BASE_CURRENCY = address(0);
    uint256 internal constant BASE_CURRENCY_UNIT = 100000000;

    // Default rate strategies
    uint256 internal constant DEFAULT_OPTI_UTILIZATION_RATE = 0.75e27;
    uint256 internal constant DEFAULT_BASE_VARIABLE_BORROW_RATE = 0;
    uint256 internal constant DEFAULT_VARIABLE_RATE_SLOPE1 = 0.07e27;
    uint256 internal constant DEFAULT_VARIABLE_RATE_SLOPE2 = 3e27;

    // Pi rate strategies
    uint256 internal constant DEFAULT_OPTI_UTILIZATION_RATE_PI = 0.5e27;
    int256 internal constant DEFAULT_MIN_CONTROLLER_ERROR = 1e25;
    int256 internal constant DEFAULT_MAX_I_TIME_AMP = 50e25;
    uint256 internal constant DEFAULT_KP = 1e27;
    uint256 internal constant DEFAULT_KI = 13e19;

    // Lending pool Default reserve config
    uint256 internal constant DEFAULT_BASE_LTV = 8000;
    uint256 internal constant DEFAULT_LIQUIDATION_THRESHOLD = 8500;
    uint256 internal constant DEFAULT_LIQUIDATION_BONUS = 10500;
    uint256 internal constant DEFAULT_RESERVE_FACTOR = 1500;

    // Rehypothecation
    uint256 internal constant DEFAULT_FARMING_PCT = 9000; // 90%
    uint256 internal constant DEFAULT_CLAIMING_THRESHOLD = 100_000; // 100,000 wei of assets
    uint256 internal constant DEFAULT_FARMING_PCT_DRIFT = 100; // 1%

    address constant ETH_USD_SOURCE = 0xb7B9A39CC63f856b90B364911CC324dC46aC1770;
    address constant USDC_USD_SOURCE = 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;
}
