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

    function readPreviousDeployments(string memory root) internal returns (bool readPrevious) {
        string memory path = string.concat(root, "/scripts/outputs/2_MiniPoolContracts.json");
        console.log("PREVIOUS DEPLOYMENT PATH: ", path);
        try vm.readFile(path) returns (string memory previousContracts) {
            address[] memory tmpContracts;
            tmpContracts = previousContracts.readAddressArray(".miniPoolImpl");
            for (uint256 idx = 0; idx < tmpContracts.length; idx++) {
                contracts.miniPoolImpl.push(MiniPool(tmpContracts[idx]));
            }
            tmpContracts = previousContracts.readAddressArray(".aTokenErc6909");
            for (uint256 idx = 0; idx < tmpContracts.length; idx++) {
                contracts.aTokenErc6909.push(ATokenERC6909(tmpContracts[idx]));
            }
            tmpContracts = previousContracts.readAddressArray(".miniPoolPiStrategies");
            for (uint256 idx = 0; idx < tmpContracts.length; idx++) {
                contracts.miniPoolPiStrategies.push(
                    MiniPoolPiReserveInterestRateStrategy(tmpContracts[idx])
                );
            }
            tmpContracts = previousContracts.readAddressArray(".miniPoolStableStrategies");
            for (uint256 idx = 0; idx < tmpContracts.length; idx++) {
                contracts.miniPoolStableStrategies.push(
                    MiniPoolDefaultReserveInterestRateStrategy(tmpContracts[idx])
                );
            }
            tmpContracts = previousContracts.readAddressArray(".miniPoolVolatileStrategies");
            for (uint256 idx = 0; idx < tmpContracts.length; idx++) {
                contracts.miniPoolVolatileStrategies.push(
                    MiniPoolDefaultReserveInterestRateStrategy(tmpContracts[idx])
                );
            }
            contracts.flowLimiter = FlowLimiter(previousContracts.readAddress(".flowLimiter"));
            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                previousContracts.readAddress(".miniPoolAddressesProvider")
            );
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(previousContracts.readAddress(".miniPoolConfigurator"));

            return true;
        } catch {
            return false;
        }
    }

    function writeJsonData(string memory root, string memory path) internal {
        /* Write important contracts into the file */
        address[] memory contractAddresses = new address[](contracts.miniPoolImpl.length);
        for (uint256 idx = 0; idx < contracts.miniPoolImpl.length; idx++) {
            contractAddresses[idx] = address(contracts.miniPoolImpl[idx]);
        }
        vm.serializeAddress("miniPoolContracts", "miniPoolImpl", contractAddresses);
        contractAddresses = new address[](contracts.aTokenErc6909.length);
        for (uint256 idx = 0; idx < contracts.aTokenErc6909.length; idx++) {
            contractAddresses[idx] = address(contracts.aTokenErc6909[idx]);
        }
        vm.serializeAddress("miniPoolContracts", "aTokenErc6909", contractAddresses);
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
        console.log("2_DeployMiniPool");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/2_DeploymentConfig.json");
        console.log("PATH: ", path);
        string memory config = vm.readFile(path);

        PoolReserversConfig[] memory poolReserversConfig =
            abi.decode(config.parseRaw(".poolReserversConfig"), (PoolReserversConfig[]));
        LinearStrategy[] memory volatileStrategies =
            abi.decode(config.parseRaw(".volatileStrategies"), (LinearStrategy[]));
        LinearStrategy[] memory stableStrategies =
            abi.decode(config.parseRaw(".stableStrategies"), (LinearStrategy[]));

        PiStrategy[] memory piStrategies =
            abi.decode(config.parseRaw(".piStrategies"), (PiStrategy[]));

        OracleConfig memory oracleConfig =
            abi.decode(config.parseRaw(".oracleConfig"), (OracleConfig));

        bool usePreviousStrats = config.readBool(".usePreviousStrats");
        bool readPreviousContracts = config.readBool(".readPreviousContracts");

        if (vm.envBool("LOCAL_FORK")) {
            /* Fork Identifier */
            {
                string memory RPC = vm.envString("BASE_RPC_URL");
                uint256 FORK_BLOCK = 21838058;
                uint256 fork;
                fork = vm.createSelectFork(RPC, FORK_BLOCK);
            }

            /* Config fetching */
            DeployLendingPool deployLendingPool = new DeployLendingPool();
            contracts = deployLendingPool.run();

            /* Deployment */
            vm.startPrank(FOUNDRY_DEFAULT);
            contracts.oracle.setAssetSources(
                oracleConfig.assets, oracleConfig.sources, oracleConfig.timeouts
            );
            deployMiniPoolInfra(
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolReserversConfig,
                FOUNDRY_DEFAULT,
                false
            );
            vm.stopPrank();
        } else if (vm.envBool("TESTNET")) {
            console.log("Testnet Deployment");

            /* Read all mocks deployed */
            string memory path = string.concat(root, "/scripts/outputs/0_MockedTokens.json");
            console.log("PATH: ", path);
            string memory config = vm.readFile(path);
            address[] memory mockedTokens = config.readAddressArray(".mockedTokens");
            contracts.oracle = Oracle(config.readAddress(".mockedOracle"));
            if (readPreviousContracts) {
                readPreviousDeployments(root);
            }

            require(
                mockedTokens.length >= poolReserversConfig.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            {
                for (uint8 idx = 0; idx < poolReserversConfig.length; idx++) {
                    for (uint8 i = 0; i < mockedTokens.length; i++) {
                        if (
                            keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
                                == keccak256(abi.encodePacked(poolReserversConfig[idx].symbol))
                        ) {
                            poolReserversConfig[idx].tokenAddress = address(mockedTokens[i]);
                            piStrategies[idx].tokenAddress = address(mockedTokens[i]);
                            break;
                        }
                    }
                    require(
                        poolReserversConfig[idx].tokenAddress != address(0),
                        "Mocked token not assigned"
                    );
                }
            }

            /* Read all lending pool contracts deployed */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }

            contracts.lendingPoolAddressesProvider =
                LendingPoolAddressesProvider(config.readAddress(".lendingPoolAddressesProvider"));
            contracts.lendingPool = LendingPool(config.readAddress(".lendingPool"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(config.readAddress(".lendingPoolConfigurator"));
            contracts.cod3xLendDataProvider =
                Cod3xLendDataProvider(config.readAddress(".cod3xLendDataProvider"));

            /* Deploy on testnet */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console.log("Deploying lending pool infra");
            deployMiniPoolInfra(
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolReserversConfig,
                vm.addr(vm.envUint("PRIVATE_KEY")),
                usePreviousStrats
            );
            vm.stopBroadcast();
        } else if (vm.envBool("MAINNET")) {
            console.log("Mainnet Deployment");
            /* Get deployed lending pool infra dontracts */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }
            contracts.lendingPoolAddressesProvider =
                LendingPoolAddressesProvider(config.readAddress(".lendingPoolAddressesProvider"));
            contracts.lendingPool = LendingPool(config.readAddress(".lendingPool"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(config.readAddress(".lendingPoolConfigurator"));
            contracts.cod3xLendDataProvider =
                Cod3xLendDataProvider(config.readAddress(".cod3xLendDataProvider"));

            if (readPreviousContracts) {
                readPreviousDeployments(root);
            }

            /* Deploy on mainnet */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console.log("Getting oracle");
            contracts.oracle = Oracle(contracts.miniPoolAddressesProvider.getPriceOracle());
            contracts.oracle.setAssetSources(
                oracleConfig.assets, oracleConfig.sources, oracleConfig.timeouts
            );
            console.log("Deploying mini pool infra");
            deployMiniPoolInfra(
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolReserversConfig,
                vm.addr(vm.envUint("PRIVATE_KEY")),
                usePreviousStrats
            );
            vm.stopBroadcast();
        } else {
            console.log("No deployment type selected in .env");
        }
        /* Write important contracts into the file */
        writeJsonData(root, path);
        return contracts;
    }
}
