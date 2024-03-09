// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/rewarder/Rewarder.sol";
import "contracts/misc/Oracle.sol";
import "contracts/misc/ProtocolDataProvider.sol";
import "contracts/misc/Treasury.sol";
import "contracts/misc/UiPoolDataProviderV2.sol";
import "contracts/misc/WETHGateway.sol";
import "contracts/protocol/libraries/logic/ReserveLogic.sol";
import "contracts/protocol/libraries/logic/GenericLogic.sol";
import "contracts/protocol/libraries/logic/ValidationLogic.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProviderRegistry.sol";
import "contracts/protocol/lendingpool/DefaultReserveInterestRateStrategy.sol";
import "contracts/protocol/lendingpool/LendingPool.sol";
import "contracts/protocol/lendingpool/LendingPoolCollateralManager.sol";
import "contracts/protocol/lendingpool/LendingPoolConfigurator.sol";
import "contracts/protocol/lendingpool/minipool/MiniPool.sol";
import "contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import "contracts/protocol/lendingpool/minipool/MiniPoolConfigurator.sol";
import "contracts/protocol/lendingpool/minipool/FlowLimiter.sol";

import "contracts/deployments/ATokensAndRatesHelper.sol";
import "contracts/protocol/tokenization/AToken.sol";
import "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import "contracts/protocol/tokenization/VariableDebtToken.sol";
import "contracts/mocks/tokens/MintableERC20.sol";
import "contracts/mocks/tokens/WETH9Mocked.sol";
import "contracts/mocks/oracle/CLAggregators/MockAggregator.sol";
import "contracts/mocks/tokens/MockVault.sol";
import "contracts/mocks/tokens/MockStrat.sol";
import "contracts/mocks/tokens/ExternalContract.sol";
import "contracts/mocks/dependencies/IStrategy.sol";
import "contracts/mocks/dependencies/IExternalContract.sol";

