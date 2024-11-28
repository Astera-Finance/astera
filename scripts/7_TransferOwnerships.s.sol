// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {ChangePeripherials} from "./6_ChangePeripherials.s.sol";

contract TransferOwnerships is Script, DeploymentUtils, Test {
    using stdJson for string;

    function run() external returns (DeployedContracts memory) {
        console.log("7_TransferOwnerships");
        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/7_TransferOwnerships.json");
        console.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);

        bool transferMiniPoolRole = deploymentConfig.readBool(".transferMiniPoolRole");
        Roles memory roles = abi.decode(deploymentConfig.parseRaw(".roles"), (Roles));
        MiniPoolRole memory miniPoolRole =
            abi.decode(deploymentConfig.parseRaw(".miniPoolRole"), (MiniPoolRole));

        if (vm.envBool("LOCAL_FORK")) {
            /* Fork Identifier */
            string memory RPC = vm.envString("BASE_RPC_URL");
            uint256 FORK_BLOCK = 21838058;
            uint256 fork;
            fork = vm.createSelectFork(RPC, FORK_BLOCK);

            /* Config fetching */
            ChangePeripherials changePeripherials = new ChangePeripherials();
            contracts = changePeripherials.run();

            vm.startPrank(FOUNDRY_DEFAULT);
            if (transferMiniPoolRole) {
                console.log("MiniPool ownership transfer");
                _transferMiniPoolOwnership(miniPoolRole);
            } else {
                console.log("MainPool ownership transfer");
                _transferOwnershipsAndRenounceRoles(roles);
            }

            vm.stopPrank();
        } else if (vm.envBool("TESTNET")) {
            console.log("Testnet");
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

            // contracts.treasury = Treasury(deploymentConfig.readAddress(".treasury"));
            contracts.oracle = Oracle(deploymentConfig.readAddress(".oracle"));

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

            /* *********** Strategies *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/3_DeployedStrategies.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            address[] memory tmpStrats = deploymentConfig.readAddressArray(".miniPoolPiStrategies");
            delete contracts.miniPoolPiStrategies;
            for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
                contracts.miniPoolPiStrategies.push(
                    MiniPoolPiReserveInterestRateStrategy(tmpStrats[idx])
                );
            }

            tmpStrats = deploymentConfig.readAddressArray(".piStrategies");
            delete contracts.piStrategies;
            for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
                contracts.piStrategies.push(PiReserveInterestRateStrategy(tmpStrats[idx]));
            }

            /* *********** Peripherials *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/6_DeployedPeripherials.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }
            contracts.rewarder = Rewarder(deploymentConfig.readAddress(".rewarder"));
            contracts.rewarder6909 = Rewarder6909(deploymentConfig.readAddress(".rewarder6909"));

            /* ***** Action ***** */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            if (transferMiniPoolRole) {
                console.log("MiniPool ownership transfer");
                _transferMiniPoolOwnership(miniPoolRole);
            } else {
                console.log("MainPool ownership transfer");
                _transferOwnershipsAndRenounceRoles(roles);
            }
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

            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            contracts.aTokensAndRatesHelper =
                ATokensAndRatesHelper(deploymentConfig.readAddress(".aTokensAndRatesHelper"));

            // contracts.treasury = Treasury(deploymentConfig.readAddress(".treasury"));
            contracts.oracle = Oracle(deploymentConfig.readAddress(".oracle"));

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

            /* *********** Strategies *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/3_DeployedStrategies.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            address[] memory tmpStrats = deploymentConfig.readAddressArray(".miniPoolPiStrategies");
            delete contracts.miniPoolPiStrategies;
            for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
                contracts.miniPoolPiStrategies.push(
                    MiniPoolPiReserveInterestRateStrategy(tmpStrats[idx])
                );
            }

            tmpStrats = deploymentConfig.readAddressArray(".piStrategies");
            delete contracts.piStrategies;
            for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
                contracts.piStrategies.push(PiReserveInterestRateStrategy(tmpStrats[idx]));
            }

            /* *********** Peripherials *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/6_DeployedPeripherials.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }
            contracts.rewarder = Rewarder(deploymentConfig.readAddress(".rewarder"));
            contracts.rewarder6909 = Rewarder6909(deploymentConfig.readAddress(".rewarder6909"));

            /* ***** Action ***** */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            if (transferMiniPoolRole) {
                console.log("MiniPool ownership transfer");
                _transferMiniPoolOwnership(miniPoolRole);
            } else {
                console.log("MainPool ownership transfer");
                _transferOwnershipsAndRenounceRoles(roles);
            }
            vm.stopBroadcast();
        } else {
            console.log("No deployment type selected in .env");
        }
    }
}
