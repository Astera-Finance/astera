// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.0;

// import "./Common.sol";
// // import "forge-std/Test.sol";
// // import "forge-std/console.sol";
// // import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
// // import "contracts/protocol/rewarder/lendingpool/Rewarder.sol";
// // import "contracts/misc/Oracle.sol";
// // import "contracts/misc/ProtocolDataProvider.sol";
// // import "contracts/misc/Treasury.sol";
// // import "contracts/misc/UiPoolDataProviderV2.sol";
// // import "contracts/misc/WETHGateway.sol";
// // import "contracts/protocol/libraries/logic/ReserveLogic.sol";
// // import "contracts/protocol/libraries/logic/GenericLogic.sol";
// // import "contracts/protocol/libraries/logic/ValidationLogic.sol";
// // import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
// // import "contracts/protocol/configuration/LendingPoolAddressesProviderRegistry.sol";
// // import "contracts/protocol/lendingpool/interestRateStrategies/DefaultReserveInterestRateStrategy.sol";
// // import "contracts/protocol/lendingpool/LendingPool.sol";
// // import "contracts/protocol/lendingpool/LendingPoolCollateralManager.sol";
// // import "contracts/protocol/lendingpool/LendingPoolConfigurator.sol";

// // import "contracts/treasury/GranaryTreasury.sol";
// // import "contracts/deployments/StableAndVariableTokensHelper.sol";

// // import "contracts/deployments/ATokensAndRatesHelper.sol";
// // import "contracts/protocol/tokenization/ERC20/AToken.sol";
// // import "contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
// // import "contracts/mocks/tokens/MintableERC20.sol";
// // import "contracts/mocks/tokens/WETH9Mocked.sol";
// // import "contracts/mocks/oracle/MockAggregator.sol";
// // import "contracts/mocks/tokens/MockVault.sol";
// // import "contracts/mocks/tokens/MockStrat.sol";
// // import "contracts/mocks/tokens/ExternalContract.sol";
// // import "contracts/mocks/dependencies/IStrategy.sol";
// // import "contracts/mocks/dependencies/IExternalContract.sol";

// // struct InitReserveInput {
// //     address aTokenImpl;
// //     address variableDebtTokenImpl;
// //     uint8 underlyingAssetDecimals;
// //     address interestRateStrategyAddress;
// //     address underlyingAsset;
// //     address treasury;
// //     address incentivesController;
// //     string underlyingAssetName;
// //     bool reserveType;
// //     string aTokenName;
// //     string aTokenSymbol;
// //     string variableDebtTokenName;
// //     string variableDebtTokenSymbol;
// //     bytes params;
// // }

// contract Rehypothecation is Common {
//     function setUp() public {
//         // Forking
//         opFork = vm.createSelectFork(RPC, FORK_BLOCK);
//         assertEq(vm.activeFork(), opFork);

//         MintableERC20 mintableUsdc = new MintableERC20("Test Usdc", "USDC", 6);
//         MintableERC20 mintableWbtc = new MintableERC20("Test Wbtc", "WBTC", 8);
//         WETH9Mocked mintableWeth = new WETH9Mocked();

//         usdcPriceFeed = new MockAggregator(100000000, int256(uint256(mintableUsdc.decimals())));
//         wbtcPriceFeed = new MockAggregator(1600000000000, int256(uint256(mintableWbtc.decimals())));
//         ethPriceFeed = new MockAggregator(120000000000, int256(uint256(mintableWeth.decimals())));
//         aggregators = [address(usdcPriceFeed), address(wbtcPriceFeed), address(ethPriceFeed)];

//         rewarder = new Rewarder();
//         // bytes memory args = abi.encode();
//         // bytes memory bytecode = abi.encodePacked(vm.getCode("contracts/incentives/Rewarder.sol:Rewarder"));
//         // address anotherAddress;
//         // assembly {
//         //     anotherAddress := create(0, add(bytecode, 0x20), mload(bytecode))
//         // }

//         lendingPoolAddressesProviderRegistry = new LendingPoolAddressesProviderRegistry();
//         lendingPoolAddressesProvider = new LendingPoolAddressesProvider(marketId);
//         lendingPoolAddressesProviderRegistry.registerAddressesProvider(
//             address(lendingPoolAddressesProvider), providerId
//         );
//         lendingPoolAddressesProvider.setPoolAdmin(admin);
//         lendingPoolAddressesProvider.setEmergencyAdmin(admin);

