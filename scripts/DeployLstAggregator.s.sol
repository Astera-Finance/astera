// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LstAggregator} from "contracts/protocol/core/LstAggregator.sol"; // Adjust path if your LstAggregator.sol is in a different directory

/**
 * @title DeployLstAggregator
 * @notice A Foundry script to deploy the LstAggregator contract on the Base network.
 *
 * Run the command:
 * `forge script script/DeployLstAggregator.s.sol:DeployLstAggregator --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify -vvvv`
 * (Add `--verify` if you want to verify on Etherscan/Blockscout, which requires Etherscan API key set as `ETHERSCAN_API_KEY`)
 */
contract DeployLstAggregator is Script {
    // Chainlink Price Feed addresses for Base Mainnet
    // ETH/USD price feed
    address private immutable ETH_USD_PRICE_FEED = 0x3c6Cd9Cc7c7a4c2Cf5a82734CD249D7D593354dA;
    // wstETH/ETH price feed
    // available WETH / USD address private immutable WSTETH_ETH_PRICE_FEED = 0x43a5C292A453A3bF3606fa856197f09D7B74251a;
    // ezETH/ETH price feed
    address private immutable EZETH_ETH_PRICE_FEED = 0xB1d9A4Fe9331E28C5588B63343BF064A397aadB8;
    // ezETH/ETH price feed exchange rate
    address private immutable EZETH_ETH_PRICE_FEED_EXCHANGE_RATE =
        0xb71F79770BA599940F454c70e63d4DE0E8606731;
    // weETH/ETH price feed
    address private immutable WEETH_ETH_PRICE_FEED = 0xC4bF21Ab46bd22Cf993c0AAa363577bD2Af83544;

    // wrsETH/rsETH price feed
    address private immutable WRS_ETH_PRICE_FEED = 0xEEDF0B095B5dfe75F3881Cb26c19DA209A27463a;

    // Aggregator name for the deployed contract
    // string private constant AGGREGATOR_NAME_WST = "wstETH/USD";
    string private constant AGGREGATOR_NAME_EZ = "ezETH/USD";
    string private constant AGGREGATOR_NAME_WE = "weETH/USD";
    string private constant AGGREGATOR_NAME_WRS = "wrsETH/USD";

    /**
     * @notice The main function to run the deployment script.
     * @dev This function will deploy the LstAggregator contract.
     */
    function run() public returns (LstAggregator lstAggregator) {
        // Start broadcasting transactions from the deployer's address.
        // This is crucial for sending actual transactions on a live network.
        vm.startBroadcast();

        string memory aggregatorName = AGGREGATOR_NAME_WE;
        address lstPriceFeed = WEETH_ETH_PRICE_FEED;

        // Deploy the LstAggregator contract.
        // The constructor takes three arguments:
        // 1. _underlyingPriceFeed (ETH/USD in this case)
        // 2. _lstPriceFeed (stETH/ETH in this case)
        // 3. _aggregatorName (a descriptive name for the new aggregator)
        lstAggregator = new LstAggregator(ETH_USD_PRICE_FEED, lstPriceFeed, aggregatorName);

        // Log the address of the newly deployed contract for easy reference.
        console.log("LstAggregator deployed at:", address(lstAggregator));
        console.log("ETH/USD Price Feed:", ETH_USD_PRICE_FEED);
        console.log("Aggregator Name:", aggregatorName);

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = lstAggregator.latestRoundData();

        console.log("LstAggregator.latestRoundData():");
        console.log("  roundId: %s", roundId);
        console.log("  answer: %s", answer);
        console.log("  startedAt: %s", startedAt);
        console.log("  updatedAt: %s", updatedAt);
        console.log("  answeredInRound: %s", answeredInRound);

        // Stop broadcasting transactions.
        vm.stopBroadcast();
    }
}
