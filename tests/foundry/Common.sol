// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/protocol/rewarder/lendingpool/Rewarder.sol";
import "contracts/protocol/core/Oracle.sol";
import "contracts/misc/ProtocolDataProvider.sol";
import "contracts/misc/Cod3xLendDataProvider.sol";
import "contracts/misc/Treasury.sol";
// import "contracts/misc/UiPoolDataProviderV2.sol";
import "contracts/misc/WETHGateway.sol";
import "contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
import "contracts/protocol/core/lendingpool/logic/GenericLogic.sol";
import "contracts/protocol/core/lendingpool/logic/ValidationLogic.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import
    "contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import
    "contracts/protocol/core/interestRateStrategies/lendingpool/PiReserveInterestRateStrategy.sol";
import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolPiReserveInterestRateStrategy.sol";
import "contracts/protocol/core/lendingpool/LendingPool.sol";
import "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import "contracts/protocol/core/minipool/MiniPool.sol";
import "contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import "contracts/protocol/core/minipool/FlowLimiter.sol";

import "contracts/deployments/ATokensAndRatesHelper.sol";
import "contracts/protocol/tokenization/ERC20/AToken.sol";
import "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import "contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import "contracts/mocks/tokens/MintableERC20.sol";
import "contracts/mocks/tokens/WETH9Mocked.sol";
import "contracts/mocks/oracle/MockAggregator.sol";
import "contracts/mocks/tokens/MockVault.sol";
import "contracts/mocks/tokens/ExternalContract.sol";
import "contracts/mocks/dependencies/IStrategy.sol";
import "contracts/mocks/dependencies/IExternalContract.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import "contracts/mocks/oracle/PriceOracle.sol";
import "contracts/mocks/tokens/MockVaultUnit.sol";

struct ReserveDataParams {
    uint256 availableLiquidity;
    uint256 totalVariableDebt;
    uint256 liquidityRate;
    uint256 variableBorrowRate;
    uint256 liquidityIndex;
    uint256 variableBorrowIndex;
    uint40 lastUpdateTimestamp;
}

struct TokenTypes {
    ERC20 token;
    AToken aToken;
    VariableDebtToken debtToken;
}

event Deposit(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount);

event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount);

event Borrow(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount,
    uint256 borrowRate
);

event Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount);