//         // reserveLogic = address(new ReserveLogic());
//         // genericLogic = address(new GenericLogic());
//         // validationLogic = address(new ValidationLogic());
//         lendingPool = new LendingPool();
//         lendingPool.initialize(ILendingPoolAddressesProvider(lendingPoolAddressesProvider));
//         lendingPoolAddressesProvider.setLendingPoolImpl(address(lendingPool));
//         lendingPoolProxyAddress = address(lendingPoolAddressesProvider.getLendingPool());
//         lendingPoolProxy = LendingPool(lendingPoolProxyAddress);
//         treasury = new Treasury(lendingPoolAddressesProvider);
//         // granaryTreasury = new GranaryTreasury(ILendingPoolAddressesProvider(lendingPoolAddressesProvider));

//         lendingPoolConfigurator = new LendingPoolConfigurator();
//         lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(address(lendingPoolConfigurator));
//         lendingPoolConfiguratorProxyAddress = lendingPoolAddressesProvider.getLendingPoolConfigurator();
//         lendingPoolConfiguratorProxy = LendingPoolConfigurator(lendingPoolConfiguratorProxyAddress);
//         vm.prank(admin);
//         lendingPoolConfiguratorProxy.setPoolPause(true);

//         // stableAndVariableTokensHelper = new StableAndVariableTokensHelper(lendingPoolProxyAddress, address(lendingPoolAddressesProvider));
//         aTokensAndRatesHelper =
//         new ATokensAndRatesHelper(payable(lendingPoolProxyAddress), address(lendingPoolAddressesProvider), lendingPoolConfiguratorProxyAddress);

//         aToken = new AToken();
//         variableDebtToken = new VariableDebtToken();
//         // stableDebtToken = new StableDebtToken();
//         oracle = new Oracle(tokens, aggregators, FALLBACK_ORACLE, BASE_CURRENCY, BASE_CURRENCY_UNIT);
//         lendingPoolAddressesProvider.setPriceOracle(address(oracle));
//         protocolDataProvider = new ProtocolDataProvider(lendingPoolAddressesProvider);
//         //@todo uiPoolDataProviderV2 = new UiPoolDataProviderV2(IChainlinkAggregator(ethPriceFeed), IChainlinkAggregator(ethPriceFeed));
//         wETHGateway = new WETHGateway(address(weth));
//         stableStrategy = new DefaultReserveInterestRateStrategy(
//             lendingPoolAddressesProvider,
//             sStrat[0],
//             sStrat[1],
//             sStrat[2],
//             sStrat[3]
//         );
//         volatileStrategy = new DefaultReserveInterestRateStrategy(
//             lendingPoolAddressesProvider,
//             volStrat[0],
//             volStrat[1],
//             volStrat[2],
//             volStrat[3]
//         );

//         initInputParams.push(
//             ILendingPoolConfigurator.InitReserveInput({
//                 aTokenImpl: address(aToken),
//                 variableDebtTokenImpl: address(variableDebtToken),
//                 underlyingAssetDecimals: 6,
//                 interestRateStrategyAddress: address(stableStrategy),
//                 underlyingAsset: tokens[0],
//                 reserveType: reserveTypes[0],
//                 treasury: address(treasury),
//                 incentivesController: address(rewarder),
//                 underlyingAssetName: "USDC",
//                 aTokenName: "Granary USDC",
//                 aTokenSymbol: "grainUSDC",
//                 variableDebtTokenName: "Granary variable debt bearing USDC",
//                 variableDebtTokenSymbol: "variableDebtUSDC",
//                 params: "0x10"
//             })
//         );
//         initInputParams.push(
//             ILendingPoolConfigurator.InitReserveInput({
//                 aTokenImpl: address(aToken),
//                 variableDebtTokenImpl: address(variableDebtToken),
//                 underlyingAssetDecimals: 8,
//                 interestRateStrategyAddress: address(volatileStrategy),
//                 underlyingAsset: tokens[1],
//                 reserveType: reserveTypes[1],
//                 treasury: address(treasury),
//                 incentivesController: address(rewarder),
//                 underlyingAssetName: "WBTC",
//                 aTokenName: "Granary WBTC",
//                 aTokenSymbol: "grainWBTC",
//                 variableDebtTokenName: "Granary variable debt bearing WBTC",
//                 variableDebtTokenSymbol: "variableDebtWBTC",
//                 params: "0x10"
//             })
//         );
//         initInputParams.push(
//             ILendingPoolConfigurator.InitReserveInput({
//                 aTokenImpl: address(aToken),
//                 variableDebtTokenImpl: address(variableDebtToken),
//                 underlyingAssetDecimals: 18,
//                 interestRateStrategyAddress: address(volatileStrategy),
//                 underlyingAsset: tokens[2],
//                 reserveType: reserveTypes[2],
//                 treasury: address(treasury),
//                 incentivesController: address(rewarder),
//                 underlyingAssetName: "ETH",
//                 aTokenName: "Granary ETH",
//                 aTokenSymbol: "grainETH",
//                 variableDebtTokenName: "Granary variable debt bearing ETH",
//                 variableDebtTokenSymbol: "variableDebtETH",
//                 params: "0x10"
//             })
//         );
//         vm.prank(admin);
//         lendingPoolConfiguratorProxy.batchInitReserve(initInputParams);

