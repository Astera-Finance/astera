// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {AddAssets} from "./3_AddAssets.s.sol";

contract Reconfigure is Script, DeploymentUtils, Test {
    using stdJson for string;

    function run() external returns (DeployedContracts memory) {
        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/4_Reconfigure.json");
        console.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);

        Roles memory roles = abi.decode(deploymentConfig.parseRaw(".roles"), (Roles));

        PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
            deploymentConfig.parseRaw(".poolAddressesProviderConfig"), (PoolAddressesProviderConfig)
        );

        PoolReserversConfig[] memory lendingPoolReserversConfig = abi.decode(
            deploymentConfig.parseRaw(".lendingPoolReserversConfig"), (PoolReserversConfig[])
        );

        PoolReserversConfig[] memory miniPoolReserversConfig = abi.decode(
            deploymentConfig.parseRaw(".miniPoolReserversConfig"), (PoolReserversConfig[])
        );

        if (vm.envBool("LOCAL_FORK")) {
            /* Fork Identifier [ARBITRUM] */
            string memory RPC = vm.envString("ARBITRUM_RPC_URL");
            uint256 FORK_BLOCK = 257827379;
            uint256 arbFork;
            arbFork = vm.createSelectFork(RPC, FORK_BLOCK);

            /* Config fetching */
            AddAssets addAssets = new AddAssets();
            contracts = addAssets.run();

            vm.startPrank(FOUNDRY_DEFAULT);
            _configureReserves(contracts, lendingPoolReserversConfig);
            address mp =
                contracts.miniPoolAddressesProvider.getMiniPool(poolAddressesProviderConfig.poolId);
            _configureMiniPoolReserves(contracts, miniPoolReserversConfig, mp);

            vm.stopPrank();
        } else if (vm.envBool("TESTNET")) {
            console.log("Testnet Deployment");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            contracts.aTokensAndRatesHelper =
                ATokensAndRatesHelper(deploymentConfig.readAddress(".aTokensAndRatesHelper"));

            /* Mocked tokens deployment */
            {
                deploymentConfig = vm.readFile(path);
                MockedToken[] memory mockedTokens = abi.decode(
                    deploymentConfig.parseRaw(".lendingPoolReserversConfig"), (MockedToken[])
                );

                require(
                    mockedTokens.length == lendingPoolReserversConfig.length, "Wrong config in Json"
                );
                string[] memory symbols = new string[](lendingPoolReserversConfig.length);
                uint8[] memory decimals = new uint8[](lendingPoolReserversConfig.length);
                int256[] memory prices = new int256[](lendingPoolReserversConfig.length);

                for (uint8 idx = 0; idx < lendingPoolReserversConfig.length; idx++) {
                    symbols[idx] = mockedTokens[idx].symbol;
                    decimals[idx] = uint8(mockedTokens[idx].decimals);
                    prices[idx] = int256(mockedTokens[idx].prices);
                }

                // Deployment
                console.log("Broadcasting....");
                vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
                (address[] memory tokens,) = _deployERC20Mocks(symbols, symbols, decimals, prices);
                vm.stopBroadcast();

                for (uint8 idx = 0; idx < lendingPoolReserversConfig.length; idx++) {
                    lendingPoolReserversConfig[idx].tokenAddress = address(tokens[idx]);
                }
            }

            /* Reconfigure */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            _configureReserves(contracts, lendingPoolReserversConfig);
            vm.stopBroadcast();

            /* *********** Mini pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/2_MiniPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                deploymentConfig.readAddress(".miniPoolAddressesProvider")
            );
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(deploymentConfig.readAddress(".miniPoolConfigurator"));

            /* Mocked tokens deployment */
            {
                deploymentConfig = vm.readFile(path);
                MockedToken[] memory mockedTokens = abi.decode(
                    deploymentConfig.parseRaw(".miniPoolReserversConfig"), (MockedToken[])
                );

                require(
                    mockedTokens.length == miniPoolReserversConfig.length, "Wrong config in Json"
                );
                string[] memory symbols = new string[](miniPoolReserversConfig.length);
                uint8[] memory decimals = new uint8[](miniPoolReserversConfig.length);
                int256[] memory prices = new int256[](miniPoolReserversConfig.length);

                for (uint8 idx = 0; idx < miniPoolReserversConfig.length; idx++) {
                    symbols[idx] = mockedTokens[idx].symbol;
                    decimals[idx] = uint8(mockedTokens[idx].decimals);
                    prices[idx] = int256(mockedTokens[idx].prices);
                }

                // Deployment
                console.log("Broadcasting....");
                vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
                (address[] memory tokens,) = _deployERC20Mocks(symbols, symbols, decimals, prices);
                vm.stopBroadcast();

                for (uint8 idx = 0; idx < miniPoolReserversConfig.length; idx++) {
                    miniPoolReserversConfig[idx].tokenAddress = address(tokens[idx]);
                }
            }

            /* Reconfigure */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            address mp =
                contracts.miniPoolAddressesProvider.getMiniPool(poolAddressesProviderConfig.poolId);
            _configureMiniPoolReserves(contracts, miniPoolReserversConfig, mp);
            vm.stopBroadcast();
        } else if (vm.envBool("MAINNET")) {
            console.log("Mainnet Deployment");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            /* Read necessary lending pool infra contracts */
            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            contracts.aTokensAndRatesHelper =
                ATokensAndRatesHelper(deploymentConfig.readAddress(".aTokensAndRatesHelper"));

            /* Reconfigure */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            _configureReserves(contracts, lendingPoolReserversConfig);
            vm.stopBroadcast();

            /* *********** Mini pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/2_MiniPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            /* Read necessary mini pool infra contracts */
            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                deploymentConfig.readAddress(".miniPoolAddressesProvider")
            );
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(deploymentConfig.readAddress(".miniPoolConfigurator"));

            /* Reconfigure */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            address mp =
                contracts.miniPoolAddressesProvider.getMiniPool(poolAddressesProviderConfig.poolId);
            _configureMiniPoolReserves(contracts, miniPoolReserversConfig, mp);
            vm.stopBroadcast();
        } else {
            console.log("No deployment type selected in .env");
        }
    }
}
