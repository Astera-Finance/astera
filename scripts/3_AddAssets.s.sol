// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {DeployMiniPool} from "./2_DeployMiniPool.s.sol";

contract AddAssets is Script, DeploymentUtils, Test {
    using stdJson for string;

    address WETH_ARB = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function run() external returns (DeployedContracts memory) {
        //vm.startBroadcast(vm.envUint("DEPLOYER"));

        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/3_AssetsToAdd.json");
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
            /* Fork Identifier [ARBITRUM] */
            string memory RPC = vm.envString("ARBITRUM_RPC_URL");
            uint256 FORK_BLOCK = 257827379;
            uint256 arbFork;
            arbFork = vm.createSelectFork(RPC, FORK_BLOCK);

            /* Config fetching */
            DeployMiniPool deployMiniPool = new DeployMiniPool();
            contracts = deployMiniPool.run();

            vm.startPrank(FOUNDRY_DEFAULT);
            _initAndConfigureReserves(contracts, lendingPoolReserversConfig, general, oracleConfig);
            _initAndConfigureMiniPoolReserves(
                contracts, miniPoolReserversConfig, poolAddressesProviderConfig.poolId, oracleConfig
            );
            vm.stopPrank();
        } else if (vm.envBool("TESTNET")) {
            //Lending pool settings
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.stableStrategy =
                DefaultReserveInterestRateStrategy(deploymentConfig.readAddress(".stableStrategy"));
            contracts.volatileStrategy = DefaultReserveInterestRateStrategy(
                deploymentConfig.readAddress(".volatileStrategy")
            );
            contracts.aToken = AToken(deploymentConfig.readAddress(".aToken"));
            contracts.variableDebtToken =
                VariableDebtToken(deploymentConfig.readAddress(".variableDebtToken"));
            contracts.treasury = Treasury(deploymentConfig.readAddress(".treasury"));
            contracts.rewarder = Rewarder(deploymentConfig.readAddress(".rewarder"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(deploymentConfig.readAddress(".lendingPoolConfigurator"));
            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            contracts.aTokensAndRatesHelper =
                ATokensAndRatesHelper(deploymentConfig.readAddress(".aTokensAndRatesHelper"));

            /* Mocked tokens deployment */
            {
                deploymentConfig = vm.readFile(path);
                MockedToken[] memory mockedTokens = abi.decode(
                    deploymentConfig.parseRaw(".lendingPoolMockedToken"), (MockedToken[])
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
            contracts.miniPoolVolatileStrategy = MiniPoolDefaultReserveInterestRateStrategy(
                deploymentConfig.readAddress(".miniPoolVolatileStrategy")
            );

            contracts.miniPoolStableStrategy = MiniPoolDefaultReserveInterestRateStrategy(
                deploymentConfig.readAddress(".miniPoolStableStrategy")
            );
            /* Mocked token deployment */
            {
                deploymentConfig = vm.readFile(path);
                MockedToken[] memory mockedTokens =
                    abi.decode(deploymentConfig.parseRaw(".miniPoolMockedToken"), (MockedToken[]));

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

            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console.log("Configuration ");
            _initAndConfigureMiniPoolReserves(
                contracts, miniPoolReserversConfig, poolAddressesProviderConfig.poolId, oracleConfig
            );
            vm.stopBroadcast();
        }
        return contracts;
    }
}
