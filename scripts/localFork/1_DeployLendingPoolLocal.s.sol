// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../DeployDataTypes.sol";
import "../helpers/LendingPoolHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";

contract DeployLendingPoolLocal is Script, LendingPoolHelper, Test {
    using stdJson for string;

    function writeJsonData(string memory root, string memory path) internal {
        vm.serializeAddress("lendingPoolContracts", "oracle", address(contracts.oracle));
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

        (,, address[] memory aTokens, address[] memory debtTokens) =
            contracts.cod3xLendDataProvider.getAllLpTokens();

        vm.serializeAddress("lendingPoolContracts", "aTokens", aTokens);

        {
            address[] memory wrappedTokens = new address[](aTokens.length);
            for (uint256 idx = 0; idx < aTokens.length; idx++) {
                wrappedTokens[idx] = AToken(aTokens[idx]).WRAPPER_ADDRESS();
            }
            vm.serializeAddress("lendingPoolContracts", "wrappedTokens", wrappedTokens);
        }

        // vm.serializeAddress("lendingPoolContracts", "aTokensWrappers", AToken(aTokens))
        vm.serializeAddress("lendingPoolContracts", "wethGateway", address(contracts.wethGateway));
        vm.serializeAddress("lendingPoolContracts", "debtTokens", debtTokens);
        vm.serializeAddress("lendingPoolContracts", "aTokenImpl", address(contracts.aToken));
        vm.serializeAddress(
            "lendingPoolContracts", "variableDebtTokenImpl", address(contracts.variableDebtToken)
        );

        vm.serializeAddress(
            "lendingPoolContracts",
            "cod3xLendDataProvider",
            address(contracts.cod3xLendDataProvider)
        );
        vm.serializeAddress(
            "lendingPoolContracts",
            "aTokensAndRatesHelper",
            address(contracts.aTokensAndRatesHelper)
        );
        vm.serializeAddress(
            "lendingPoolContracts",
            "lendingPool",
            contracts.lendingPoolAddressesProvider.getLendingPool()
        );
        vm.serializeAddress(
            "lendingPoolContracts",
            "lendingPoolAddressesProvider",
            address(contracts.lendingPoolAddressesProvider)
        );
        string memory output = vm.serializeAddress(
            "lendingPoolContracts",
            "lendingPoolConfigurator",
            address(contracts.lendingPoolConfigurator)
        );

        vm.writeJson(output, "./scripts/localFork/outputs/1_LendingPoolContracts.json");

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

        address wethGateway = deploymentConfig.readAddress(".wethGateway");

        // Fork Identifier
        string memory RPC = vm.envString("BASE_RPC_URL");
        uint256 FORK_BLOCK = 26631073;
        uint256 fork;
        fork = vm.createSelectFork(RPC, FORK_BLOCK);

        // Deployment
        vm.startPrank(FOUNDRY_DEFAULT);
        for (uint8 idx = 0; idx < poolReserversConfig.length; idx++) {
            deal(poolReserversConfig[idx].tokenAddress, FOUNDRY_DEFAULT, 100 ether);
        }

        contracts.oracle = _deployOracle(oracleConfig);
        deployLendingPoolInfra(
            general,
            volatileStrategies,
            stableStrategies,
            piStrategies,
            poolReserversConfig,
            oracleConfig,
            FOUNDRY_DEFAULT,
            wethGateway
        );
        vm.stopPrank();

        /* Write data to json */
        writeJsonData(root, path);

        return contracts;
    }
}
