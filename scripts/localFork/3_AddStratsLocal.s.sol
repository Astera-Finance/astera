// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../DeployDataTypes.sol";
import "../helpers/StratsHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {DeployMiniPoolLocal} from "./2_DeployMiniPoolLocal.s.sol";

contract AddStratsLocal is Script, StratsHelper, Test {
    using stdJson for string;

    function writeJsonData(string memory root, string memory path) internal {
        string memory output;
        {
            address[] memory stableAddresses = new address[](contracts.stableStrategies.length);
            for (uint256 idx = 0; idx < contracts.stableStrategies.length; idx++) {
                stableAddresses[idx] = address(contracts.stableStrategies[idx]);
            }
            vm.serializeAddress("strategies", "stableStrategies", stableAddresses);
        }
        {
            address[] memory volatileAddresses = new address[](contracts.volatileStrategies.length);
            for (uint256 idx = 0; idx < contracts.volatileStrategies.length; idx++) {
                volatileAddresses[idx] = address(contracts.volatileStrategies[idx]);
            }
            vm.serializeAddress("strategies", "volatileStrategies", volatileAddresses);
        }
        {
            address[] memory piAddresses = new address[](contracts.piStrategies.length);
            string[] memory symbols = new string[](contracts.piStrategies.length);
            for (uint256 idx = 0; idx < contracts.piStrategies.length; idx++) {
                symbols[idx] = ERC20(contracts.piStrategies[idx]._asset()).symbol();
                piAddresses[idx] = address(contracts.piStrategies[idx]);
            }
            console.log("Serializing");
            vm.serializeString("strategies", "piStrategiesSymbols", symbols);
            vm.serializeAddress("strategies", "piStrategies", piAddresses);
        }

        {
            console.log("Stable");
            address[] memory stableAddresses =
                new address[](contracts.miniPoolStableStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolStableStrategies.length; idx++) {
                stableAddresses[idx] = address(contracts.miniPoolStableStrategies[idx]);
            }
            vm.serializeAddress("strategies", "miniPoolStableStrategies", stableAddresses);
        }
        {
            console.log("Volatile");
            address[] memory volatileAddresses =
                new address[](contracts.miniPoolVolatileStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolVolatileStrategies.length; idx++) {
                volatileAddresses[idx] = address(contracts.miniPoolVolatileStrategies[idx]);
            }
            vm.serializeAddress("strategies", "miniPoolVolatileStrategies", volatileAddresses);
        }
        {
            console.log("PiAddresses");
            address[] memory piAddresses = new address[](contracts.miniPoolPiStrategies.length);
            string[] memory symbols = new string[](contracts.miniPoolPiStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolPiStrategies.length; idx++) {
                symbols[idx] = ERC20(contracts.miniPoolPiStrategies[idx]._asset()).symbol();
                piAddresses[idx] = address(contracts.miniPoolPiStrategies[idx]);
            }
            vm.serializeString("strategies", "miniPoolPiStrategiesSymbols", symbols);
            output = vm.serializeAddress("strategies", "miniPoolPiStrategies", piAddresses);
        }

        vm.writeJson(output, "./scripts/localFork/outputs/3_DeployedStrategies.json");

        path = string.concat(root, "/scripts/3_DeployedStrategies.json");

        console.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);
    }

    function run() external returns (DeployedContracts memory) {
        console.log("3_AddStrats");

        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/3_StratsToAdd.json");
        console.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);
        PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
            deploymentConfig.parseRaw(".poolAddressesProviderConfig"), (PoolAddressesProviderConfig)
        );
        Factors memory factors = abi.decode(deploymentConfig.parseRaw(".factors"), (Factors));
        uint256 miniPoolId = poolAddressesProviderConfig.poolId;
        LinearStrategy[] memory volatileStrategies =
            abi.decode(deploymentConfig.parseRaw(".volatileStrategies"), (LinearStrategy[]));
        LinearStrategy[] memory stableStrategies =
            abi.decode(deploymentConfig.parseRaw(".stableStrategies"), (LinearStrategy[]));
        PiStrategy[] memory piStrategies =
            abi.decode(deploymentConfig.parseRaw(".piStrategies"), (PiStrategy[]));

        LinearStrategy[] memory miniPoolVolatileStrategies =
            abi.decode(deploymentConfig.parseRaw(".miniPoolVolatileStrategies"), (LinearStrategy[]));
        LinearStrategy[] memory miniPoolStableStrategies =
            abi.decode(deploymentConfig.parseRaw(".miniPoolStableStrategies"), (LinearStrategy[]));
        PiStrategy[] memory miniPoolPiStrategies =
            abi.decode(deploymentConfig.parseRaw(".miniPoolPiStrategies"), (PiStrategy[]));

        /* Fork Identifier */
        string memory RPC = vm.envString("BASE_RPC_URL");
        uint256 FORK_BLOCK = 21838058;
        uint256 fork;
        fork = vm.createSelectFork(RPC, FORK_BLOCK);

        /* Config fetching */
        DeployMiniPoolLocal deployMiniPool = new DeployMiniPoolLocal();
        contracts = deployMiniPool.run();

        vm.startPrank(FOUNDRY_DEFAULT);
        _deployStrategies(
            contracts.lendingPoolAddressesProvider,
            volatileStrategies,
            stableStrategies,
            piStrategies
        );
        _deployMiniPoolStrategies(
            contracts.miniPoolAddressesProvider,
            miniPoolId,
            miniPoolVolatileStrategies,
            miniPoolStableStrategies,
            miniPoolPiStrategies
        );
        /* Pi miniPool strats */
        address[] memory tmpStrats = deployedStrategies.readAddressArray(".miniPoolPiStrategies");
        for (uint8 idx = 0; idx < miniPoolPiStrategies.length; idx++) {
            require(
                contracts.miniPoolPiStrategies[idx].M_FACTOR() == factors.m_factor, "Wrong M_FACTOR"
            );
            require(
                contracts.miniPoolPiStrategies[idx].N_FACTOR() == factors.n_factor, "Wrong N_FACTOR"
            );
        }
        vm.stopPrank();

        writeJsonData(root, path);
        return contracts;
    }
}
