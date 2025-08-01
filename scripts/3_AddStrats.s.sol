// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "./DeployDataTypes.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console2.sol";
import {StratsHelper} from "./helpers/StratsHelper.s.sol";

contract AddStrats is Script, StratsHelper, Test {
    using stdJson for string;

    function writeJsonData(string memory path) internal {
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
            console2.log("Serializing");
            vm.serializeString("strategies", "piStrategiesSymbols", symbols);
            vm.serializeAddress("strategies", "piStrategies", piAddresses);
        }

        {
            console2.log("Stable");
            address[] memory stableAddresses =
                new address[](contracts.miniPoolStableStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolStableStrategies.length; idx++) {
                stableAddresses[idx] = address(contracts.miniPoolStableStrategies[idx]);
            }
            vm.serializeAddress("strategies", "miniPoolStableStrategies", stableAddresses);
        }
        {
            console2.log("Volatile");
            address[] memory volatileAddresses =
                new address[](contracts.miniPoolVolatileStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolVolatileStrategies.length; idx++) {
                volatileAddresses[idx] = address(contracts.miniPoolVolatileStrategies[idx]);
            }
            vm.serializeAddress("strategies", "miniPoolVolatileStrategies", volatileAddresses);
        }
        {
            console2.log("PiAddresses");
            address[] memory piAddresses = new address[](contracts.miniPoolPiStrategies.length);
            string[] memory symbols = new string[](contracts.miniPoolPiStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolPiStrategies.length; idx++) {
                symbols[idx] = ERC20(contracts.miniPoolPiStrategies[idx]._asset()).symbol();
                piAddresses[idx] = address(contracts.miniPoolPiStrategies[idx]);
            }
            vm.serializeString("strategies", "miniPoolPiStrategiesSymbols", symbols);
            output = vm.serializeAddress("strategies", "miniPoolPiStrategies", piAddresses);
        }

        vm.writeJson(output, path);

        console2.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);
    }

    function run() external returns (DeployedContracts memory) {
        console2.log("3_AddStrats");

        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/3_StratsToAdd.json");
        console2.log("PATH: ", path);
        string memory config = vm.readFile(path);
        PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
            config.parseRaw(".poolAddressesProviderConfig"), (PoolAddressesProviderConfig)
        );
        uint256 miniPoolId = poolAddressesProviderConfig.poolId;
        LinearStrategy[] memory volatileStrategies =
            abi.decode(config.parseRaw(".volatileStrategies"), (LinearStrategy[]));
        LinearStrategy[] memory stableStrategies =
            abi.decode(config.parseRaw(".stableStrategies"), (LinearStrategy[]));
        PiStrategy[] memory piStrategies =
            abi.decode(config.parseRaw(".piStrategies"), (PiStrategy[]));

        LinearStrategy[] memory miniPoolVolatileStrategies =
            abi.decode(config.parseRaw(".miniPoolVolatileStrategies"), (LinearStrategy[]));
        LinearStrategy[] memory miniPoolStableStrategies =
            abi.decode(config.parseRaw(".miniPoolStableStrategies"), (LinearStrategy[]));
        PiStrategy[] memory miniPoolPiStrategies =
            abi.decode(config.parseRaw(".miniPoolPiStrategies"), (PiStrategy[]));

        if (!vm.envBool("MAINNET")) {
            /* ****** Lending pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/1_LendingPoolContracts.json");
                console2.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }

            {
                address[] memory stableStrats = config.readAddressArray(".stableStrategies");
                for (uint8 idx; idx < stableStrats.length; idx++) {
                    contracts.stableStrategies.push(
                        DefaultReserveInterestRateStrategy(stableStrats[idx])
                    );
                }
            }

            {
                address[] memory volatileStrats = config.readAddressArray(".volatileStrategies");
                for (uint8 idx; idx < volatileStrats.length; idx++) {
                    contracts.volatileStrategies.push(
                        DefaultReserveInterestRateStrategy(volatileStrats[idx])
                    );
                }
            }

            {
                address[] memory piStrats = config.readAddressArray(".piStrategies");
                for (uint8 idx; idx < piStrats.length; idx++) {
                    contracts.piStrategies.push(PiReserveInterestRateStrategy(piStrats[idx]));
                }
            }

            contracts.lendingPoolAddressesProvider =
                LendingPoolAddressesProvider(config.readAddress(".lendingPoolAddressesProvider"));

            // /* Read all mocks deployed */
            // path = string.concat(root, "/scripts/outputs/testnet/0_MockedTokens.json");
            // console2.log("PATH: ", path);
            // config = vm.readFile(path);
            // address[] memory mockedTokens = config.readAddressArray(".mockedTokens");

            // require(
            //     mockedTokens.length >= piStrategies.length,
            //     "There are not enough mocked tokens. Deploy mocks.. "
            // );
            // {
            //     for (uint8 idx = 0; idx < piStrategies.length; idx++) {
            //         for (uint8 i = 0; i < mockedTokens.length; i++) {
            //             if (
            //                 keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
            //                     == keccak256(abi.encodePacked(piStrategies[idx].symbol))
            //             ) {
            //                 piStrategies[idx].tokenAddress = address(mockedTokens[i]);
            //                 break;
            //             }
            //         }
            //         require(
            //             piStrategies[idx].tokenAddress != address(0), "Mocked token not assigned"
            //         );
            //     }
            // }

            /* ******* Mini pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/2_MiniPoolContracts.json");
                console2.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }

            {
                address[] memory miniStableStrats =
                    config.readAddressArray(".miniPoolStableStrategies");
                for (uint8 idx = 0; idx < miniStableStrats.length; idx++) {
                    contracts.miniPoolStableStrategies.push(
                        MiniPoolDefaultReserveInterestRateStrategy(miniStableStrats[idx])
                    );
                }
            }

            {
                address[] memory miniVolatileStrats =
                    config.readAddressArray(".miniPoolVolatileStrategies");
                for (uint8 idx = 0; idx < miniVolatileStrats.length; idx++) {
                    contracts.miniPoolVolatileStrategies.push(
                        MiniPoolDefaultReserveInterestRateStrategy(miniVolatileStrats[idx])
                    );
                }
            }

            {
                address[] memory miniPiStrats = config.readAddressArray(".miniPoolPiStrategies");
                for (uint8 idx = 0; idx < miniPiStrats.length; idx++) {
                    contracts.miniPoolPiStrategies.push(
                        MiniPoolPiReserveInterestRateStrategy(miniPiStrats[idx])
                    );
                }
            }

            contracts.miniPoolAddressesProvider =
                MiniPoolAddressesProvider(config.readAddress(".miniPoolAddressesProvider"));

            // /* Assigned mocked tokens to the mini pool Pi strats */
            // require(
            //     mockedTokens.length >= miniPoolPiStrategies.length,
            //     "There are not enough mocked tokens. Deploy mocks.. "
            // );
            // {
            //     for (uint8 idx = 0; idx < miniPoolPiStrategies.length; idx++) {
            //         for (uint8 i = 0; i < mockedTokens.length; i++) {
            //             if (
            //                 keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
            //                     == keccak256(abi.encodePacked(miniPoolPiStrategies[idx].symbol))
            //             ) {
            //                 miniPoolPiStrategies[idx].tokenAddress = address(mockedTokens[i]);
            //                 break;
            //             }
            //         }
            //         require(
            //             miniPoolPiStrategies[idx].tokenAddress != address(0),
            //             "Mocked token not assigned"
            //         );
            //     }
            // }

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
            path = string.concat(root, "/scripts/outputs/testnet/3_DeployedStrategies.json");
        } else if (vm.envBool("MAINNET")) {
            /* ****** Lending pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/1_LendingPoolContracts.json");
                console2.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }

            {
                address[] memory stableStrats = config.readAddressArray(".stableStrategies");
                for (uint8 idx; idx < stableStrats.length; idx++) {
                    contracts.stableStrategies.push(
                        DefaultReserveInterestRateStrategy(stableStrats[idx])
                    );
                }
            }

            {
                address[] memory volatileStrats = config.readAddressArray(".volatileStrategies");
                for (uint8 idx; idx < volatileStrats.length; idx++) {
                    contracts.volatileStrategies.push(
                        DefaultReserveInterestRateStrategy(volatileStrats[idx])
                    );
                }
            }

            {
                address[] memory piStrats = config.readAddressArray(".piStrategies");
                for (uint8 idx; idx < piStrats.length; idx++) {
                    contracts.piStrategies.push(PiReserveInterestRateStrategy(piStrats[idx]));
                }
            }

            contracts.lendingPoolAddressesProvider =
                LendingPoolAddressesProvider(config.readAddress(".lendingPoolAddressesProvider"));

            /* ******* Mini pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/2_MiniPoolContracts.json");
                console2.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }

            {
                address[] memory miniStableStrats =
                    config.readAddressArray(".miniPoolStableStrategies");
                for (uint8 idx = 0; idx < miniStableStrats.length; idx++) {
                    contracts.miniPoolStableStrategies.push(
                        MiniPoolDefaultReserveInterestRateStrategy(miniStableStrats[idx])
                    );
                }
            }

            {
                address[] memory miniVolatileStrats =
                    config.readAddressArray(".miniPoolVolatileStrategies");
                for (uint8 idx = 0; idx < miniVolatileStrats.length; idx++) {
                    contracts.miniPoolVolatileStrategies.push(
                        MiniPoolDefaultReserveInterestRateStrategy(miniVolatileStrats[idx])
                    );
                }
            }

            {
                address[] memory miniPiStrats = config.readAddressArray(".miniPoolPiStrategies");
                for (uint8 idx = 0; idx < miniPiStrats.length; idx++) {
                    contracts.miniPoolPiStrategies.push(
                        MiniPoolPiReserveInterestRateStrategy(miniPiStrats[idx])
                    );
                }
            }

            contracts.miniPoolAddressesProvider =
                MiniPoolAddressesProvider(config.readAddress(".miniPoolAddressesProvider"));

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
            path = string.concat(root, "/scripts/outputs/mainnet/3_DeployedStrategies.json");
        }
        writeJsonData(path);
        return contracts;
    }
}
