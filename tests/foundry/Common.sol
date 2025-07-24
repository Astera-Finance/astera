// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ReserveConfiguration} from
    "../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {InitializableImmutableAdminUpgradeabilityProxy} from
    "../../contracts/protocol/libraries/upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol";
import {ERC20} from "../../contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {Rewarder} from "../../contracts/protocol/rewarder/lendingpool/Rewarder.sol";
import {Oracle} from "../../contracts/protocol/core/Oracle.sol";
import {
    AsteraDataProvider,
    StaticData,
    DynamicData,
    UserReserveData
} from "../../contracts/misc/AsteraDataProvider.sol";
import {Treasury} from "../../contracts/misc/Treasury.sol";
import {WETHGateway} from "../../contracts/misc/WETHGateway.sol";
import {
    LendingPoolAddressesProvider,
    ILendingPoolAddressesProvider
} from "../../contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import {DefaultReserveInterestRateStrategy} from
    "../../contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import {PiReserveInterestRateStrategy} from
    "../../contracts/protocol/core/interestRateStrategies/lendingpool/PiReserveInterestRateStrategy.sol";
import {MiniPoolPiReserveInterestRateStrategy} from
    "../../contracts/protocol/core/interestRateStrategies/minipool/MiniPoolPiReserveInterestRateStrategy.sol";
import {LendingPool} from "../../contracts/protocol/core/lendingpool/LendingPool.sol";
import {
    LendingPoolConfigurator,
    ILendingPoolConfigurator
} from "../../contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import {MiniPool, IMiniPool} from "../../contracts/protocol/core/minipool/MiniPool.sol";
import {MiniPoolAddressesProvider} from
    "../../contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import {
    MiniPoolConfigurator,
    IMiniPoolConfigurator
} from "../../contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import {FlowLimiter} from "../../contracts/protocol/core/minipool/FlowLimiter.sol";

import {ATokensAndRatesHelper} from "../../contracts/deployments/ATokensAndRatesHelper.sol";
import {AToken} from "../../contracts/protocol/tokenization/ERC20/AToken.sol";
import {ATokenERC6909} from "../../contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import {VariableDebtToken} from "../../contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import {MockAggregator} from "../../contracts/mocks/oracle/MockAggregator.sol";
import {MockReaperVault2} from "../../contracts/mocks/tokens/MockVault.sol";
import {WadRayMath} from "../../contracts/protocol/libraries/math/WadRayMath.sol";

import
    "../../contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import "../../contracts/mocks/oracle/PriceOracle.sol";
