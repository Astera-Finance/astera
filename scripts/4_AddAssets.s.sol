// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {DeployMiniPool} from "./2_DeployMiniPool.s.sol";
import {AddStrats} from "./3_AddStrats.s.sol";

contract AddAssets is Script, DeploymentUtils, Test {
    using stdJson for string;

    DeployedContracts contractsWithStrats;

    function readAddressesToContracts(string memory root) public {
        string memory path = string.concat(root, "/scripts/outputs/3_DeployedStrategies.json");
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
        console.log("4_AddAssets");

        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/4_AssetsToAdd.json");
        console.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);

        General memory general = abi.decode(deploymentConfig.parseRaw(".general"), (General));

        PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
            deploymentConfig.parseRaw(".poolAddressesProviderConfig"), (PoolAddressesProviderConfig)
        );

        PoolReserversConfig[] memory lendingPoolReserversConfig = abi.decode(
            deploymentConfig.parseRaw(".lendingPoolReserversConfig"), (PoolReserversConfig[])
        );
        PoolReserversConfig[] memory miniPoolReserversConfig = abi.decode(
            deploymentConfig.parseRaw(".miniPoolReserversConfig"), (PoolReserversConfig[])
        );
        OracleConfig memory oracleConfig =
            abi.decode(deploymentConfig.parseRaw(".oracleConfig"), (OracleConfig));

        if (vm.envBool("LOCAL_FORK")) {
            console.log("Local fork deployment");
            /* Fork Identifier [ARBITRUM] */
            string memory RPC = vm.envString("ARBITRUM_RPC_URL");
            uint256 FORK_BLOCK = 257827379;
            uint256 arbFork;
            arbFork = vm.createSelectFork(RPC, FORK_BLOCK);

            /* Config fetching */
            DeployMiniPool deployMiniPool = new DeployMiniPool();
            contracts = deployMiniPool.run();
            AddStrats addStrats = new AddStrats();

            contracts = addStrats.run();

            vm.startPrank(FOUNDRY_DEFAULT);
            _initAndConfigureReserves(contracts, lendingPoolReserversConfig, general, oracleConfig);
            _initAndConfigureMiniPoolReserves(
                contracts, miniPoolReserversConfig, poolAddressesProviderConfig.poolId, oracleConfig
            );
            vm.stopPrank();
        } else if (vm.envBool("TESTNET")) {
            console.log("Testnet");

            /* Lending pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.aToken = AToken(deploymentConfig.readAddress(".aToken"));
            contracts.variableDebtToken =
                VariableDebtToken(deploymentConfig.readAddress(".variableDebtToken"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(deploymentConfig.readAddress(".lendingPoolConfigurator"));
            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            contracts.aTokensAndRatesHelper =
                ATokensAndRatesHelper(deploymentConfig.readAddress(".aTokensAndRatesHelper"));

            readAddressesToContracts(root);

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
                            oracleConfig.assets[idx] = address(mockedTokens[i]);
                            break;
                        }
                    }
                    require(
                        lendingPoolReserversConfig[idx].tokenAddress != address(0),
                        "Mocked token not assigned"
                    );
                }
            }

            console.log("Init and configuration");
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            _initAndConfigureReserves(contracts, lendingPoolReserversConfig, general, oracleConfig);
            vm.stopBroadcast();

            /* Mini pool settings */
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

            console.log("Mini pool init and configuration");
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console.log("Configuration ");
            _initAndConfigureMiniPoolReserves(
                contracts, miniPoolReserversConfig, poolAddressesProviderConfig.poolId, oracleConfig
            );
            vm.stopBroadcast();
        } else if (vm.envBool("MAINNET")) {
            console.log("Mainnet");
            /* Lending pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            /* Ready lending pool contracts settings */
            contracts.aToken = AToken(deploymentConfig.readAddress(".aToken"));
            contracts.variableDebtToken =
                VariableDebtToken(deploymentConfig.readAddress(".variableDebtToken"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(deploymentConfig.readAddress(".lendingPoolConfigurator"));
            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            contracts.aTokensAndRatesHelper =
                ATokensAndRatesHelper(deploymentConfig.readAddress(".aTokensAndRatesHelper"));

            readAddressesToContracts(root);

            /* Configure reserve */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            _initAndConfigureReserves(contracts, lendingPoolReserversConfig, general, oracleConfig);
            vm.stopBroadcast();

            /* Mini pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/2_MiniPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }
            /* Ready mini pool contracts settings */
            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                deploymentConfig.readAddress(".miniPoolAddressesProvider")
            );
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(deploymentConfig.readAddress(".miniPoolConfigurator"));

            /* Configuration */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console.log("Configuration ");
            _initAndConfigureMiniPoolReserves(
                contracts, miniPoolReserversConfig, poolAddressesProviderConfig.poolId, oracleConfig
            );
            vm.stopBroadcast();
        } else {
            console.log("No deployment type selected in .env");
        }
        return contracts;
    }
}
