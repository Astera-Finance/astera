// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {DeployMiniPool} from "./2_DeployMiniPool.s.sol";

contract AddAssets is Script, DeploymentUtils, Test {
    using stdJson for string;

    function run() external returns (DeployedContracts memory) {
        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/3_StratsToAdd.json");
        console.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);

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

        /* Fork Identifier [ARBITRUM] */
        string memory RPC = vm.envString("ARBITRUM_RPC_URL");
        uint256 FORK_BLOCK = 257827379;
        uint256 arbFork;
        arbFork = vm.createSelectFork(RPC, FORK_BLOCK);

        // /* Config fetching */
        // DeployMiniPool deployMiniPool = new DeployMiniPool();
        // contracts = deployMiniPool.run();

        /* Lending pool settings */
        {
            string memory outputPath =
                string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
            console.log("PATH: ", outputPath);
            deploymentConfig = vm.readFile(outputPath);
        }

        {
            address[] memory stableStrats = deploymentConfig.readAddressArray(".stableStrategies");
            for (uint8 idx; idx < stableStrats.length; idx++) {
                contracts.stableStrategies.push(
                    DefaultReserveInterestRateStrategy(stableStrats[idx])
                );
            }
        }

        {
            address[] memory volatileStrats =
                deploymentConfig.readAddressArray(".volatileStrategies");
            for (uint8 idx; idx < volatileStrats.length; idx++) {
                contracts.volatileStrategies.push(
                    DefaultReserveInterestRateStrategy(volatileStrats[idx])
                );
            }
        }

        {
            address[] memory piStrats = deploymentConfig.readAddressArray(".piStrategies");
            for (uint8 idx; idx < piStrats.length; idx++) {
                contracts.piStrategies.push(PiReserveInterestRateStrategy(piStrats[idx]));
            }
        }

        contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
            deploymentConfig.readAddress(".lendingPoolAddressesProvider")
        );

        /* Mini pool settings */
        {
            string memory outputPath =
                string.concat(root, "/scripts/outputs/2_MiniPoolContracts.json");
            console.log("PATH: ", outputPath);
            deploymentConfig = vm.readFile(outputPath);
        }

        {
            address[] memory miniStableStrats =
                deploymentConfig.readAddressArray(".miniPoolStableStrategies");
            for (uint8 idx = 0; idx < miniStableStrats.length; idx++) {
                contracts.miniPoolStableStrategies.push(
                    MiniPoolDefaultReserveInterestRateStrategy(miniStableStrats[idx])
                );
            }
        }

        {
            address[] memory miniVolatileStrats =
                deploymentConfig.readAddressArray(".miniPoolVolatileStrategies");
            for (uint8 idx = 0; idx < miniVolatileStrats.length; idx++) {
                contracts.miniPoolVolatileStrategies.push(
                    MiniPoolDefaultReserveInterestRateStrategy(miniVolatileStrats[idx])
                );
            }
        }

        {
            address[] memory miniPiStrats =
                deploymentConfig.readAddressArray(".miniPoolPiStrategies");
            for (uint8 idx = 0; idx < miniPiStrats.length; idx++) {
                contracts.miniPoolPiStrategies.push(
                    MiniPoolPiReserveInterestRateStrategy(miniPiStrats[idx])
                );
            }
        }

        contracts.miniPoolAddressesProvider =
            MiniPoolAddressesProvider(deploymentConfig.readAddress(".miniPoolAddressesProvider"));

        vm.startPrank(FOUNDRY_DEFAULT);
        _deployStrategies(
            contracts.lendingPoolAddressesProvider,
            volatileStrategies,
            stableStrategies,
            piStrategies
        );
        _deployMiniPoolStrategies(
            contracts.miniPoolAddressesProvider,
            miniPoolVolatileStrategies,
            miniPoolStableStrategies,
            miniPoolPiStrategies
        );
        vm.stopPrank();

        return contracts;
    }
}