import {MockVaultUnit} from "../../contracts/mocks/tokens/MockVaultUnit.sol";
import {MockPyth} from "node_modules/@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import {PythAggregatorV3} from "node_modules/@pythnetwork/pyth-sdk-solidity/PythAggregatorV3.sol";

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

    struct ConfigAddresses {
        address asteraDataProvider;
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
        AsteraDataProvider asteraDataProvider;
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

    struct TokenParamsExtended {
        ERC20 token;
        AToken aToken;
        AToken aTokenWrapper;
        MockVaultUnit vault;
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

    struct CommonContracts {
        address[] aggregators;
        address[] aggregatorsPyth;
        Oracle oracle;
        Oracle oraclePyth;
        WETHGateway wETHGateway;
        AToken aToken;
        VariableDebtToken variableDebtToken;
        ATokenERC6909 aTokenErc6909;
        AToken[] aTokens;
        AToken[] aTokensWrapper;
        VariableDebtToken[] variableDebtTokens;
        ATokenERC6909[] aTokensErc6909;
        MockReaperVault2[] mockedVaults;
        MockVaultUnit[] mockVaultUnits;
        PidConfig defaultPidConfig;
    }

    // Fork Identifier
    string RPC = vm.envString("RPC_PROVIDER");
    uint256 constant FORK_BLOCK = 116753757;
    uint256 public opFork;

    // Constants
    // address constant ZERO_ADDRESS = address(0);
    address constant BASE_CURRENCY = address(0);
    uint256 constant BASE_CURRENCY_UNIT = 100000000;
    address constant FALLBACK_ORACLE = address(0);
    uint256 constant TVL_CAP = 1e20;
    uint256 constant PERCENTAGE_FACTOR = 10_000;
    uint32 constant PRICE_FEED_DECIMALS = 8;
    uint8 constant RAY_DECIMALS = 27;

    // Tokens addresses
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant WBTC = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant ETH_USD_SOURCE = 0xb7B9A39CC63f856b90B364911CC324dC46aC1770;
    address constant USDC_USD_SOURCE = 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;

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
    uint256 constant USDC_OFFSET = 0;
    uint256 constant WBTC_OFFSET = 1;
    uint256 constant WETH_OFFSET = 2;
    uint256 constant DAI_OFFSET = 3;

    address admin = 0xe027880CEB8114F2e367211dF977899d00e66138;
    address poolOwner = makeAddr("poolOwner");
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
    string constant MARKET_ID = "Astera Genesis Market";

    CommonContracts public commonContracts;

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
        // bytes memory bytecode = abi.encodePacked(vm.getCode("../../contracts/incentives/Rewarder.sol:Rewarder"));
        // address anotherAddress;
        // assembly {
        //     anotherAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        // }
        deployedContracts.rewarder = new Rewarder();

        deployedContracts.lendingPoolAddressesProvider = new LendingPoolAddressesProvider();

        deployedContracts.lendingPoolAddressesProvider.setPoolAdmin(admin);
        deployedContracts.lendingPoolAddressesProvider.setEmergencyAdmin(admin);

        lendingPool = new LendingPool();
        deployedContracts.lendingPoolAddressesProvider.setLendingPoolImpl(address(lendingPool));
        lendingPoolProxyAddress =
            address(deployedContracts.lendingPoolAddressesProvider.getLendingPool());
        deployedContracts.lendingPool = LendingPool(lendingPoolProxyAddress);
        deployedContracts.treasury = new Treasury(deployedContracts.lendingPoolAddressesProvider);

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

        commonContracts.aToken = new AToken();
        commonContracts.aTokenErc6909 = new ATokenERC6909();
        commonContracts.variableDebtToken = new VariableDebtToken();
        // stableDebtToken = new StableDebtToken();
        fixture_deployMocks(
            address(deployedContracts.treasury),
            address(deployedContracts.lendingPoolAddressesProvider)
        );
        deployedContracts.lendingPoolAddressesProvider.setPriceOracle(
            address(commonContracts.oracle)
        );
        vm.label(address(commonContracts.oracle), "Oracle");
        deployedContracts.asteraDataProvider =
            new AsteraDataProvider(ETH_USD_SOURCE, USDC_USD_SOURCE);
        deployedContracts.asteraDataProvider.setLendingPoolAddressProvider(
            address(deployedContracts.lendingPoolAddressesProvider)
        );

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

        commonContracts.defaultPidConfig = PidConfig({
            asset: DAI,
            assetReserveType: true,
            minControllerError: -400e24,
            maxITimeAmp: 20 days,
            optimalUtilizationRate: 45e25,
            kp: 1e27,
            ki: 13e19
        });
        deployedContracts.piStrategy = new PiReserveInterestRateStrategy(
            address(deployedContracts.lendingPoolAddressesProvider),
            commonContracts.defaultPidConfig.asset,
            commonContracts.defaultPidConfig.assetReserveType,
            commonContracts.defaultPidConfig.minControllerError,
            commonContracts.defaultPidConfig.maxITimeAmp,
            commonContracts.defaultPidConfig.optimalUtilizationRate,
            commonContracts.defaultPidConfig.kp,
            commonContracts.defaultPidConfig.ki
        );

        return (deployedContracts);
    }

    function fixture_deployMocks(address _treasury, address _lendingPoolAddressesProvider) public {
        /* Prices to be changed here */
        ERC20[] memory erc20tokens = fixture_getErc20Tokens(tokens);
        int256[] memory prices = new int256[](4);
        uint256[] memory timeouts = new uint256[](4);
        /* All chainlink price feeds have 8 decimals */
        prices[0] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // USDC
        prices[1] = int256(67_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[2] = int256(3700 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[3] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // DAI
        commonContracts.mockedVaults = fixture_deployReaperVaultMocks(tokens, _treasury);
        commonContracts.mockVaultUnits = fixture_deployVaultUnits(tokens);
        // usdcPriceFeed = new MockAggregator(100000000, int256(uint256(mintableUsdc.decimals())));
        // wbtcPriceFeed = new MockAggregator(1600000000000, int256(uint256(mintableWbtc.decimals())));
        // ethPriceFeed = new MockAggregator(120000000000, int256(uint256(mintableWeth.decimals())));
        (, commonContracts.aggregators, timeouts) = fixture_getTokenPriceFeeds(erc20tokens, prices);

        commonContracts.oracle = new Oracle(
            tokens,
            commonContracts.aggregators,
            timeouts,
            FALLBACK_ORACLE,
            BASE_CURRENCY,
            BASE_CURRENCY_UNIT,
            _lendingPoolAddressesProvider
        );

        (commonContracts.aggregatorsPyth, timeouts) =
            fixture_getTokenPriceFeedsPyth(erc20tokens, prices);

        commonContracts.oraclePyth = new Oracle(
            tokens,
            commonContracts.aggregatorsPyth,
            timeouts,
            FALLBACK_ORACLE,
            BASE_CURRENCY,
            BASE_CURRENCY_UNIT,
            _lendingPoolAddressesProvider
        );
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

        vm.prank(admin);
        lendingPoolConfiguratorProxy.setPoolPause(false);

        commonContracts.aTokens =
            fixture_getATokens(tokens, AsteraDataProvider(configAddresses.asteraDataProvider));
        commonContracts.aTokensWrapper = fixture_getATokensWrapper(
            tokens, AsteraDataProvider(configAddresses.asteraDataProvider)
        );
        commonContracts.variableDebtTokens =
            fixture_getVarDebtTokens(tokens, AsteraDataProvider(configAddresses.asteraDataProvider));
        commonContracts.wETHGateway =
            new WETHGateway(address(commonContracts.aTokensWrapper[WETH_OFFSET]));
        commonContracts.wETHGateway.authorizeLendingPool(ledingPool);

        for (uint256 idx; idx < tokens.length; idx++) {
            vm.label(
                address(commonContracts.aTokens[idx]), string.concat("AToken ", uintToString(idx))
            );
            vm.label(
                address(commonContracts.variableDebtTokens[idx]),
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
            // console2.log("[common] main interestStartegy: ", interestStrategy);
            initInputParams[idx] = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: aTokenAddress,
                variableDebtTokenImpl: address(commonContracts.variableDebtToken),
                underlyingAssetDecimals: ERC20(tokens[idx]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: tokens[idx],
                reserveType: reserveTypes[idx],
                treasury: configAddresses.treasury,
                incentivesController: configAddresses.rewarder,
                underlyingAssetName: tmpSymbol,
                aTokenName: string.concat("Astera ", tmpSymbol),
                aTokenSymbol: string.concat("cl", tmpSymbol),
                variableDebtTokenName: string.concat("Astera variable debt bearing ", tmpSymbol),
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

    function fixture_getATokens(address[] memory _tokens, AsteraDataProvider asteraDataProvider)
        public
        view
        returns (AToken[] memory _aTokens)
    {
        _aTokens = new AToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            (address _aTokenAddress,) = asteraDataProvider.getLpTokens(_tokens[idx], true);
            // console2.log("AToken%s: %s", idx, _aTokenAddress);
            _aTokens[idx] = AToken(_aTokenAddress);
        }
    }

    function fixture_getATokensWrapper(
        address[] memory _tokens,
        AsteraDataProvider asteraDataProvider
    ) public view returns (AToken[] memory _aTokensW) {
        _aTokensW = new AToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            (address _aTokenAddress,) = asteraDataProvider.getLpTokens(_tokens[idx], true);
            // console2.log("AToken%s: %s", idx, _aTokenAddress);
            _aTokensW[idx] = AToken(address(AToken(_aTokenAddress).WRAPPER_ADDRESS()));
        }
    }

    function fixture_getVarDebtTokens(
        address[] memory _tokens,
        AsteraDataProvider asteraDataProvider
    ) public returns (VariableDebtToken[] memory _varDebtTokens) {
        _varDebtTokens = new VariableDebtToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            (, address _variableDebtToken) = asteraDataProvider.getLpTokens(_tokens[idx], true);
            // console2.log("Atoken address", _variableDebtToken);
            string memory debtToken = string.concat("debtToken", uintToString(idx));
            vm.label(_variableDebtToken, debtToken);
            console2.log("Debt token %s: %s", idx, _variableDebtToken);
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

    function fixture_getTokenPriceFeedsPyth(ERC20[] memory _tokens, int256[] memory _prices)
        public
        returns (address[] memory _aggregators, uint256[] memory _timeouts)
    {
        require(_tokens.length == _prices.length, "Length of params shall be equal");

        MockPyth _priceFeedMock = new MockPyth(10000, 0);
        _aggregators = new address[](_tokens.length);
        _timeouts = new uint256[](_tokens.length);
        for (uint256 idx; idx < _tokens.length; idx++) {
            bytes[] memory priceFeedData = new bytes[](1);
            priceFeedData[0] = _priceFeedMock.createPriceFeedUpdateData(
                bytes32(idx + 1),
                int64(_prices[idx]),
                0,
                int32(PRICE_FEED_DECIMALS),
                int64(_prices[idx]),
                0,
                uint64(block.timestamp),
                uint64(block.timestamp)
            );
            _priceFeedMock.updatePriceFeeds(priceFeedData);
            _aggregators[idx] =
                address(new PythAggregatorV3(address(_priceFeedMock), bytes32(idx + 1)));
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
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            console2.log("IDX: ", idx);
            uint256 price = commonContracts.oracle.getAssetPrice(address(_tokens[idx]));
            console2.log("_toGiveInUsd:", _toGiveInUsd);
            uint256 rawGive = (_toGiveInUsd / price) * 10 ** PRICE_FEED_DECIMALS;
            console2.log("rawGive:", rawGive);
            console2.log(
                "Distributed %s of %s",
                rawGive / (10 ** (18 - _tokens[idx].decimals())),
                _tokens[idx].symbol()
            );
            deal(
                address(_tokens[idx]),
                _testContractAddress,
                rawGive / (10 ** (18 - _tokens[idx].decimals()))
            );
            console2.log(
                "Balance: %s %s",
                _tokens[idx].balanceOf(_testContractAddress),
                _tokens[idx].symbol()
            );
        }
    }

    /**
     * @dev put address(0) for _miniPoolAddressProvider in order to initialize all minipool contracts
     */
    function fixture_deployMiniPoolSetup(
        address _lendingPoolAddressesProvider,
        address _lendingPool,
        address _asteraDataProvider,
        DeployedMiniPoolContracts memory miniPoolContracts
    ) public returns (DeployedMiniPoolContracts memory, uint256) {
        uint256 miniPoolId;
        if (address(miniPoolContracts.miniPoolImpl) == address(0)) {
            miniPoolContracts.miniPoolImpl = new MiniPool();
        }

        if (address(miniPoolContracts.aToken6909Impl) == address(0)) {
            miniPoolContracts.aToken6909Impl = new ATokenERC6909();
        }

        if (address(miniPoolContracts.miniPoolAddressesProvider) == address(0)) {
            /* First deployment so configure everything */

            miniPoolContracts.miniPoolAddressesProvider = new MiniPoolAddressesProvider(
                ILendingPoolAddressesProvider(_lendingPoolAddressesProvider)
            );
            console2.log("miniPoolImpl: ", address(miniPoolContracts.miniPoolImpl));
            console2.log("aToken6909Impl: ", address(miniPoolContracts.aToken6909Impl));
            miniPoolId = miniPoolContracts.miniPoolAddressesProvider.deployMiniPool(
                address(miniPoolContracts.miniPoolImpl),
                address(miniPoolContracts.aToken6909Impl),
                poolOwner
            );
            miniPoolContracts.flowLimiter = new FlowLimiter(
                IMiniPoolAddressesProvider(address(miniPoolContracts.miniPoolAddressesProvider))
            );
            address miniPoolConfigImpl = address(new MiniPoolConfigurator());
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolConfigurator(miniPoolConfigImpl);
            miniPoolContracts.miniPoolConfigurator = MiniPoolConfigurator(
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator()
            );

            ILendingPoolAddressesProvider(_lendingPoolAddressesProvider)
                .setMiniPoolAddressesProvider(address(miniPoolContracts.miniPoolAddressesProvider));
            ILendingPoolAddressesProvider(_lendingPoolAddressesProvider).setFlowLimiter(
                address(miniPoolContracts.flowLimiter)
            );

            /* Strategies */
            miniPoolContracts.stableStrategy = new MiniPoolDefaultReserveInterestRateStrategy(
                IMiniPoolAddressesProvider(_lendingPoolAddressesProvider),
                sStrat[0],
                sStrat[1],
                sStrat[2],
                sStrat[3]
            );
            miniPoolContracts.volatileStrategy = new MiniPoolDefaultReserveInterestRateStrategy(
                IMiniPoolAddressesProvider(_lendingPoolAddressesProvider),
                volStrat[0],
                volStrat[1],
                volStrat[2],
                volStrat[3]
            );
            miniPoolContracts.piStrategy = new MiniPoolPiReserveInterestRateStrategy(
                _lendingPoolAddressesProvider,
                0, // minipool ID
                commonContracts.defaultPidConfig.asset,
                commonContracts.defaultPidConfig.assetReserveType,
                commonContracts.defaultPidConfig.minControllerError,
                commonContracts.defaultPidConfig.maxITimeAmp,
                commonContracts.defaultPidConfig.optimalUtilizationRate,
                commonContracts.defaultPidConfig.kp,
                commonContracts.defaultPidConfig.ki
            );
            AsteraDataProvider(_asteraDataProvider).setMiniPoolAddressProvider(
                address(miniPoolContracts.miniPoolAddressesProvider)
            );
        } else {
            /* Get the same AERC6909 impl as previously */
            miniPoolId = miniPoolContracts.miniPoolAddressesProvider.deployMiniPool(
                address(miniPoolContracts.miniPoolImpl),
                address(miniPoolContracts.aToken6909Impl),
                poolOwner
            );
        }

        return (miniPoolContracts, miniPoolId);
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
        DeployedMiniPoolContracts memory miniPoolContracts,
        uint256 miniPoolId
    ) public returns (address) {
        IMiniPoolConfigurator.InitReserveInput[] memory initInputParams =
            new IMiniPoolConfigurator.InitReserveInput[](tokensToConfigure.length);
        console2.log("Getting Mini pool: ");
        address miniPool = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(miniPoolId);

        console2.log("Length:", tokensToConfigure.length);
        for (uint8 idx = 0; idx < tokensToConfigure.length; idx++) {
            string memory tmpSymbol = ERC20(tokensToConfigure[idx]).symbol();
            string memory tmpName = ERC20(tokensToConfigure[idx]).name();

            address interestStrategy = isStableStrategy[idx % tokens.length] != false
                ? configAddresses.stableStrategy
                : configAddresses.volatileStrategy;
            // console2.log("[common]interestStartegy: ", interestStrategy);
            initInputParams[idx] = IMiniPoolConfigurator.InitReserveInput({
                underlyingAssetDecimals: ERC20(tokensToConfigure[idx]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: tokensToConfigure[idx],
                underlyingAssetName: tmpName,
                underlyingAssetSymbol: tmpSymbol
            });
        }
        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin()));
        miniPoolContracts.miniPoolConfigurator.batchInitReserve(
            initInputParams, IMiniPool(miniPool)
        );
        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator(),
            address(miniPoolContracts.miniPoolConfigurator)
        );
        vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(miniPoolId)));
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
        return amount * commonContracts.oracle.getAssetPrice(token);
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
        address collateralSource =
            commonContracts.oracle.getSourceOfAsset(address(collateralParams.token));
        MockAggregator agg = MockAggregator(collateralSource);
        console2.log("1. Latest price: ", uint256(agg.latestAnswer()));

        agg.setLastAnswer(int256(newUsdcPrice));

        console2.log("2. Latest price: ", uint256(agg.latestAnswer()));
        console2.log(
            "2. Oracle price: ",
            commonContracts.oracle.getAssetPrice(address(collateralParams.token))
        );
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
        _lendingPoolConfigurator.setProfitHandler(_aToken, _profitHandler);
        _lendingPoolConfigurator.setVault(_aToken, _vaultAddr);
        _lendingPoolConfigurator.setFarmingPct(_aToken, _farmingPct);
        _lendingPoolConfigurator.setClaimingThreshold(_aToken, _claimingThreshold);
        _lendingPoolConfigurator.setFarmingPctDrift(_aToken, _drift);
        vm.stopPrank();
    }
}