//         inputConfigParams.push(
//             ATokensAndRatesHelper.ConfigureReserveInput({
//                 asset: tokens[0],
//                 reserveType: reserveTypes[0],
//                 baseLTV: 8000,
//                 liquidationThreshold: 8500,
//                 liquidationBonus: 10500,
//                 reserveFactor: 1500,
//                 borrowingEnabled: true
//             })
//         );

//         inputConfigParams.push(
//             ATokensAndRatesHelper.ConfigureReserveInput({
//                 asset: tokens[1],
//                 reserveType: reserveTypes[1],
//                 baseLTV: 8000,
//                 liquidationThreshold: 8500,
//                 liquidationBonus: 10500,
//                 reserveFactor: 1500,
//                 borrowingEnabled: true
//             })
//         );

//         inputConfigParams.push(
//             ATokensAndRatesHelper.ConfigureReserveInput({
//                 asset: tokens[2],
//                 reserveType: reserveTypes[2],
//                 baseLTV: 8000,
//                 liquidationThreshold: 8500,
//                 liquidationBonus: 10500,
//                 reserveFactor: 1500,
//                 borrowingEnabled: true
//             })
//         );

//         lendingPoolAddressesProvider.setPoolAdmin(address(aTokensAndRatesHelper));
//         aTokensAndRatesHelper.configureReserves(inputConfigParams);
//         lendingPoolAddressesProvider.setPoolAdmin(admin);

//         lendingPoolCollateralManager = new LendingPoolCollateralManager();
//         lendingPoolAddressesProvider.setLendingPoolCollateralManager(address(lendingPoolCollateralManager));
//         wETHGateway.authorizeLendingPool(lendingPoolProxyAddress);

//         (address USDCATokenAddress, address USDCVariableDebtToken) =
//             protocolDataProvider.getReserveTokensAddresses(address(usdc), false);
//         grainUSDC = AToken(USDCATokenAddress);
//         variableDebtUSDC = VariableDebtToken(USDCVariableDebtToken);

//         (address WBTCATokenAddress, address WBTCVariableDebtTokenAddress) =
//             protocolDataProvider.getReserveTokensAddresses(address(wbtc), false);
//         grainWBTC = AToken(WBTCATokenAddress);
//         variableDebtWBTC = VariableDebtToken(WBTCVariableDebtTokenAddress);

//         (address ETHATokenAddress, address ETHVariableDebtTokenAddress) =
//             protocolDataProvider.getReserveTokensAddresses(address(weth), false);
//         grainETH = AToken(ETHATokenAddress);
//         variableDebtETH = VariableDebtToken(ETHVariableDebtTokenAddress);

//         vm.prank(admin);
//         lendingPoolConfiguratorProxy.setPoolPause(false);
//     }

