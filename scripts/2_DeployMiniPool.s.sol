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

    address WETH_ARB = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function writeJsonData(string memory root, string memory path) internal {
        /* Write important contracts into the file */
        vm.serializeAddress("miniPoolContracts", "miniPoolImpl", address(contracts.miniPoolImpl));
        vm.serializeAddress(
            "miniPoolContracts",
            "miniPoolAddressesProvider",
            address(contracts.miniPoolAddressesProvider)
        );
        vm.serializeAddress("miniPoolContracts", "flowLimiter", address(contracts.flowLimiter));
        vm.serializeAddress(
            "miniPoolContracts",
            "miniPoolVolatileStrategy",
            address(contracts.miniPoolVolatileStrategy)
        );
        vm.serializeAddress(
            "miniPoolContracts", "miniPoolStableStrategy", address(contracts.miniPoolStableStrategy)
        );

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
        LinearStrategy memory volatileStrategy =
            abi.decode(deploymentConfig.parseRaw(".volatileStrategy"), (LinearStrategy));
        LinearStrategy memory stableStrategy =
            abi.decode(deploymentConfig.parseRaw(".stableStrategy"), (LinearStrategy));

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
                volatileStrategy,
                stableStrategy,
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
                volatileStrategy,
                stableStrategy,
                poolReserversConfig,
                poolAddressesProviderConfig.poolId,
                vm.addr(vm.envUint("PRIVATE_KEY"))
            );
            vm.stopBroadcast();
            writeJsonData(root, path);
        } else if (vm.envOr("MAINNET", false)) {
            //deploy to mainnet
            // /* Fork Identifier [ARBITRUM] */
            // string memory RPC = vm.envString(vm.envString("LOCAL_FORK"));
            // uint256 FORK_BLOCK = 257827379;
            // uint256 arbFork;
            // arbFork = vm.createSelectFork(RPC, FORK_BLOCK);

            // /* Config fetching */
            // string memory root = vm.projectRoot();
            // string memory path = string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
            // console.log("PATH: ", path);
            // string memory deploymentConfig = vm.readFile(path);
            // address lendingPool = deploymentConfig.readAddress(".lendingPool");
            // address protocolDataProvider = deploymentConfig.readAddress(".protocolDataProvider");
            // address lendingPoolAddressesProvider =
            //     deploymentConfig.readAddress(".lendingPoolAddressesProvider");
            // address treasury = deploymentConfig.readAddress(".treasury");
            // address rewarder = deploymentConfig.readAddress(".rewarder");
            // address aTokenErc6909 = deploymentConfig.readAddress(".aTokenErc6909");

            // /* Deployment */
            // vm.startPrank(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
            // deployMiniPoolInfra(
            //     volatileStrategy,
            //     stableStrategy,
            //     poolReserversConfig,
            //     address(contracts.lendingPoolAddressesProvider),
            //     address(contracts.lendingPool),
            //     address(contracts.aTokenErc6909),
            //     poolAddressesProviderConfig.poolId,
            //     0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
            // );

            // /* Write important contracts into the file */
            // vm.serializeAddress("contracts", "miniPoolImpl", address(contracts.miniPoolImpl));
            // vm.serializeAddress(
            //     "contracts",
            //     "miniPoolAddressesProvider",
            //     address(contracts.miniPoolAddressesProvider)
            // );
            // vm.serializeAddress("contracts", "flowLimiter", address(contracts.flowLimiter));

            // string memory output = vm.serializeAddress(
            //     "contracts", "miniPoolConfigurator", address(contracts.miniPoolConfigurator)
            // );

            // vm.writeJson(output, "./scripts/outputs/2_MiniPoolContracts.json");

            // path = string.concat(root, "/scripts/outputs/2_MiniPoolContracts.json");
            // console.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);

            // vm.stopPrank();
        } else {
            console.log("HERE 4");
            //deploy to a local node
        }
        return contracts;
    }
}
