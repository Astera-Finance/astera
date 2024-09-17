import "./DeployDataTypes.s.sol";
//this config is used to load information about assets that will be mocked
//addresses of the actual assets are not relevent until mainnet deployment
//they may be useful after deployment as well

//main lending pool assets
contract localDeployConfig{
    string[] MainPoolnames =
        ["UV TEST Wrapped ETHER", "UV TEST USDC", "UV TEST USDT", "UV TEST WBTC"];
    string[] MainPoolSymbols =
        ["WETH", "USDC", "USDT", "WBTC"];
    uint8[] MainPoolDecimals = [18, 6, 6, 8];
    int256[] MainPoolPrices = [int256(2700e8), 1e8, 1e8, 60000e8];  //type-casting one forces the type of all to be the same
    bool[] isStableStrategy = [false, true, true, false];
    bool[] reserveTypes = [true, true, true, true];
    /* Utilization rate targeted by the model, beyond the variable interest rate rises sharply */
    uint256 constant VOLATILE_OPTIMAL_UTILIZATION_RATE = 0.45e27;
    uint256 constant STABLE_OPTIMAL_UTILIZATION_RATE = 0.8e27;

    /* Constant rates when total borrow is 0 */
    uint256 constant VOLATILE_BASE_VARIABLE_BORROW_RATE = 0e27;
    uint256 constant STABLE_BASE_VARIABLE_BORROW_RATE = 0e27;

    /* Constant rates reprezenting scaling of the interest rate */
    uint256 constant VOLATILE_VARIABLE_RATE_SLOPE_1 = 0.07e27;
    uint256 constant STABLE_VARIABLE_RATE_SLOPE_1 = 0.04e27;
    uint256 constant VOLATILE_VARIABLE_RATE_SLOPE_2 = 3e27;
    uint256 constant STABLE_VARIABLE_RATE_SLOPE_2 = 0.75e27;
    uint256[] volStrat = [
        VOLATILE_OPTIMAL_UTILIZATION_RATE,
        VOLATILE_BASE_VARIABLE_BORROW_RATE,
        VOLATILE_VARIABLE_RATE_SLOPE_1,
        VOLATILE_VARIABLE_RATE_SLOPE_2
    ]; // optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2
    uint256[] sStrat = [
        STABLE_OPTIMAL_UTILIZATION_RATE,
        STABLE_BASE_VARIABLE_BORROW_RATE,
        STABLE_VARIABLE_RATE_SLOPE_1,
        STABLE_VARIABLE_RATE_SLOPE_2
    ];
    uint256[] rates = [ 0.03e27, 0.039e27, 0.039e27, 0.03e27]; //eth, usdc, usdt, wbtc

    uint256[] baseLTVs = [uint256(7000), uint256(8000), uint256(8000), uint256(6500)];
    uint256[] liquidationThresholds = [uint256(7500), uint256(8750), uint256(8500), uint256(7000)];
    uint256[] liquidationBonuses = [uint256(10500), uint256(10500), uint256(10500), uint256(10500)];
    uint256[] reserveFactors = [uint256(1500), uint256(1000), uint256(1000), uint256(500)];
    bool[] borrowingEnabled = [true, true, true, true];

    //MINIPOOL DATA
    //MINIPOOL1 PENDLEASSETS - ETH DERIVATIVES
     string[] MiniPoolOneNames =
        ["UV TEST MP-PT_ezETH", "UV TEST MP-PT_eETH", "UV TEST MP-PT_uniETH", "UV TEST MP-PT_rsETH", "UV TEST MP-PT_wstETH"];
    string[] MiniPoolOneSymbols =
        ["PT-ezETH", "PT-eETH", "PT-uniETH", "PT-rsETH", "PT-wstETH"];
    uint8[] MiniPoolOneDecimals = [18, 18, 18, 18, 18];
    int256[] MiniPoolOnePrices = [int256(2700e8), int256(2700e8), int256(2700e8), int256(2700e8), int256(2686e8)];  //type-casting one forces the type of all to be the same
    bool[] MiniPoolOneisStableStrategy = [true, true, true, true, true];
    bool[] MiniPoolOnereserveTypes = [true, true, true, true, true];
    uint256[] MiniPoolOnebaseLTVs = [uint256(8000), uint256(8000), uint256(8000), uint256(8000), uint256(8000)];
    uint256[] MiniPoolOneliquidationThresholds = [uint256(8750), uint256(8750), uint256(8750), uint256(8750), uint256(8750)];
    uint256[] MiniPoolOneliquidationBonuses = [uint256(10500), uint256(10500), uint256(10500), uint256(10500), uint256(10500)];
    uint256[] MiniPoolOnereserveFactors = [uint256(1000), uint256(1000), uint256(1000), uint256(1000), uint256(1000)];
    bool[] MiniPoolOneborrowingEnabled = [true, true, true, true, true];

    

    //MINIPOOL2 PENDLEASSETS - USD DERIVATIVES
    string[] MiniPoolTwoNames =
        ["UV TEST MP-PT_gUSDC", "UV TEST MP-PT_gDAI", "UV TEST MP-PT_USDe3DAY", "UV TEST MP-PT_USDe90DAY"];
    string[] MiniPoolTwoSymbols =
        ["PT_gUSDC", "PT-gDAI", "PT-USDe3DAY", "PT-USDe90DAY"];
    uint8[] MiniPoolTwoDecimals = [6, 18, 18, 18];
    int256[] MiniPoolTwoPrices = [int256(973e5), int256(991e5), int256(997e5), int256(982e5)];  //type-casting one forces the type of all to be the same
    bool[] MiniPoolTwoisStableStrategy = [true, true, true, true];
    bool[] MiniPoolTwoReserveTypes = [true, true, true, true];
    uint256[] MiniPoolTwoBaseLTVs = [uint256(7000), uint256(8000), uint256(8000), uint256(6500)];
    uint256[] MiniPoolTwoLiquidationThresholds = [uint256(7500), uint256(8750), uint256(8500), uint256(7000)];
    uint256[] MiniPoolTwoLiquidationBonuses = [uint256(10500), uint256(10500), uint256(10500), uint256(10500)];
    uint256[] MiniPoolTwoReserveFactors = [uint256(1500), uint256(1000), uint256(1000), uint256(500)];
    bool[] MiniPoolTwoBorrowingEnabled = [true, true, true, true];


    //STANDARD TRANCHED ASSET TERMS
        uint256[] trancheBaseLTVs = [uint256(9000)];
        uint256[] trancheLiquidationThresholds = [uint256(9250)];
        uint256[] trancheLiquidationBonuses = [uint256(10500)];
        uint256[] trancheReserveFactors = [uint256(1500)];
        bool[] trancheBorrowingEnabled = [true];
        bool[] trancheReserveTypes = [true];
        bool[] trancheIsStableStrategy = [true];
}