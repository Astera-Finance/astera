// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {AddAssets} from "./4_AddAssets.s.sol";

contract Reconfigure is Script, DeploymentUtils, Test {
    using stdJson for string;

    function run() external returns (DeployedContracts memory) {
        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/5_Reconfigure.json");
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

        // path = string.concat(root, "/scripts/outputs/3_DeployedStrategies.json");
        // console.log("PATH: ", path);
        // deploymentConfig = vm.readFile(path);

        // address[] memory stableStrats = deploymentConfig.readAddressArray(".stableStrats");
        // address[] memory volatileStrats = deploymentConfig.readAddressArray(".volatileStrategies");
        // address[] memory piStrats = deploymentConfig.readAddressArray(".stableStrats");

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
            _changeStrategies(contracts, lendingPoolReserversConfig);

            address mp =
                contracts.miniPoolAddressesProvider.getMiniPool(poolAddressesProviderConfig.poolId);
            _configureMiniPoolReserves(contracts, miniPoolReserversConfig, mp);
            _changeMiniPoolStrategies(contracts, miniPoolReserversConfig, mp);

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

            /* Read all mocks deployed */
            string memory path = string.concat(root, "/scripts/outputs/0_MockedTokens.json");
            console.log("PATH: ", path);
            string memory config = vm.readFile(path);
            address[] memory mockedTokens = config.readAddressArray(".mockedTokens");

            require(
                mockedTokens.length >= lendingPoolReserversConfig.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            {
                for (uint8 idx = 0; idx < lendingPoolReserversConfig.length; idx++) {
                    for (uint8 i = 0; i < mockedTokens.length; i++) {
                        if (
                            keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
                                == keccak256(abi.encodePacked(lendingPoolReserversConfig[idx].symbol))
                        ) {
                            lendingPoolReserversConfig[idx].tokenAddress = address(mockedTokens[i]);
                            break;
                        }
                    }
                    require(
                        lendingPoolReserversConfig[idx].tokenAddress != address(0),
                        "Mocked token not assigned"
                    );
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

            /* Mini pool mocks assignment */
            require(
                mockedTokens.length >= miniPoolReserversConfig.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            {
                for (uint8 idx = 0; idx < miniPoolReserversConfig.length; idx++) {
                    for (uint8 i = 0; i < mockedTokens.length; i++) {
                        if (
                            keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
                                == keccak256(abi.encodePacked(miniPoolReserversConfig[idx].symbol))
                        ) {
                            miniPoolReserversConfig[idx].tokenAddress = address(mockedTokens[i]);
                            break;
                        }
                    }
                    require(
                        miniPoolReserversConfig[idx].tokenAddress != address(0),
                        "Mocked token not assigned"
                    );
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
