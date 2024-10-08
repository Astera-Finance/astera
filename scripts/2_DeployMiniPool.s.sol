// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {DeployLendingPool} from "./1_DeployLendingPool.s.sol";

contract DeployMiniPool is Script, Test, DeploymentUtils {
    using stdJson for string;

    function writeJsonData(string memory root, string memory path) internal {
        /* Write important contracts into the file */
        vm.serializeAddress("miniPoolContracts", "miniPoolImpl", address(contracts.miniPoolImpl));
        vm.serializeAddress(
            "miniPoolContracts",
            "miniPoolAddressesProvider",
            address(contracts.miniPoolAddressesProvider)
        );
        vm.serializeAddress("miniPoolContracts", "flowLimiter", address(contracts.flowLimiter));

        {
            address[] memory stableAddresses =
                new address[](contracts.miniPoolStableStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolStableStrategies.length; idx++) {
                stableAddresses[idx] = address(contracts.miniPoolStableStrategies[idx]);
            }
            vm.serializeAddress("miniPoolContracts", "miniPoolStableStrategies", stableAddresses);
        }
        {
            address[] memory volatileAddresses =
                new address[](contracts.miniPoolVolatileStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolVolatileStrategies.length; idx++) {
                volatileAddresses[idx] = address(contracts.miniPoolVolatileStrategies[idx]);
            }
            vm.serializeAddress(
                "miniPoolContracts", "miniPoolVolatileStrategies", volatileAddresses
            );
        }
        {
            address[] memory piAddresses = new address[](contracts.miniPoolPiStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolPiStrategies.length; idx++) {
                piAddresses[idx] = address(contracts.miniPoolPiStrategies[idx]);
            }
            vm.serializeAddress("miniPoolContracts", "miniPoolPiStrategies", piAddresses);
        }

        string memory output = vm.serializeAddress(
            "miniPoolContracts", "miniPoolConfigurator", address(contracts.miniPoolConfigurator)
        );

        vm.writeJson(output, "./scripts/outputs/2_MiniPoolContracts.json");

        path = string.concat(root, "/scripts/outputs/2_MiniPoolContracts.json");
        console.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);
    }

    function run() external returns (DeployedContracts memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/2_DeploymentConfig.json");
        console.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);

        PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
            deploymentConfig.parseRaw(".poolAddressesProviderConfig"), (PoolAddressesProviderConfig)
        );
        PoolReserversConfig[] memory poolReserversConfig =
            abi.decode(deploymentConfig.parseRaw(".poolReserversConfig"), (PoolReserversConfig[]));
        LinearStrategy[] memory volatileStrategies =
            abi.decode(deploymentConfig.parseRaw(".volatileStrategies"), (LinearStrategy[]));
        LinearStrategy[] memory stableStrategies =
            abi.decode(deploymentConfig.parseRaw(".stableStrategies"), (LinearStrategy[]));

        PiStrategy[] memory piStrategies =
            abi.decode(deploymentConfig.parseRaw(".piStrategies"), (PiStrategy[]));

        OracleConfig memory oracleConfig =
            abi.decode(deploymentConfig.parseRaw(".oracleConfig"), (OracleConfig));

        if (vm.envBool("LOCAL_FORK")) {
            /* Fork Identifier [ARBITRUM] */
            {
                string memory RPC = vm.envString("ARBITRUM_RPC_URL");
                uint256 FORK_BLOCK = 257827379;
                uint256 arbFork;
                arbFork = vm.createSelectFork(RPC, FORK_BLOCK);
            }

            /* Config fetching */
            DeployLendingPool deployLendingPool = new DeployLendingPool();
            contracts = deployLendingPool.run();

            /* Deployment */
            vm.startPrank(FOUNDRY_DEFAULT);
            deployMiniPoolInfra(
                oracleConfig,
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolReserversConfig,
                poolAddressesProviderConfig.poolId,
                FOUNDRY_DEFAULT
            );
            vm.stopPrank();

            /* Write important contracts into the file */
            writeJsonData(root, path);
        } else if (vm.envBool("TESTNET")) {
            console.log("Testnet Deployment");
            /* Mocked tokens deployment */
            {
                MockedToken[] memory mockedTokens =
                    abi.decode(deploymentConfig.parseRaw(".mockedToken"), (MockedToken[]));

                require(mockedTokens.length == poolReserversConfig.length, "Wrong config in Json");
                string[] memory symbols = new string[](poolReserversConfig.length);
                uint8[] memory decimals = new uint8[](poolReserversConfig.length);
                int256[] memory prices = new int256[](poolReserversConfig.length);

                for (uint8 idx = 0; idx < poolReserversConfig.length; idx++) {
                    symbols[idx] = mockedTokens[idx].symbol;
                    decimals[idx] = uint8(mockedTokens[idx].decimals);
                    prices[idx] = int256(mockedTokens[idx].prices);
                }

                // Deployment
                console.log("Broadcasting....");
                vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
                (address[] memory tokens,) = _deployERC20Mocks(symbols, symbols, decimals, prices);
                vm.stopBroadcast();

                for (uint8 idx = 0; idx < poolReserversConfig.length; idx++) {
                    poolReserversConfig[idx].tokenAddress = address(tokens[idx]);
                }
            }

            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            contracts.lendingPool = LendingPool(deploymentConfig.readAddress(".lendingPool"));
            contracts.aTokenErc6909 = ATokenERC6909(deploymentConfig.readAddress(".aTokenErc6909"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(deploymentConfig.readAddress(".lendingPoolConfigurator"));

            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console.log("Deploying lending pool infra");
            deployMiniPoolInfra(
                oracleConfig,
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolReserversConfig,
                poolAddressesProviderConfig.poolId,
                vm.addr(vm.envUint("PRIVATE_KEY"))
            );
            vm.stopBroadcast();
            writeJsonData(root, path);
        } else if (vm.envBool("MAINNET")) {
            console.log("Mainnet Deployment");
            /* Get deployed lending pool infra dontracts */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            contracts.lendingPool = LendingPool(deploymentConfig.readAddress(".lendingPool"));
            contracts.aTokenErc6909 = ATokenERC6909(deploymentConfig.readAddress(".aTokenErc6909"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(deploymentConfig.readAddress(".lendingPoolConfigurator"));

            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console.log("Deploying lending pool infra");
            deployMiniPoolInfra(
                oracleConfig,
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolReserversConfig,
                poolAddressesProviderConfig.poolId,
                vm.addr(vm.envUint("PRIVATE_KEY"))
            );
            vm.stopBroadcast();
            writeJsonData(root, path);
        } else {
            console.log("No deployment type selected in .env");
        }
        return contracts;
    }
}
