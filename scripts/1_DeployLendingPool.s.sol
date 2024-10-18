// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";

contract DeployLendingPool is Script, DeploymentUtils, Test {
    using stdJson for string;

    address WETH_ARB = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function writeJsonData(string memory root, string memory path) internal {
        vm.serializeAddress("lendingPoolContracts", "oracle", address(contracts.oracle));
        vm.serializeAddress("lendingPoolContracts", "rewarder", address(contracts.rewarder));
        vm.serializeAddress("lendingPoolContracts", "treasury", address(contracts.treasury));
        {
            address[] memory stableAddresses = new address[](contracts.stableStrategies.length);
            for (uint256 idx = 0; idx < contracts.stableStrategies.length; idx++) {
                stableAddresses[idx] = address(contracts.stableStrategies[idx]);
            }
            vm.serializeAddress("lendingPoolContracts", "stableStrategies", stableAddresses);
        }
        {
            address[] memory volatileAddresses = new address[](contracts.stableStrategies.length);
            for (uint256 idx = 0; idx < contracts.volatileStrategies.length; idx++) {
                volatileAddresses[idx] = address(contracts.volatileStrategies[idx]);
            }
            vm.serializeAddress("lendingPoolContracts", "volatileStrategies", volatileAddresses);
        }
        {
            address[] memory piAddresses = new address[](contracts.piStrategies.length);
            for (uint256 idx = 0; idx < contracts.piStrategies.length; idx++) {
                piAddresses[idx] = address(contracts.piStrategies[idx]);
            }
            vm.serializeAddress("lendingPoolContracts", "piStrategies", piAddresses);
        }
        vm.serializeAddress(
            "lendingPoolContracts", "protocolDataProvider", address(contracts.protocolDataProvider)
        );
        vm.serializeAddress(
            "lendingPoolContracts",
            "aTokensAndRatesHelper",
            address(contracts.aTokensAndRatesHelper)
        );
        vm.serializeAddress(
            "lendingPoolContracts", "aTokenErc6909", address(contracts.aTokenErc6909)
        );
        vm.serializeAddress("lendingPoolContracts", "aToken", address(contracts.aToken));
        vm.serializeAddress(
            "lendingPoolContracts", "variableDebtToken", address(contracts.variableDebtToken)
        );

        vm.serializeAddress("lendingPoolContracts", "lendingPool", address(contracts.lendingPool));
        vm.serializeAddress(
            "lendingPoolContracts",
            "lendingPoolAddressesProvider",
            address(contracts.lendingPoolAddressesProvider)
        );
        vm.serializeAddress(
            "lendingPoolContracts",
            "lendingPoolCollateralManager",
            address(contracts.lendingPoolCollateralManager)
        );
        string memory output = vm.serializeAddress(
            "lendingPoolContracts",
            "lendingPoolConfigurator",
            address(contracts.lendingPoolConfigurator)
        );

        vm.writeJson(output, "./scripts/outputs/1_LendingPoolContracts.json");

        path = string.concat(root, "/scripts/1_LendingPoolContracts.json");

        console.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);
    }

    function run() external returns (DeployedContracts memory) {
        console.log("1_DeployLendingPool");
        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/1_DeploymentConfig.json");
        console.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);
        General memory general = abi.decode(deploymentConfig.parseRaw(".general"), (General));

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
            // Fork Identifier [ARBITRUM]
            string memory RPC = vm.envString("ARBITRUM_RPC_URL");
            uint256 FORK_BLOCK = 257827379;
            uint256 arbFork;
            arbFork = vm.createSelectFork(RPC, FORK_BLOCK);

            // Deployment
            vm.startPrank(FOUNDRY_DEFAULT);
            deployLendingPoolInfra(
                general,
                oracleConfig,
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolAddressesProviderConfig,
                poolReserversConfig,
                WETH_ARB,
                FOUNDRY_DEFAULT
            );
            vm.stopPrank();
            writeJsonData(root, path);

            /* Write important contracts into the file */
        } else if (vm.envBool("TESTNET")) {
            console.log("Testnet Deployment");
            /* Read all mocks deployed */
            string memory path = string.concat(root, "/scripts/outputs/0_MockedTokens.json");
            console.log("PATH: ", path);
            string memory config = vm.readFile(path);
            address[] memory mockedTokens = config.readAddressArray(".mockedTokens");

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
            /* Deploy to testnet */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console.log("Deploying lending pool infra");
            deployLendingPoolInfra(
                general,
                oracleConfig,
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolAddressesProviderConfig,
                poolReserversConfig,
                WETH_ARB,
                vm.addr(vm.envUint("PRIVATE_KEY"))
            );
            vm.stopBroadcast();

            /* Write data */
            writeJsonData(root, path);
        } else if (vm.envBool("MAINNET")) {
            console.log("Mainnet Deployment");

            /* Deploy to the mainnet */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            deployLendingPoolInfra(
                general,
                oracleConfig,
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolAddressesProviderConfig,
                poolReserversConfig,
                WETH_ARB,
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