contract Common is Test {
    using WadRayMath for uint256;

    // Structures
    struct ConfigAddresses {
        address cod3xLendDataProvider;
        address stableStrategy;
        address volatileStrategy;
        address treasury;
        address rewarder;
        address aTokensAndRatesHelper;
    }

    struct PidConfig {
        address asset;
        bool assetReserveType;
        int256 minControllerError;
        int256 maxITimeAmp;
        uint256 optimalUtilizationRate;
        uint256 kp;
        uint256 ki;
    }

    struct DeployedContracts {
        Rewarder rewarder;
        LendingPoolAddressesProvider lendingPoolAddressesProvider;
        LendingPool lendingPool;
        Treasury treasury;
        LendingPoolConfigurator lendingPoolConfigurator;
        DefaultReserveInterestRateStrategy stableStrategy;
        DefaultReserveInterestRateStrategy volatileStrategy;
        PiReserveInterestRateStrategy piStrategy;
        Cod3xLendDataProvider cod3xLendDataProvider;
        ATokensAndRatesHelper aTokensAndRatesHelper;
    }

    struct DeployedMiniPoolContracts {
        MiniPool miniPoolImpl;
        MiniPoolAddressesProvider miniPoolAddressesProvider;
        MiniPoolConfigurator miniPoolConfigurator;
        MiniPoolDefaultReserveInterestRateStrategy stableStrategy;
        MiniPoolDefaultReserveInterestRateStrategy volatileStrategy;
        MiniPoolPiReserveInterestRateStrategy piStrategy;
        ATokenERC6909 aToken6909Impl;
        FlowLimiter flowLimiter;
    }

    struct TokenParams {
        ERC20 token;
        AToken aToken;
        uint256 price;
    }

    struct Users {
        address user1;
        address user2;
        address user3;
        address user4;
        address user5;
        address user6;
        address user7;
        address user8;
        address user9;
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
    uint8 constant RAY_DECIMALS = 27;

    // Tokens addresses
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant WBTC = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant USDC_WHALE = 0x383BB83D698733b021dD4d943c12BB12217f9AB8;
    address constant WBTC_WHALE = 0x99b7AE9ff695C0430D63460C69b141F7703349e7;
    address constant WETH_WHALE = 0x240F670a93e7DAC470d22722Aba5f7ff8915c5f2;
    address constant DAI_WHALE = 0x1eED63EfBA5f81D95bfe37d82C8E736b974F477b;

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

    address[] tokens = [USDC, WBTC, WETH, DAI];
    address[] tokensWhales = [USDC_WHALE, WBTC_WHALE, WETH_WHALE, DAI_WHALE];

    address admin = 0xe027880CEB8114F2e367211dF977899d00e66138;
    uint256[] rates = [0.039e27, 0.03e27, 0.03e27]; //usdc, wbtc, eth
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
    ]; // optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2
    bool[] isStableStrategy = [true, false, false, true];
    bool[] reserveTypes = [true, true, true, true];
    // Protocol deployment variables
    uint256 providerId = 1;
    string marketId = "Cod3x Lend Genesis Market";
    uint256 cntr;

    ERC20 public weth = ERC20(WETH);
    ERC20 public dai = ERC20(DAI);

    address[] public aggregators;

    address public reserveLogic;
    address public genericLogic;
    address public validationLogic;

    Oracle public oracle;

    WETHGateway public wETHGateway;
    AToken public aToken;
    VariableDebtToken public variableDebtToken;
    ATokenERC6909 public aTokenErc6909;

    AToken[] public aTokens;
    AToken[] public aTokensWrapper;
    VariableDebtToken[] public variableDebtTokens;
    ATokenERC6909[] public aTokensErc6909;

    MockReaperVault2[] public mockedVaults;
    MockVaultUnit[] public mockVaultUnits;
    PidConfig public defaultPidConfig = PidConfig({
        asset: DAI,
        assetReserveType: true,
        minControllerError: -400e24,
        maxITimeAmp: 20 days,
        optimalUtilizationRate: 45e25,
        kp: 1e27,
        ki: 13e19
    });

    function uintToString(uint256 value) public pure returns (string memory) {
        // Special case for 0
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;

        // Calculate the number of digits
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        // Fill the buffer with the digits in reverse order
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

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

        deployedContracts.lendingPoolAddressesProvider = new LendingPoolAddressesProvider();

        deployedContracts.lendingPoolAddressesProvider.setPoolAdmin(admin);
        deployedContracts.lendingPoolAddressesProvider.setEmergencyAdmin(admin);

        // reserveLogic = address(new ReserveLogic());
        // genericLogic = address(new GenericLogic());
        // validationLogic = address(new ValidationLogic());
        lendingPool = new LendingPool();
        lendingPool.initialize(
            ILendingPoolAddressesProvider(deployedContracts.lendingPoolAddressesProvider)
        );
        deployedContracts.lendingPoolAddressesProvider.setLendingPoolImpl(address(lendingPool));
        lendingPoolProxyAddress =
            address(deployedContracts.lendingPoolAddressesProvider.getLendingPool());
        deployedContracts.lendingPool = LendingPool(lendingPoolProxyAddress);
        deployedContracts.treasury = new Treasury(deployedContracts.lendingPoolAddressesProvider);
        // granaryTreasury = new GranaryTreasury(ILendingPoolAddressesProvider(lendingPoolAddressesProvider));

        lendingPoolConfigurator = new LendingPoolConfigurator();
        deployedContracts.lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(
            address(lendingPoolConfigurator)
        );
        lendingPoolConfiguratorProxyAddress =
            deployedContracts.lendingPoolAddressesProvider.getLendingPoolConfigurator();
        deployedContracts.lendingPoolConfigurator =
            LendingPoolConfigurator(lendingPoolConfiguratorProxyAddress);
        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.setPoolPause(true);

        // stableAndVariableTokensHelper = new StableAndVariableTokensHelper(lendingPoolProxyAddress, address(lendingPoolAddressesProvider));
        deployedContracts.aTokensAndRatesHelper = new ATokensAndRatesHelper(
            payable(lendingPoolProxyAddress),
            address(deployedContracts.lendingPoolAddressesProvider),
            lendingPoolConfiguratorProxyAddress
        );

        aToken = new AToken();
        aTokenErc6909 = new ATokenERC6909();
        variableDebtToken = new VariableDebtToken();
        // stableDebtToken = new StableDebtToken();
        fixture_deployMocks(address(deployedContracts.treasury));
        deployedContracts.lendingPoolAddressesProvider.setPriceOracle(address(oracle));
        vm.label(address(oracle), "Oracle");
        deployedContracts.cod3xLendDataProvider = new Cod3xLendDataProvider();
        deployedContracts.cod3xLendDataProvider.setLendingPoolAddressProvider(
            address(deployedContracts.lendingPoolAddressesProvider)
        );
        wETHGateway = new WETHGateway(WETH);
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
        deployedContracts.piStrategy = new PiReserveInterestRateStrategy(
            address(deployedContracts.lendingPoolAddressesProvider),
            defaultPidConfig.asset,
            defaultPidConfig.assetReserveType,
            defaultPidConfig.minControllerError,
            defaultPidConfig.maxITimeAmp,
            defaultPidConfig.optimalUtilizationRate,
            defaultPidConfig.kp,
            defaultPidConfig.ki
        );

        return (deployedContracts);
    }

    function fixture_deployMocks(address _treasury) public {
        /* Prices to be changed here */
        ERC20[] memory erc20tokens = fixture_getErc20Tokens(tokens);
        int256[] memory prices = new int256[](4);
        uint256[] memory timeouts = new uint256[](4);
        /* All chainlink price feeds have 8 decimals */
        prices[0] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // USDC
        prices[1] = int256(67_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[2] = int256(3700 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[3] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // DAI
        mockedVaults = fixture_deployReaperVaultMocks(tokens, _treasury);
        mockVaultUnits = fixture_deployVaultUnits(tokens);
        // usdcPriceFeed = new MockAggregator(100000000, int256(uint256(mintableUsdc.decimals())));
        // wbtcPriceFeed = new MockAggregator(1600000000000, int256(uint256(mintableWbtc.decimals())));
        // ethPriceFeed = new MockAggregator(120000000000, int256(uint256(mintableWeth.decimals())));
        (, aggregators, timeouts) = fixture_getTokenPriceFeeds(erc20tokens, prices);

        oracle = new Oracle(
            tokens, aggregators, timeouts, FALLBACK_ORACLE, BASE_CURRENCY, BASE_CURRENCY_UNIT
        );

        wETHGateway = new WETHGateway(WETH);
    }

    function fixture_configureProtocol(
        address ledingPool,
        address _aToken,
        ConfigAddresses memory configAddresses,
        LendingPoolConfigurator lendingPoolConfiguratorProxy,
        LendingPoolAddressesProvider lendingPoolAddressesProvider
    ) public {
        fixture_configureReserves(
            configAddresses, lendingPoolConfiguratorProxy, lendingPoolAddressesProvider, _aToken
        );
        wETHGateway.authorizeLendingPool(ledingPool);

        vm.prank(admin);
        lendingPoolConfiguratorProxy.setPoolPause(false);

        aTokens =
            fixture_getATokens(tokens, Cod3xLendDataProvider(configAddresses.cod3xLendDataProvider));
        aTokensWrapper = fixture_getATokensWrapper(
            tokens, Cod3xLendDataProvider(configAddresses.cod3xLendDataProvider)
        );
        variableDebtTokens = fixture_getVarDebtTokens(
            tokens, Cod3xLendDataProvider(configAddresses.cod3xLendDataProvider)
        );
        for (uint256 idx; idx < tokens.length; idx++) {
            vm.label(address(aTokens[idx]), string.concat("AToken ", uintToString(idx)));
            vm.label(
                address(variableDebtTokens[idx]),
                string.concat("VariableDebtToken ", uintToString(idx))
            );
        }
    }

    function fixture_configureReserves(
        ConfigAddresses memory configAddresses,
        LendingPoolConfigurator lendingPoolConfigurator,
        LendingPoolAddressesProvider lendingPoolAddressesProvider,
        address aTokenAddress
    ) public {
        ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
            new ILendingPoolConfigurator.InitReserveInput[](tokens.length);
        ATokensAndRatesHelper.ConfigureReserveInput[] memory inputConfigParams =
            new ATokensAndRatesHelper.ConfigureReserveInput[](tokens.length);

        for (uint8 idx = 0; idx < tokens.length; idx++) {
            string memory tmpSymbol = ERC20(tokens[idx]).symbol();
            address interestStrategy = isStableStrategy[idx] != false
                ? configAddresses.stableStrategy
                : configAddresses.volatileStrategy;
            // console.log("[common] main interestStartegy: ", interestStrategy);
            initInputParams[idx] = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: aTokenAddress,
                variableDebtTokenImpl: address(variableDebtToken),
                underlyingAssetDecimals: ERC20(tokens[idx]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: tokens[idx],
                reserveType: reserveTypes[idx],
                treasury: configAddresses.treasury,
                incentivesController: configAddresses.rewarder,
                underlyingAssetName: tmpSymbol,
                aTokenName: string.concat("Cod3x Lend ", tmpSymbol),
                aTokenSymbol: string.concat("cl", tmpSymbol),
                variableDebtTokenName: string.concat("Cod3x Lend variable debt bearing ", tmpSymbol),
                variableDebtTokenSymbol: string.concat("variableDebt", tmpSymbol),
                params: "0x10"
            });
        }

        vm.prank(admin);
        lendingPoolConfigurator.batchInitReserve(initInputParams);

        for (uint8 idx = 0; idx < tokens.length; idx++) {
            inputConfigParams[idx] = ATokensAndRatesHelper.ConfigureReserveInput({
                asset: tokens[idx],
                reserveType: reserveTypes[idx],
                baseLTV: 8000,
                liquidationThreshold: 8500,
                liquidationBonus: 10500,
                reserveFactor: 1500,
                borrowingEnabled: true
            });
        }
        lendingPoolAddressesProvider.setPoolAdmin(configAddresses.aTokensAndRatesHelper);
        ATokensAndRatesHelper(configAddresses.aTokensAndRatesHelper).configureReserves(
            inputConfigParams
        );
        lendingPoolAddressesProvider.setPoolAdmin(admin);
    }

    function fixture_getATokens(
        address[] memory _tokens,
        Cod3xLendDataProvider cod3xLendDataProvider
    ) public view returns (AToken[] memory _aTokens) {
        _aTokens = new AToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            (address _aTokenAddress,) = cod3xLendDataProvider.getLpTokens(_tokens[idx], true);
            // console.log("AToken%s: %s", idx, _aTokenAddress);
            _aTokens[idx] = AToken(_aTokenAddress);
        }
    }

    function fixture_getATokensWrapper(
        address[] memory _tokens,
        Cod3xLendDataProvider cod3xLendDataProvider
    ) public view returns (AToken[] memory _aTokensW) {
        _aTokensW = new AToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            (address _aTokenAddress,) = cod3xLendDataProvider.getLpTokens(_tokens[idx], true);
            // console.log("AToken%s: %s", idx, _aTokenAddress);
            _aTokensW[idx] = AToken(address(AToken(_aTokenAddress).WRAPPER_ADDRESS()));
        }
    }

    function fixture_getVarDebtTokens(
        address[] memory _tokens,
        Cod3xLendDataProvider cod3xLendDataProvider
    ) public returns (VariableDebtToken[] memory _varDebtTokens) {
        _varDebtTokens = new VariableDebtToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            (, address _variableDebtToken) = cod3xLendDataProvider.getLpTokens(_tokens[idx], true);
            // console.log("Atoken address", _variableDebtToken);
            string memory debtToken = string.concat("debtToken", uintToString(idx));
            vm.label(_variableDebtToken, debtToken);
            console.log("Debt token %s: %s", idx, _variableDebtToken);
            _varDebtTokens[idx] = VariableDebtToken(_variableDebtToken);
        }
    }

    function fixture_getErc20Tokens(address[] memory _tokens)
        public
        pure
        returns (ERC20[] memory erc20Tokens)
    {
        erc20Tokens = new ERC20[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            erc20Tokens[idx] = ERC20(_tokens[idx]);
        }
    }

    function fixture_getTokenPriceFeeds(ERC20[] memory _tokens, int256[] memory _prices)
        public
        returns (
            MockAggregator[] memory _priceFeedMocks,
            address[] memory _aggregators,
            uint256[] memory _timeouts
        )
    {
        require(_tokens.length == _prices.length, "Length of params shall be equal");

        _priceFeedMocks = new MockAggregator[](_tokens.length);
        _aggregators = new address[](_tokens.length);
        _timeouts = new uint256[](_tokens.length);
        for (uint32 idx; idx < _tokens.length; idx++) {
            _priceFeedMocks[idx] =
                new MockAggregator(_prices[idx], int256(uint256(_tokens[idx].decimals())));
            _aggregators[idx] = address(_priceFeedMocks[idx]);
            _timeouts[idx] = 0;
        }
    }

    function fixture_deployReaperVaultMocks(address[] memory _tokens, address _treasury)
        public
        returns (MockReaperVault2[] memory)
    {
        MockReaperVault2[] memory _mockedVaults = new MockReaperVault2[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            _mockedVaults[idx] =
                new MockReaperVault2(_tokens[idx], "Mock ERC4626", "mock", TVL_CAP, _treasury);
        }
        return _mockedVaults;
    }

    function fixture_deployVaultUnits(address[] memory _tokens)
        public
        returns (MockVaultUnit[] memory)
    {
        MockVaultUnit[] memory _mockedVaults = new MockVaultUnit[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            _mockedVaults[idx] = new MockVaultUnit(IERC20(_tokens[idx]));
        }
        return _mockedVaults;
    }

    function fixture_transferTokensToTestContract(
        ERC20[] memory _tokens,
        uint256 _toGiveInUsd,
        address _testContractAddress
    ) public {
        require(_tokens.length == tokensWhales.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            uint256 price = oracle.getAssetPrice(address(_tokens[idx]));
            console.log("_toGiveInUsd:", _toGiveInUsd);
            uint256 rawGive = (_toGiveInUsd / price) * 10 ** PRICE_FEED_DECIMALS;
            console.log("rawGive:", rawGive);
            console.log(
                "Distributed %s of %s",
                rawGive / (10 ** (18 - _tokens[idx].decimals())),
                _tokens[idx].symbol()
            );
            deal(
                address(_tokens[idx]),
                _testContractAddress,
                rawGive / (10 ** (18 - _tokens[idx].decimals()))
            );
            console.log(
                "Balance: %s %s",
                _tokens[idx].balanceOf(_testContractAddress),
                _tokens[idx].symbol()
            );
        }
    }

    function fixture_deployMiniPoolSetup(
        address _lendingPoolAddressesProvider,
        address _lendingPool
    ) public returns (DeployedMiniPoolContracts memory) {
        DeployedMiniPoolContracts memory deployedMiniPoolContracts;
        deployedMiniPoolContracts.miniPoolImpl = new MiniPool();
        deployedMiniPoolContracts.miniPoolAddressesProvider = new MiniPoolAddressesProvider(
            ILendingPoolAddressesProvider(_lendingPoolAddressesProvider)
        );
        deployedMiniPoolContracts.aToken6909Impl = new ATokenERC6909();
        deployedMiniPoolContracts.flowLimiter = new FlowLimiter(
            ILendingPoolAddressesProvider(_lendingPoolAddressesProvider),
            IMiniPoolAddressesProvider(address(deployedMiniPoolContracts.miniPoolAddressesProvider)),
            ILendingPool(_lendingPool)
        );
        address miniPoolConfigImpl = address(new MiniPoolConfigurator());
        deployedMiniPoolContracts.miniPoolAddressesProvider.setMiniPoolConfigurator(
            miniPoolConfigImpl
        );
        deployedMiniPoolContracts.miniPoolConfigurator = MiniPoolConfigurator(
            deployedMiniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator()
        );

        ILendingPoolAddressesProvider(_lendingPoolAddressesProvider).setMiniPoolAddressesProvider(
            address(deployedMiniPoolContracts.miniPoolAddressesProvider)
        );
        ILendingPoolAddressesProvider(_lendingPoolAddressesProvider).setFlowLimiter(
            address(deployedMiniPoolContracts.flowLimiter)
        );
        deployedMiniPoolContracts.miniPoolAddressesProvider.deployMiniPool(
            address(deployedMiniPoolContracts.miniPoolImpl),
            address(deployedMiniPoolContracts.aToken6909Impl)
        );

        /* Strategies */
        deployedMiniPoolContracts.stableStrategy = new MiniPoolDefaultReserveInterestRateStrategy(
            IMiniPoolAddressesProvider(_lendingPoolAddressesProvider),
            sStrat[0],
            sStrat[1],
            sStrat[2],
            sStrat[3]
        );
        deployedMiniPoolContracts.volatileStrategy = new MiniPoolDefaultReserveInterestRateStrategy(
            IMiniPoolAddressesProvider(_lendingPoolAddressesProvider),
            volStrat[0],
            volStrat[1],
            volStrat[2],
            volStrat[3]
        );
        deployedMiniPoolContracts.piStrategy = new MiniPoolPiReserveInterestRateStrategy(
            _lendingPoolAddressesProvider,
            0, // minipool ID
            defaultPidConfig.asset,
            defaultPidConfig.assetReserveType,
            defaultPidConfig.minControllerError,
            defaultPidConfig.maxITimeAmp,
            defaultPidConfig.optimalUtilizationRate,
            defaultPidConfig.kp,
            defaultPidConfig.ki
        );

        return deployedMiniPoolContracts;
    }

    function fixture_convertWithDecimals(uint256 amountRaw, uint256 decimalsA, uint256 decimalsB)
        public
        pure
        returns (uint256)
    {
        return (decimalsA > decimalsB)
            ? amountRaw * (10 ** (decimalsA - decimalsB))
            : amountRaw / (10 ** (decimalsB - decimalsA));
    }

    function fixture_preciseConvertWithDecimals(
        uint256 amountRay,
        uint256 decimalsA,
        uint256 decimalsB
    ) public pure returns (uint256) {
        return (decimalsA > decimalsB)
            ? amountRay / 10 ** (RAY_DECIMALS - PRICE_FEED_DECIMALS + (decimalsA - decimalsB))
            : amountRay / 10 ** (RAY_DECIMALS - PRICE_FEED_DECIMALS - (decimalsB - decimalsA));
    }

    function fixture_configureMiniPoolReserves(
        address[] memory tokensToConfigure,
        ConfigAddresses memory configAddresses,
        DeployedMiniPoolContracts memory miniPoolContracts
    ) public returns (address) {
        IMiniPoolConfigurator.InitReserveInput[] memory initInputParams =
            new IMiniPoolConfigurator.InitReserveInput[](tokensToConfigure.length);
        // address aTokensErc6909Addr;
        console.log("Getting Mini pool: ");
        address miniPool = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(cntr);
        cntr++;

        // aTokensErc6909Addr = miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(mp);
        console.log("Length:", tokensToConfigure.length);
        for (uint8 idx = 0; idx < tokensToConfigure.length; idx++) {
            string memory tmpSymbol = ERC20(tokensToConfigure[idx]).symbol();
            string memory tmpName = ERC20(tokensToConfigure[idx]).name();

            address interestStrategy = isStableStrategy[idx % tokens.length] != false
                ? configAddresses.stableStrategy
                : configAddresses.volatileStrategy;
            console.log("[common]interestStartegy: ", interestStrategy);
            initInputParams[idx] = IMiniPoolConfigurator.InitReserveInput({
                underlyingAssetDecimals: ERC20(tokensToConfigure[idx]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: tokensToConfigure[idx],
                underlyingAssetName: tmpName,
                underlyingAssetSymbol: tmpSymbol
            });
        }
        vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin()));
        miniPoolContracts.miniPoolConfigurator.batchInitReserve(
            initInputParams, IMiniPool(miniPool)
        );
        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator(),
            address(miniPoolContracts.miniPoolConfigurator)
        );

        for (uint8 idx = 0; idx < tokensToConfigure.length; idx++) {
            prepareReserveForLending(
                miniPoolContracts.miniPoolConfigurator,
                tokensToConfigure[idx],
                // isPid,
                // address(miniPoolContracts.miniPoolAddressesProvider),
                address(miniPool)
            );
        }
        vm.stopPrank();
        return miniPool;
    }

    function prepareReserveForLending(
        MiniPoolConfigurator miniPoolConfigurator,
        address tokenToPrepare,
        // bool isPid,
        // address miniPoolAddressesProvider,
        address mp
    ) public {
        miniPoolConfigurator.configureReserveAsCollateral(
            tokenToPrepare, 9500, 9700, 10100, IMiniPool(mp)
        );

        miniPoolConfigurator.activateReserve(tokenToPrepare, IMiniPool(mp));

        miniPoolConfigurator.enableBorrowingOnReserve(tokenToPrepare, IMiniPool(mp));
    }

    function getUsdValOfToken(uint256 amount, address token) public view returns (uint256) {
        return amount * oracle.getAssetPrice(token);
    }

    function fixture_getReserveData(address token, Cod3xLendDataProvider cod3xLendDataProvider)
        public
        view
        returns (ReserveDataParams memory)
    {
        (
            uint256 availableLiquidity,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        ) = cod3xLendDataProvider.getLpReserveDynamicData(token, true);
        return ReserveDataParams(
            availableLiquidity,
            totalVariableDebt,
            liquidityRate,
            variableBorrowRate,
            liquidityIndex,
            variableBorrowIndex,
            lastUpdateTimestamp
        );
    }

    function fixture_changePriceOfToken(
        TokenParams memory collateralParams,
        uint256 percentageOfChange,
        bool isPriceIncrease
    ) public returns (uint256) {
        uint256 newUsdcPrice;
        newUsdcPrice = (isPriceIncrease)
            ? (collateralParams.price + collateralParams.price * percentageOfChange / 10_000)
            : (collateralParams.price - collateralParams.price * percentageOfChange / 10_000);
        address collateralSource = oracle.getSourceOfAsset(address(collateralParams.token));
        MockAggregator agg = MockAggregator(collateralSource);
        console.log("1. Latest price: ", uint256(agg.latestAnswer()));

        agg.setLastAnswer(int256(newUsdcPrice));

        console.log("2. Latest price: ", uint256(agg.latestAnswer()));
        console.log("2. Oracle price: ", oracle.getAssetPrice(address(collateralParams.token)));
    }

    function fixture_calcCompoundedInterest(
        uint256 rate,
        uint256 currentTimestamp,
        uint256 lastUpdateTimestamp
    ) public pure returns (uint256) {
        uint256 timeDifference = currentTimestamp - lastUpdateTimestamp;
        if (timeDifference == 0) {
            return WadRayMath.RAY;
        }
        uint256 ratePerSecond = rate / 365 days;

        uint256 expMinusOne = timeDifference - 1;
        uint256 expMinusTwo = (timeDifference > 2) ? timeDifference - 2 : 0;

        uint256 basePowerTwo = ratePerSecond.rayMul(ratePerSecond);
        uint256 basePowerThree = basePowerTwo.rayMul(ratePerSecond);
        uint256 secondTerm = timeDifference * expMinusOne * basePowerTwo / 2;
        uint256 thirdTerm = timeDifference * expMinusOne * expMinusTwo * basePowerThree / 6;

        return WadRayMath.RAY + ratePerSecond * timeDifference + secondTerm + thirdTerm;
    }

    function fixture_calcExpectedVariableDebtTokenBalance(
        uint256 variableBorrowRate,
        uint256 variableBorrowIndex,
        uint256 lastUpdateTimestamp,
        uint256 scaledVariableDebt,
        uint256 txTimestamp
    ) public pure returns (uint256) {
        if (variableBorrowRate == 0) {
            return variableBorrowIndex;
        }
        uint256 cumulatedInterest =
            fixture_calcCompoundedInterest(variableBorrowRate, txTimestamp, lastUpdateTimestamp);
        uint256 normalizedDebt = cumulatedInterest.rayMul(variableBorrowIndex);

        uint256 expectedVariableDebtTokenBalance = scaledVariableDebt.rayMul(normalizedDebt);
        return expectedVariableDebtTokenBalance;
    }

    function turnOnRehypothecation(
        LendingPoolConfigurator _lendingPoolConfigurator,
        address _aToken,
        address _vaultAddr,
        address _profitHandler,
        uint256 _farmingPct,
        uint256 _claimingThreshold,
        uint256 _drift
    ) public {
        vm.startPrank(admin);
        _lendingPoolConfigurator.setVault(_aToken, _vaultAddr);
        _lendingPoolConfigurator.setFarmingPct(_aToken, _farmingPct);
        _lendingPoolConfigurator.setClaimingThreshold(_aToken, _claimingThreshold);
        _lendingPoolConfigurator.setFarmingPctDrift(_aToken, _drift);
        _lendingPoolConfigurator.setProfitHandler(_aToken, _profitHandler);
        vm.stopPrank();
    }
}