//     function testRebalance() public {
//         address gibbons = makeAddr("gibbons");
//         uint256 usdcDepositSize = 100 * 1e6;
//         deal(address(usdc), gibbons, usdcDepositSize);
//         vm.prank(gibbons);
//         usdc.approve(lendingPoolProxyAddress, type(uint256).max);
//         vm.prank(gibbons);
//         lendingPoolProxy.deposit(address(usdc), false, usdcDepositSize, gibbons);
//         MockERC4626 usdcMockERC4626 = MockERC4626(deployMockErc4626(address(usdc)));
//         vm.startPrank(admin);
//         lendingPoolConfiguratorProxy.setVault(address(grainUSDC), address(usdcMockERC4626));
//         lendingPoolConfiguratorProxy.setFarmingPct(address(grainUSDC), 2000);
//         lendingPoolConfiguratorProxy.setClaimingThreshold(address(grainUSDC), 1e6);
//         lendingPoolConfiguratorProxy.setFarmingPctDrift(address(grainUSDC), 200);
//         lendingPoolConfiguratorProxy.setProfitHandler(address(grainUSDC), admin);
//         vm.stopPrank();

//         assertEq(usdc.balanceOf(address(grainUSDC)), usdcDepositSize);

//         vm.startPrank(admin);
//         lendingPoolConfiguratorProxy.setPoolPause(true);
//         lendingPoolConfiguratorProxy.rebalance(address(grainUSDC));
//         vm.stopPrank();

//         uint256 remainingPct = 10000 - (grainUSDC.farmingPct());
//         assertEq(usdc.balanceOf(address(grainUSDC)), usdcDepositSize * remainingPct / 10000);
//         assertEq(grainUSDC.getTotalManagedAssets(), usdcDepositSize);
//     }

//     function testDepositAndWithdrawYield() public {
//         address yankovic = makeAddr("yankovic");
//         uint256 usdcDepositSize = 100 * 1e6;
//         vm.label(address(usdc), "usdc");
//         deal(address(usdc), yankovic, usdcDepositSize);
//         vm.startPrank(yankovic);
//         usdc.approve(lendingPoolProxyAddress, type(uint256).max);
//         lendingPoolProxy.deposit(address(usdc), false, usdcDepositSize, yankovic);
//         vm.stopPrank();
//         vm.startPrank(admin);
//         MockERC4626 usdcMockERC4626 = MockERC4626(deployMockErc4626(address(usdc)));
//         vm.label(address(usdcMockERC4626), "usdcMockERC4626");
//         ExternalContract externalContract = new ExternalContract(address(usdc));
//         ReaperStrategy usdcReaperStrategy =
//             new ReaperStrategy(address(usdcMockERC4626), address(usdc), address(externalContract));
//         vm.label(address(usdcReaperStrategy), "strategy");
//         lendingPoolConfiguratorProxy.setVault(address(grainUSDC), address(usdcMockERC4626));
//         lendingPoolConfiguratorProxy.setFarmingPct(address(grainUSDC), 2000);
//         lendingPoolConfiguratorProxy.setClaimingThreshold(address(grainUSDC), 1e6);
//         lendingPoolConfiguratorProxy.setFarmingPctDrift(address(grainUSDC), 200);
//         lendingPoolConfiguratorProxy.setProfitHandler(address(grainUSDC), admin);
//         vm.stopPrank();
//         // Starting here, vault should be able to handle asset
//         assertEq(usdc.balanceOf(address(grainUSDC)), usdcDepositSize);

//         uint256 remainingPct = 10000 - (grainUSDC.farmingPct());
//         vm.prank(admin);
//         lendingPoolConfiguratorProxy.rebalance(address(grainUSDC));
//         assertEq(usdc.balanceOf(address(grainUSDC)), usdcDepositSize * remainingPct / 10000);

//         // Artificially increasing balance of vault should result in yield for the graintoken
//         deal(address(usdc), address(usdcReaperStrategy), usdcDepositSize / 2);
//         console.log(usdcDepositSize);
//         console.log(usdc.balanceOf(address(usdcReaperStrategy)));
//         vm.prank(admin);
//         lendingPoolConfiguratorProxy.rebalance(address(grainUSDC));
//     }

//     function deployMockErc4626(address token) public returns (address mockERC4626) {
//         uint8 decimals = ERC20(token).decimals();
//         mockERC4626 = address(new MockERC4626(token,'Mock ERC4626', 'mock', 1e27, address(treasury)));
//     }
// }
