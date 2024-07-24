// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Users are defined in users
// Admin is address(this)
contract MarketParams {
    uint internal constant BPS = 10000; 

    string internal constant MARKET_ID = "GV2";
    uint internal constant PROVIDER_ID = 1;
    address internal constant FALLBACK_ORACLE = address(0);
    address internal constant BASE_CURRENCY = address(0);
    uint internal constant BASE_CURRENCY_UNIT = 100000000;

    uint internal constant DEFAULT_OPTI_UTILIZATION_RATE = 0.45e27;
    uint internal constant DEFAULT_BASE_VARIABLE_BORROW_RATE = 0;
    uint internal constant DEFAULT_VARIABLE_RATE_SLOPE1 = 0.07e27;
    uint internal constant DEFAULT_VARIABLE_RATE_SLOPE2 = 3e27;

    uint internal constant DEFAULT_BASE_LTV = 8000;
    uint internal constant DEFAULT_LIQUIDATION_THRESHOLD = 8500;
    uint internal constant DEFAULT_LIQUIDATION_BONUS = 10500;
    uint internal constant DEFAULT_RESERVE_FACTOR = 1500;
}