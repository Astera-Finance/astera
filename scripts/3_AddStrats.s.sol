// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {DeployMiniPool} from "./2_DeployMiniPool.s.sol";

contract AddStrats is Script, DeploymentUtils, Test {
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

        vm.writeJson(output, "./scripts/outputs/3_DeployedStrategies.json");

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

        if (vm.envBool("LOCAL_FORK")) {
            /* Fork Identifier */
            string memory RPC = vm.envString("BASE_RPC_URL");
            uint256 FORK_BLOCK = 21838058;
            uint256 fork;
            fork = vm.createSelectFork(RPC, FORK_BLOCK);

            /* Config fetching */
            DeployMiniPool deployMiniPool = new DeployMiniPool();
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
            vm.stopPrank();
        } else if (vm.envBool("TESTNET")) {
            /* ****** Lending pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            {
                address[] memory stableStrats =
                    deploymentConfig.readAddressArray(".stableStrategies");
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

            /* Read all mocks deployed */
            string memory path = string.concat(root, "/scripts/outputs/0_MockedTokens.json");
            console.log("PATH: ", path);
            string memory config = vm.readFile(path);
            address[] memory mockedTokens = config.readAddressArray(".mockedTokens");

            require(
                mockedTokens.length >= piStrategies.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            {
                for (uint8 idx = 0; idx < piStrategies.length; idx++) {
                    for (uint8 i = 0; i < mockedTokens.length; i++) {
                        if (
                            keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
                                == keccak256(abi.encodePacked(piStrategies[idx].symbol))
                        ) {
                            piStrategies[idx].tokenAddress = address(mockedTokens[i]);
                            break;
                        }
                    }
                    require(
                        piStrategies[idx].tokenAddress != address(0), "Mocked token not assigned"
                    );
                }
            }

            /* ******* Mini pool settings */
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

            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                deploymentConfig.readAddress(".miniPoolAddressesProvider")
            );

            /* Assigned mocked tokens to the mini pool Pi strats */
            require(
                mockedTokens.length >= miniPoolPiStrategies.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            {
                for (uint8 idx = 0; idx < miniPoolPiStrategies.length; idx++) {
                    for (uint8 i = 0; i < mockedTokens.length; i++) {
                        if (
                            keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
                                == keccak256(abi.encodePacked(miniPoolPiStrategies[idx].symbol))
                        ) {
                            miniPoolPiStrategies[idx].tokenAddress = address(mockedTokens[i]);
                            break;
                        }
                    }
                    require(
                        miniPoolPiStrategies[idx].tokenAddress != address(0),
                        "Mocked token not assigned"
                    );
                }
            }

            /* Deploy on the testnet */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
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
            vm.stopBroadcast();
        } else if (vm.envBool("MAINNET")) {
            /* ****** Lending pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            {
                address[] memory stableStrats =
                    deploymentConfig.readAddressArray(".stableStrategies");
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

            /* ******* Mini pool settings */
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

            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                deploymentConfig.readAddress(".miniPoolAddressesProvider")
            );

            /* Deploy on the mainnet */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
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
            vm.stopBroadcast();
        }
        writeJsonData(root, path);
        return contracts;
    }
}
