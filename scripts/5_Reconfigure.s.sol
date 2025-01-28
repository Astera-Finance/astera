// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {InitAndConfigurationHelper} from "./helpers/InitAndConfigurationHelper.s.sol";
import "./DeployDataTypes.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";

contract Reconfigure is Script, InitAndConfigurationHelper, Test {
    using stdJson for string;

    function readAddressesToContracts(string memory path) public {
        string memory deployedStrategies = vm.readFile(path);
        /* Pi miniPool strats */
        address[] memory tmpStrats = deployedStrategies.readAddressArray(".miniPoolPiStrategies");
        delete contracts.miniPoolPiStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.miniPoolPiStrategies.push(
                MiniPoolPiReserveInterestRateStrategy(tmpStrats[idx])
            );
        }
        /* Stable miniPool strats */
        tmpStrats = deployedStrategies.readAddressArray(".miniPoolStableStrategies");
        delete contracts.miniPoolStableStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.miniPoolStableStrategies.push(
                MiniPoolDefaultReserveInterestRateStrategy(tmpStrats[idx])
            );
        }
        /* Volatile miniPool strats */
        tmpStrats = deployedStrategies.readAddressArray(".miniPoolVolatileStrategies");
        delete contracts.miniPoolVolatileStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.miniPoolVolatileStrategies.push(
                MiniPoolDefaultReserveInterestRateStrategy(tmpStrats[idx])
            );
        }
        /* Pi strats */
        tmpStrats = deployedStrategies.readAddressArray(".piStrategies");
        delete contracts.piStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.piStrategies.push(PiReserveInterestRateStrategy(tmpStrats[idx]));
        }
        /* Stable strats */
        tmpStrats = deployedStrategies.readAddressArray(".stableStrategies");
        delete contracts.stableStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.stableStrategies.push(DefaultReserveInterestRateStrategy(tmpStrats[idx]));
        }
        /* Volatile strats */
        tmpStrats = deployedStrategies.readAddressArray(".volatileStrategies");
        delete contracts.volatileStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.volatileStrategies.push(DefaultReserveInterestRateStrategy(tmpStrats[idx]));
        }
    }

    function run() external returns (DeployedContracts memory) {
        console.log("5_Reconfigure");

        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/5_Reconfigure.json");
        console.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);

        PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
            deploymentConfig.parseRaw(".poolAddressesProviderConfig"), (PoolAddressesProviderConfig)
        );

        PoolReserversConfig[] memory lendingPoolReserversConfig = abi.decode(
            deploymentConfig.parseRaw(".lendingPoolReserversConfig"), (PoolReserversConfig[])
        );

        PoolReserversConfig[] memory miniPoolReserversConfig = abi.decode(
            deploymentConfig.parseRaw(".miniPoolReserversConfig"), (PoolReserversConfig[])
        );

        if (vm.envBool("TESTNET")) {
            console.log("Testnet");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(deploymentConfig.readAddress(".lendingPoolConfigurator"));
            contracts.aTokensAndRatesHelper =
                ATokensAndRatesHelper(deploymentConfig.readAddress(".aTokensAndRatesHelper"));
            contracts.oracle = Oracle(deploymentConfig.readAddress(".oracle"));

            readAddressesToContracts(
                string.concat(root, "/scripts/outputs/testnet/3_DeployedStrategies.json")
            );

            /* Read all mocks deployed */
            path = string.concat(root, "/scripts/outputs/testnet/0_MockedTokens.json");
            console.log("PATH: ", path);
            string memory config = vm.readFile(path);
            address[] memory mockedTokens = config.readAddressArray(".mockedTokens");

            require(
                mockedTokens.length >= lendingPoolReserversConfig.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            // {
            //     for (uint8 idx = 0; idx < lendingPoolReserversConfig.length; idx++) {
            //         for (uint8 i = 0; i < mockedTokens.length; i++) {
            //             if (
            //                 keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
            //                     == keccak256(abi.encodePacked(lendingPoolReserversConfig[idx].symbol))
            //             ) {
            //                 lendingPoolReserversConfig[idx].tokenAddress = address(mockedTokens[i]);
            //                 break;
            //             }
            //         }
            //         require(
            //             lendingPoolReserversConfig[idx].tokenAddress != address(0),
            //             "Mocked token not assigned"
            //         );
            //     }
            // }

            /* Reconfigure */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console.log("Reconfiguring lending pool..");
            _configureReserves(contracts, lendingPoolReserversConfig, 0);
            _changeStrategies(contracts, lendingPoolReserversConfig);
            vm.stopBroadcast();

            /* *********** Mini pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/2_MiniPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                deploymentConfig.readAddress(".miniPoolAddressesProvider")
            );
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(deploymentConfig.readAddress(".miniPoolConfigurator"));

            address[] memory addrs = deploymentConfig.readAddressArray(".aTokenErc6909Proxy");
            for (uint8 idx = 0; idx < addrs.length; idx++) {
                contracts.aTokenErc6909Proxy.push(ATokenERC6909(addrs[idx]));
                console.log("Setting addr:", addrs[idx]);
            }

            /* Mini pool mocks assignment */
            // {
            //     for (uint8 idx = 0; idx < miniPoolReserversConfig.length; idx++) {
            //         for (uint8 i = 0; i < mockedTokens.length; i++) {
            //             if (
            //                 keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
            //                     == keccak256(abi.encodePacked(miniPoolReserversConfig[idx].symbol))
            //             ) {
            //                 miniPoolReserversConfig[idx].tokenAddress = address(mockedTokens[i]);
            //                 break;
            //             }
            //         }
            //         require(
            //             miniPoolReserversConfig[idx].tokenAddress != address(0),
            //             "Mocked token not assigned"
            //         );
            //     }
            // }

            /* Reconfigure */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console.log("Reconfigure mini pool...");
            address mp =
                contracts.miniPoolAddressesProvider.getMiniPool(poolAddressesProviderConfig.poolId);
            _configureMiniPoolReserves(contracts, miniPoolReserversConfig, mp, 0);
            _changeMiniPoolStrategies(contracts, miniPoolReserversConfig, mp);
            vm.stopBroadcast();
        } else if (vm.envBool("MAINNET")) {
            console.log("Mainnet");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            /* Read necessary lending pool infra contracts */
            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(deploymentConfig.readAddress(".lendingPoolConfigurator"));
            contracts.aTokensAndRatesHelper =
                ATokensAndRatesHelper(deploymentConfig.readAddress(".aTokensAndRatesHelper"));
            contracts.oracle = Oracle(deploymentConfig.readAddress(".oracle"));

            readAddressesToContracts(
                string.concat(root, "/scripts/outputs/mainnet/3_DeployedStrategies.json")
            );

            /* Reconfigure */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            _configureReserves(contracts, lendingPoolReserversConfig, 0);
            _changeStrategies(contracts, lendingPoolReserversConfig);
            vm.stopBroadcast();

            /* *********** Mini pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/2_MiniPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            /* Read necessary mini pool infra contracts */
            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                deploymentConfig.readAddress(".miniPoolAddressesProvider")
            );
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(deploymentConfig.readAddress(".miniPoolConfigurator"));

            address[] memory addrs = deploymentConfig.readAddressArray(".aTokenErc6909Proxy");
            for (uint8 idx = 0; idx < addrs.length; idx++) {
                contracts.aTokenErc6909Proxy.push(ATokenERC6909(addrs[idx]));
                console.log("Setting addr:", addrs[idx]);
            }
            /* Reconfigure */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            address mp =
                contracts.miniPoolAddressesProvider.getMiniPool(poolAddressesProviderConfig.poolId);
            _configureMiniPoolReserves(contracts, miniPoolReserversConfig, mp, 0);
            _changeMiniPoolStrategies(contracts, miniPoolReserversConfig, mp);
            vm.stopBroadcast();
        } else {
            console.log("No deployment type selected in .env");
        }
    }
}
