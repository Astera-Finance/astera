// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PythAggregatorV3} from "node_modules/@pythnetwork/pyth-sdk-solidity/PythAggregatorV3.sol"; // Adjust path if your LstAggregator.sol is in a different directory

/**
 * @title DeployPythAggregatorV3
 * @notice A Foundry script to deploy the PythAggregatorV3 contract on the Base network.
 *
 * Run the command:
 * `forge script script/DeploPythAggregatorV3.s.sol:DeployPythAggregatorV3 --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify -vvvv`
 * (Add `--verify` if you want to verify on Etherscan/Blockscout, which requires Etherscan API key set as `ETHERSCAN_API_KEY`)
 */
contract DeploPythAggregatorV3 is Script {
    // https://docs.pyth.network/price-feeds/contract-addresses/evm
    address private immutable PYTH_CONTRACT = 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729;

    // https://insights.pyth.network/price-feeds
    bytes32 private immutable PRICE_FEED_ID =
        0x583015352f5936e099fa7149d496ac087c5bfbfc386ce875be27dc4d69c2e023;

    /**
     * @notice The main function to run the deployment script.
     * @dev This function will deploy the PythAggregator contract.
     */
    function run() public returns (PythAggregatorV3 pythAggregator) {
        vm.startBroadcast();

        // Deploy the PythAggregator contract.
        pythAggregator = new PythAggregatorV3(PYTH_CONTRACT, PRICE_FEED_ID);

        // Log the address of the newly deployed contract for easy reference.
        console.log("pythAggregator deployed at:", address(pythAggregator));

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = pythAggregator.latestRoundData();

        console.log("pythAggregator.latestRoundData():");
        console.log("  roundId: %s", roundId);
        console.log("  answer: %s", answer);
        console.log("  startedAt: %s", startedAt);
        console.log("  updatedAt: %s", updatedAt);
        console.log("  answeredInRound: %s", answeredInRound);

        // Stop broadcasting transactions.
        vm.stopBroadcast();
    }
}