contract Common is Test {
    // Structures
    struct ConfigAddresses {
        address stableStrategy;
        address volatileStrategy;
        address treasury;
        address rewarder;
        address aTokensAndRatesHelper;
    }

    struct DeployedContracts {
        LendingPoolAddressesProviderRegistry lendingPoolAddressesProviderRegistry;
        Rewarder rewarder;
        LendingPoolAddressesProvider lendingPoolAddressesProvider;
        LendingPool lendingPool;
        Treasury treasury;
        LendingPoolConfigurator lendingPoolConfigurator;
        DefaultReserveInterestRateStrategy stableStrategy;
        DefaultReserveInterestRateStrategy volatileStrategy;
        ProtocolDataProvider protocolDataProvider;
        ATokensAndRatesHelper aTokensAndRatesHelper;
    }

    struct DeployedMiniPoolContracts {
        MiniPool miniPoolImpl;
        MiniPoolAddressesProvider miniPoolAddressesProvider;
        MiniPoolConfigurator miniPoolConfigurator;
        ATokenERC6909 AToken6909Impl;
        flowLimiter flowLimiter;
    }

    // Fork Identifier
    string RPC = vm.envString("RPC_PROVIDER");
    uint256 constant FORK_BLOCK = 116753757;
    uint256 public opFork;

    // Constants
    address constant ZERO_ADDRESS = address(0);
    address constant BASE_CURRENCY = address(0);
    uint256 constant BASE_CURRENCY_UNIT = 100000000;
    address constant FALLBACK_ORACLE = address(0);
    uint256 constant TVL_CAP = 1e20;
    uint256 constant PERCENTAGE_FACTOR = 10_000;
    uint8 constant PRICE_FEED_DECIMALS = 8;

    // Tokens addresses
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant WBTC = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant USDC_WHALE = 0x383BB83D698733b021dD4d943c12BB12217f9AB8;
    address constant WBTC_WHALE = 0x99b7AE9ff695C0430D63460C69b141F7703349e7;
    address constant WETH_WHALE = 0x240F670a93e7DAC470d22722Aba5f7ff8915c5f2;
    address constant DAI_WHALE = 0x1eED63EfBA5f81D95bfe37d82C8E736b974F477b;

    address[] tokens = [USDC, WBTC, WETH, DAI];
    address[] tokensWhales = [USDC_WHALE, WBTC_WHALE, WETH_WHALE, DAI_WHALE];

    address admin = 0xe027880CEB8114F2e367211dF977899d00e66138;
    uint256[] rates = [0.039e27, 0.03e27, 0.03e27]; //usdc, wbtc, eth
    uint256[] volStrat = [0.45e27, 0e27, 0.07e27, 3e27, 0, 0]; // optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2
    uint256[] sStrat = [0.8e27, 0e27, 0.04e27, 0.75e27, 0, 0]; // optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2

    // Protocol deployment variables
    uint256 providerId = 1;
    string marketId = "Granary Genesis Market";

    ERC20 public weth = ERC20(WETH);

    bool[] reserveTypes = [false, false, false];

    // MockAggregator public usdcPriceFeed;
    // MockAggregator public wbtcPriceFeed;
    // MockAggregator public ethPriceFeed;
    address[] public aggregators;

    address public reserveLogic;
    address public genericLogic;
    address public validationLogic;

    // StableAndVariableTokensHelper public stableAndVariableTokensHelper;
    AToken public aToken;
    ATokenERC6909 public aTokenErc6909;
    VariableDebtToken public variableDebtToken;
    Oracle public oracle;

    UiPoolDataProviderV2 public uiPoolDataProviderV2;
    WETHGateway public wETHGateway;

    LendingPoolCollateralManager public lendingPoolCollateralManager;
    AToken[] public grainTokens;
    VariableDebtToken[] public variableDebtTokens;

    MockERC4626[] public mockedVaults;

    function fixture_deployProtocol() public returns (DeployedContracts memory) {
        DeployedContracts memory deployedContracts;

        LendingPool lendingPool;
        address lendingPoolProxyAddress;
        // LendingPool lendingPoolProxy;
        // Treasury treasury;
        LendingPoolConfigurator lendingPoolConfigurator;
        address lendingPoolConfiguratorProxyAddress;
        // LendingPoolConfigurator lendingPoolConfiguratorProxy;
        // bytes memory args = abi.encode();
        // bytes memory bytecode = abi.encodePacked(vm.getCode("contracts/incentives/Rewarder.sol:Rewarder"));
        // address anotherAddress;
        // assembly {
        //     anotherAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        // }
        deployedContracts.rewarder = new Rewarder();
        deployedContracts.lendingPoolAddressesProviderRegistry = new LendingPoolAddressesProviderRegistry();
        deployedContracts.lendingPoolAddressesProvider = new LendingPoolAddressesProvider(marketId);
        deployedContracts.lendingPoolAddressesProviderRegistry.registerAddressesProvider(
            address(deployedContracts.lendingPoolAddressesProvider), providerId
        );
        deployedContracts.lendingPoolAddressesProvider.setPoolAdmin(admin);
        deployedContracts.lendingPoolAddressesProvider.setEmergencyAdmin(admin);

        // reserveLogic = address(new ReserveLogic());
        // genericLogic = address(new GenericLogic());
        // validationLogic = address(new ValidationLogic());
        lendingPool = new LendingPool();
        lendingPool.initialize(ILendingPoolAddressesProvider(deployedContracts.lendingPoolAddressesProvider));
        deployedContracts.lendingPoolAddressesProvider.setLendingPoolImpl(address(lendingPool));
        lendingPoolProxyAddress = address(deployedContracts.lendingPoolAddressesProvider.getLendingPool());
        deployedContracts.lendingPool = LendingPool(lendingPoolProxyAddress);
        deployedContracts.treasury = new Treasury(deployedContracts.lendingPoolAddressesProvider);
        // granaryTreasury = new GranaryTreasury(ILendingPoolAddressesProvider(lendingPoolAddressesProvider));

        lendingPoolConfigurator = new LendingPoolConfigurator();
        deployedContracts.lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(address(lendingPoolConfigurator));
        lendingPoolConfiguratorProxyAddress =
            deployedContracts.lendingPoolAddressesProvider.getLendingPoolConfigurator();
        deployedContracts.lendingPoolConfigurator = LendingPoolConfigurator(lendingPoolConfiguratorProxyAddress);
        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.setPoolPause(true);

        // stableAndVariableTokensHelper = new StableAndVariableTokensHelper(lendingPoolProxyAddress, address(lendingPoolAddressesProvider));
        deployedContracts.aTokensAndRatesHelper =
        new ATokensAndRatesHelper(payable(lendingPoolProxyAddress), address(deployedContracts.lendingPoolAddressesProvider), lendingPoolConfiguratorProxyAddress);

        aToken = new AToken();
        variableDebtToken = new VariableDebtToken();
        // stableDebtToken = new StableDebtToken();
        fixture_deployMocks(address(deployedContracts.treasury));
        deployedContracts.lendingPoolAddressesProvider.setPriceOracle(address(oracle));
        deployedContracts.protocolDataProvider =
            new ProtocolDataProvider(deployedContracts.lendingPoolAddressesProvider);
        //@todo uiPoolDataProviderV2 = new UiPoolDataProviderV2(IChainlinkAggregator(ethPriceFeed), IChainlinkAggregator(ethPriceFeed));
        wETHGateway = new WETHGateway(address(weth));
        deployedContracts.stableStrategy = new DefaultReserveInterestRateStrategy(
            deployedContracts.lendingPoolAddressesProvider,
            sStrat[0],
            sStrat[1],
            sStrat[2],
            sStrat[3]
        );
        deployedContracts.volatileStrategy = new DefaultReserveInterestRateStrategy(
            deployedContracts.lendingPoolAddressesProvider,
            volStrat[0],
            volStrat[1],
            volStrat[2],
            volStrat[3]
        );

        return (deployedContracts);
    }

    function fixture_deployMocks(address _treasury) public {
        // MintableERC20 mintableUsdc = new MintableERC20("Test Usdc", "USDC", 6);
        // MintableERC20 mintableWbtc = new MintableERC20("Test Wbtc", "WBTC", 8);
        // WETH9Mocked mintableWeth = new WETH9Mocked();

        /* Prices to be changed here */
        ERC20[] memory erc20tokens = fixture_getErc20Tokens(tokens);
        int256[] memory prices = new int256[](4);
        // All chainlink price feeds have 8 decimals
        prices[0] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // USDC
        prices[1] = int256(67_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[2] = int256(3700 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[3] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // DAI
        mockedVaults = fixture_deployErc4626Mocks(tokens, _treasury);
        // usdcPriceFeed = new MockAggregator(100000000, int256(uint256(mintableUsdc.decimals())));
        // wbtcPriceFeed = new MockAggregator(1600000000000, int256(uint256(mintableWbtc.decimals())));
        // ethPriceFeed = new MockAggregator(120000000000, int256(uint256(mintableWeth.decimals())));
        (, aggregators) = fixture_getTokenPriceFeeds(erc20tokens, prices);

        oracle = new Oracle(tokens, aggregators, FALLBACK_ORACLE, BASE_CURRENCY, BASE_CURRENCY_UNIT);

        wETHGateway = new WETHGateway(address(weth));
        lendingPoolCollateralManager = new LendingPoolCollateralManager();
    }

    function fixture_configureProtocol(
        address ledingPool,
        ConfigAddresses memory configAddresses,
        LendingPoolConfigurator lendingPoolConfiguratorProxy,
        LendingPoolAddressesProvider lendingPoolAddressesProvider,
        ProtocolDataProvider protocolDataProvider
    ) public {
        fixture_configureReserves(configAddresses, lendingPoolConfiguratorProxy, lendingPoolAddressesProvider);

        lendingPoolAddressesProvider.setLendingPoolCollateralManager(address(lendingPoolCollateralManager));
        wETHGateway.authorizeLendingPool(ledingPool);

        vm.prank(admin);
        lendingPoolConfiguratorProxy.setPoolPause(false);

        // (grainTokens, variableDebtTokens) = fixture_getGrainTokensAndDebts(tokens, protocolDataProvider);
    }

    function fixture_configureReserves(
        ConfigAddresses memory configAddresses,
        LendingPoolConfigurator lendingPoolConfigurator,
        LendingPoolAddressesProvider lendingPoolAddressesProvider
    ) public {
        ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
            new ILendingPoolConfigurator.InitReserveInput[](3);
        ATokensAndRatesHelper.ConfigureReserveInput[] memory inputConfigParams =
            new ATokensAndRatesHelper.ConfigureReserveInput[](3);
        // make it more universal
        initInputParams[0] = (
            ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: address(aToken),
                variableDebtTokenImpl: address(variableDebtToken),
                underlyingAssetDecimals: 6,
                interestRateStrategyAddress: configAddresses.stableStrategy,
                underlyingAsset: tokens[0],
                reserveType: reserveTypes[0],
                treasury: configAddresses.treasury,
                incentivesController: configAddresses.rewarder,
                underlyingAssetName: "USDC",
                aTokenName: "Granary USDC",
                aTokenSymbol: "grainUSDC",
                variableDebtTokenName: "Granary variable debt bearing USDC",
                variableDebtTokenSymbol: "variableDebtUSDC",
                params: "0x10"
            })
        );
        initInputParams[1] = (
            ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: address(aToken),
                variableDebtTokenImpl: address(variableDebtToken),
                underlyingAssetDecimals: 8,
                interestRateStrategyAddress: configAddresses.volatileStrategy,
                underlyingAsset: tokens[1],
                reserveType: reserveTypes[1],
                treasury: configAddresses.treasury,
                incentivesController: configAddresses.rewarder,
                underlyingAssetName: "WBTC",
                aTokenName: "Granary WBTC",
                aTokenSymbol: "grainWBTC",
                variableDebtTokenName: "Granary variable debt bearing WBTC",
                variableDebtTokenSymbol: "variableDebtWBTC",
                params: "0x10"
            })
        );
        initInputParams[2] = (
            ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: address(aToken),
                variableDebtTokenImpl: address(variableDebtToken),
                underlyingAssetDecimals: 18,
                interestRateStrategyAddress: configAddresses.volatileStrategy,
                underlyingAsset: tokens[2],
                reserveType: reserveTypes[2],
                treasury: configAddresses.treasury,
                incentivesController: configAddresses.rewarder,
                underlyingAssetName: "ETH",
                aTokenName: "Granary ETH",
                aTokenSymbol: "grainETH",
                variableDebtTokenName: "Granary variable debt bearing ETH",
                variableDebtTokenSymbol: "variableDebtETH",
                params: "0x10"
            })
        );
        vm.prank(admin);
        lendingPoolConfigurator.batchInitReserve(initInputParams);

        // USDC
        inputConfigParams[0] = (
            ATokensAndRatesHelper.ConfigureReserveInput({
                asset: tokens[0],
                reserveType: reserveTypes[0],
                baseLTV: 8000,
                liquidationThreshold: 8500,
                liquidationBonus: 10500,
                reserveFactor: 1500,
                borrowingEnabled: true
            })
        );
        // WBTC
        inputConfigParams[1] = (
            ATokensAndRatesHelper.ConfigureReserveInput({
                asset: tokens[1],
                reserveType: reserveTypes[1],
                baseLTV: 8000,
                liquidationThreshold: 8500,
                liquidationBonus: 10500,
                reserveFactor: 1500,
                borrowingEnabled: true
            })
        );
        // WETH
        inputConfigParams[2] = (
            ATokensAndRatesHelper.ConfigureReserveInput({
                asset: tokens[2],
                reserveType: reserveTypes[2],
                baseLTV: 8000,
                liquidationThreshold: 8500,
                liquidationBonus: 10500,
                reserveFactor: 1500,
                borrowingEnabled: true
            })
        );
        lendingPoolAddressesProvider.setPoolAdmin(configAddresses.aTokensAndRatesHelper);
        ATokensAndRatesHelper(configAddresses.aTokensAndRatesHelper).configureReserves(inputConfigParams);
        lendingPoolAddressesProvider.setPoolAdmin(admin);
    }

    function fixture_getGrainTokensAndDebts(address[] memory _tokens, ProtocolDataProvider protocolDataProvider)
        public
        view
        returns (AToken[] memory _grainTokens, VariableDebtToken[] memory _varDebtTokens)
    {
        _grainTokens = new AToken[](_tokens.length);
        _varDebtTokens = new VariableDebtToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            console.log("Index: ", idx);
            (address _aTokenAddress, address _variableDebtToken) =
                protocolDataProvider.getReserveTokensAddresses(_tokens[idx], false);
            console.log("Atoken address", _aTokenAddress);
            _grainTokens[idx] = AToken(_aTokenAddress);
            _varDebtTokens[idx] = VariableDebtToken(_variableDebtToken);
        }
    }

    function fixture_getGrainTokensErc6909AndDebts(address[] memory _tokens, ProtocolDataProvider protocolDataProvider)
        public
        view
        returns (ATokenERC6909[] memory _grainTokens, VariableDebtToken[] memory _varDebtTokens)
    {
        _grainTokens = new ATokenERC6909[](_tokens.length);
        _varDebtTokens = new VariableDebtToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            console.log("Index: ", idx);
            (address _aTokenAddress, address _variableDebtToken) =
                protocolDataProvider.getReserveTokensAddresses(_tokens[idx], false);
            console.log("Atoken address", _aTokenAddress);
            _grainTokens[idx] = ATokenERC6909(_aTokenAddress);
            _varDebtTokens[idx] = VariableDebtToken(_variableDebtToken);
        }
    }

    function fixture_getErc20Tokens(address[] memory _tokens) public pure returns (ERC20[] memory erc20Tokens) {
        erc20Tokens = new ERC20[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            erc20Tokens[idx] = ERC20(_tokens[idx]);
        }
    }

    function fixture_getTokenPriceFeeds(ERC20[] memory _tokens, int256[] memory _prices)
        public
        returns (MockAggregator[] memory _priceFeedMocks, address[] memory _aggregators)
    {
        require(_tokens.length == _prices.length, "Length of params shall be equal");

        _priceFeedMocks = new MockAggregator[](_tokens.length);
        _aggregators = new address[](_tokens.length);
        for (uint32 idx; idx < _tokens.length; idx++) {
            _priceFeedMocks[idx] = new MockAggregator(_prices[idx], int256(uint256(_tokens[idx].decimals())));
            _aggregators[idx] = address(_priceFeedMocks[idx]);
        }
    }

    function fixture_deployErc4626Mocks(address[] memory _tokens, address _treasury)
        public
        returns (MockERC4626[] memory)
    {
        MockERC4626[] memory _mockedVaults = new MockERC4626[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            _mockedVaults[idx] = new MockERC4626(_tokens[idx], 'Mock ERC4626', 'mock', TVL_CAP, _treasury);
        }
        return _mockedVaults;
    }

    function fixture_transferTokensToTestContract(
        ERC20[] memory _tokens,
        address[] memory _tokensWhales,
        address _testContractAddress
    ) public {
        require(_tokens.length == _tokensWhales.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            uint256 _balance = _tokens[idx].balanceOf(_tokensWhales[idx]);
            console.log("Whale balance: ", _balance);
            vm.prank(_tokensWhales[idx]);
            _tokens[idx].transfer(_testContractAddress, _balance);
        }
    }

    function fixture_calcMaxAmountToBorrowBasedOnCollateral(
        uint256 collateralMaxBorrowValue,
        uint256 borrowTokenPrice,
        uint256 collateralDecimals,
        uint256 borrowTokenDecimals
    ) public pure returns (uint256 borrowTokenMaxAmount) {
        uint256 borrowTokenMaxBorrowAmountRaw =
            (collateralMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / borrowTokenPrice;
        borrowTokenMaxAmount = (borrowTokenDecimals > collateralDecimals)
            ? borrowTokenMaxBorrowAmountRaw * (10 ** (borrowTokenDecimals - collateralDecimals))
            : borrowTokenMaxBorrowAmountRaw / (10 ** (collateralDecimals - borrowTokenDecimals));
        return borrowTokenMaxAmount;
    }

    function fixture_deployMiniPoolSetup(
        address _lendingPoolAddressesProvider,
        address _lendingPool
    ) public returns (DeployedMiniPoolContracts memory) {
        DeployedMiniPoolContracts memory deployedMiniPoolContracts;
        deployedMiniPoolContracts.miniPoolImpl = new MiniPool();
        deployedMiniPoolContracts.miniPoolAddressesProvider = new MiniPoolAddressesProvider(ILendingPoolAddressesProvider(_lendingPoolAddressesProvider));
        deployedMiniPoolContracts.AToken6909Impl = new ATokenERC6909();
        deployedMiniPoolContracts.flowLimiter = new flowLimiter(
            ILendingPoolAddressesProvider(_lendingPoolAddressesProvider), 
            IMiniPoolAddressesProvider(address(deployedMiniPoolContracts.miniPoolAddressesProvider)), 
            ILendingPool(_lendingPool));
        address miniPoolConfigIMPL = address(new MiniPoolConfigurator());
        deployedMiniPoolContracts.miniPoolAddressesProvider.
            setMiniPoolConfigurator(miniPoolConfigIMPL);
        deployedMiniPoolContracts.miniPoolConfigurator = MiniPoolConfigurator(deployedMiniPoolContracts.miniPoolAddressesProvider.
            getMiniPoolConfigurator());

        deployedMiniPoolContracts.miniPoolAddressesProvider
            .setMiniPoolImpl(address(deployedMiniPoolContracts.miniPoolImpl));
        deployedMiniPoolContracts.miniPoolAddressesProvider
            .setAToken6909Impl(address(deployedMiniPoolContracts.AToken6909Impl));

        ILendingPoolAddressesProvider(_lendingPoolAddressesProvider).setMiniPoolAddressesProvider(address(deployedMiniPoolContracts.miniPoolAddressesProvider));
        ILendingPoolAddressesProvider(_lendingPoolAddressesProvider).setFlowLimiter(address(deployedMiniPoolContracts.flowLimiter));
        return deployedMiniPoolContracts;
    }

    


}
