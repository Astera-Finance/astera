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
            address(deployedContracts.cod3xLendDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        mockedVaults = fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function testSetFallbackOracle() public {
        ERC20[] memory erc20tokens = fixture_getErc20Tokens(tokens);
        int256[] memory prices = new int256[](4);
        // All chainlink price feeds have 8 decimals
        prices[0] = int256(95 * 10 ** PRICE_FEED_DECIMALS - 1); // USDC
        prices[1] = int256(63_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[2] = int256(3300 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[3] = int256(95 * 10 ** PRICE_FEED_DECIMALS - 1); // DAI
        (, aggregators) = fixture_getTokenPriceFeeds(erc20tokens, prices);

        Oracle fallbackOracle =
            new Oracle(tokens, aggregators, ZERO_ADDRESS, ZERO_ADDRESS, BASE_CURRENCY_UNIT);

        oracle.setFallbackOracle(address(fallbackOracle));
        assertEq(address(fallbackOracle), oracle.getFallbackOracle());
    }

    function testGetAssetPrice(uint32 baseCurrency) public {
        address usdcAddress = address(tokens[0]);
        vm.assume(baseCurrency != BASE_CURRENCY_UNIT);

        ERC20[] memory erc20tokens = fixture_getErc20Tokens(tokens);
        int256[] memory prices = new int256[](4);
        // All chainlink price feeds have 8 decimals
        prices[0] = int256(95 * 10 ** PRICE_FEED_DECIMALS - 1); // USDC
        prices[1] = int256(63_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[2] = int256(3300 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[3] = int256(95 * 10 ** PRICE_FEED_DECIMALS - 1); // DAI
        (, aggregators) = fixture_getTokenPriceFeeds(erc20tokens, prices);

        Oracle _oracle = new Oracle(tokens, aggregators, ZERO_ADDRESS, usdcAddress, baseCurrency);

        assertEq(_oracle.getAssetPrice(usdcAddress), baseCurrency);
    }

    function testGetAssetPriceWithSourceAsZero() public {
        address usdcAddress = address(tokens[0]);
        address[] memory assets = new address[](1);
        assets[0] = usdcAddress;
        ERC20[] memory erc20tokens = fixture_getErc20Tokens(assets);
        int256[] memory prices = new int256[](1);

        prices[0] = int256(0); // USDC
        (, aggregators) = fixture_getTokenPriceFeeds(erc20tokens, prices);
        oracle.setAssetSources(assets, aggregators);
        vm.expectRevert();
        oracle.getAssetPrice(usdcAddress);

        prices[0] = int256(1 * 10 ** PRICE_FEED_DECIMALS);
        (, aggregators) = fixture_getTokenPriceFeeds(erc20tokens, prices);
        oracle.setAssetSources(assets, aggregators);
        assertEq(oracle.getAssetPrice(usdcAddress), uint256(prices[0]));
    }
}
