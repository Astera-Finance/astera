// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

contract OracleTest is Common {
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.asteraDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(commonContracts.aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        commonContracts.mockedVaults =
            fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function testSetFallbackOracle() public {
        ERC20[] memory erc20tokens = fixture_getErc20Tokens(tokens);
        int256[] memory prices = new int256[](4);
        uint256[] memory timeouts = new uint256[](4);
        // All chainlink price feeds have 8 decimals
        prices[0] = int256(95 * 10 ** PRICE_FEED_DECIMALS - 1); // USDC
        prices[1] = int256(63_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[2] = int256(3300 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[3] = int256(95 * 10 ** PRICE_FEED_DECIMALS - 1); // DAI
        (, commonContracts.aggregators, timeouts) = fixture_getTokenPriceFeeds(erc20tokens, prices);

        Oracle fallbackOracle = new Oracle(
            tokens,
            commonContracts.aggregators,
            timeouts,
            address(0),
            address(0),
            BASE_CURRENCY_UNIT,
            address(deployedContracts.lendingPoolAddressesProvider)
        );

        commonContracts.oracle.setFallbackOracle(address(fallbackOracle));
        assertEq(address(fallbackOracle), commonContracts.oracle.getFallbackOracle());
    }

    function testGetAssetPrice(uint32 baseCurrency) public {
        address usdcAddress = address(tokens[0]);
        vm.assume(baseCurrency != BASE_CURRENCY_UNIT);

        ERC20[] memory erc20tokens = fixture_getErc20Tokens(tokens);
        int256[] memory prices = new int256[](4);
        uint256[] memory timeouts = new uint256[](4);

        // All chainlink price feeds have 8 decimals
        prices[0] = int256(95 * 10 ** PRICE_FEED_DECIMALS - 1); // USDC
        prices[1] = int256(63_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[2] = int256(3300 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[3] = int256(95 * 10 ** PRICE_FEED_DECIMALS - 1); // DAI
        (, commonContracts.aggregators, timeouts) = fixture_getTokenPriceFeeds(erc20tokens, prices);

        Oracle _oracle = new Oracle(
            tokens,
            commonContracts.aggregators,
            timeouts,
            address(0),
            usdcAddress,
            baseCurrency,
            address(deployedContracts.lendingPoolAddressesProvider)
        );

        assertEq(_oracle.getAssetPrice(usdcAddress), baseCurrency);
    }

    function testGetAssetPriceWithSourceAsZero() public {
        address usdcAddress = address(tokens[0]);
        address[] memory assets = new address[](1);
        assets[0] = usdcAddress;
        uint256[] memory timeouts = new uint256[](1);
        ERC20[] memory erc20tokens = fixture_getErc20Tokens(assets);
        int256[] memory prices = new int256[](1);

        prices[0] = int256(0); // USDC
        (, commonContracts.aggregators, timeouts) = fixture_getTokenPriceFeeds(erc20tokens, prices);
        commonContracts.oracle.setAssetSources(assets, commonContracts.aggregators, timeouts);
        vm.expectRevert();
        commonContracts.oracle.getAssetPrice(usdcAddress);

        prices[0] = int256(1 * 10 ** PRICE_FEED_DECIMALS);
        (, commonContracts.aggregators, timeouts) = fixture_getTokenPriceFeeds(erc20tokens, prices);
        commonContracts.oracle.setAssetSources(assets, commonContracts.aggregators, timeouts);
        assertEq(commonContracts.oracle.getAssetPrice(usdcAddress), uint256(prices[0]));
    }

    function testGetAssetPricePyth(uint32 baseCurrency) public {
        address usdcAddress = address(tokens[0]);
        vm.assume(baseCurrency != BASE_CURRENCY_UNIT);

        ERC20[] memory erc20tokens = fixture_getErc20Tokens(tokens);
        int256[] memory prices = new int256[](tokens.length);
        uint256[] memory timeouts = new uint256[](tokens.length);

        uint256[] memory prevPrices = new uint256[](tokens.length);

        for (uint256 idx = 0; idx < tokens.length; idx++) {
            prevPrices[idx] = commonContracts.oraclePyth.getAssetPrice(tokens[idx]);
            console.log("CurrentPrices: ", prevPrices[idx]);
        }

        // All chainlink price feeds have 8 decimals
        prices[0] = int256(95 * 10 ** PRICE_FEED_DECIMALS - 1); // USDC
        prices[1] = int256(63_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[2] = int256(3300 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[3] = int256(95 * 10 ** PRICE_FEED_DECIMALS - 1); // DAI
        (commonContracts.aggregatorsPyth, timeouts) =
            fixture_getTokenPriceFeedsPyth(erc20tokens, prices);

        Oracle[] memory _oracles = new Oracle[](tokens.length);

        for (uint256 idx = 0; idx < tokens.length; idx++) {
            _oracles[idx] = new Oracle(
                tokens,
                commonContracts.aggregatorsPyth,
                timeouts,
                address(0),
                tokens[idx],
                baseCurrency,
                address(deployedContracts.lendingPoolAddressesProvider)
            );
            assertNotEq(_oracles[idx].getAssetPrice(tokens[idx]), prevPrices[idx]);
        }
    }

    function testAsUsdPricePyth() public {
        string memory localRpc = vm.envString("BASE_RPC_URL");
        opFork = vm.createSelectFork(localRpc, 26803485);
        address pyth = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a; // BASE

        bytes32 priceId = 0x9db37f4d5654aad3e37e2e14ffd8d53265fb3026d1d8f91146539eebaa2ef45f; //AERO

        PythAggregatorV3 pythAggregator = new PythAggregatorV3(pyth, priceId);

        (uint80 roundId, int256 price, uint256 startedAt, uint256 timestamp,) =
            pythAggregator.latestRoundData();

        console2.log("RoundId", uint256(roundId));
        console2.log("price", price);
        console2.log("startedAt", startedAt);
        console2.log("timestamp", timestamp);

        assertNotEq(roundId, 0, "roundId equal to 0");
        assertNotEq(timestamp, 0, "timestamp equal to 0");
        assertNotEq(startedAt, 0, "startedAt equal to 0");
        assertGt(block.timestamp, timestamp, "timestamp grater then block timestamp");
        assertGe(price, 0, "price less than 0");

        assertApproxEqRel(uint256(price), 0.75e8, 0.02e18, "price is wrong"); // +/- 2%
    }
}
