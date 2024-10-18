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

contract TransferOwnerships is Script, DeploymentUtils, Test {
    using stdJson for string;

    function run() external returns (DeployedContracts memory) {
        console.log("7_TransferOwnerships");
        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/7_TransferOwnerships.json");
        console.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);

        Roles memory roles = abi.decode(deploymentConfig.parseRaw(".roles"), (Roles));

        if (vm.envBool("LOCAL_FORK")) {
            /* Fork Identifier [ARBITRUM] */
            string memory RPC = vm.envString("ARBITRUM_RPC_URL");
            uint256 FORK_BLOCK = 257827379;
            uint256 arbFork;
            arbFork = vm.createSelectFork(RPC, FORK_BLOCK);

            /* Config fetching */
            AddAssets reconfigure = new AddAssets();
            contracts = reconfigure.run();

            vm.startPrank(FOUNDRY_DEFAULT);
            _transferOwnershipsAndRenounceRoles(roles);
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
            contracts.rewarder = Rewarder(deploymentConfig.readAddress(".rewarder"));
            contracts.treasury = Treasury(deploymentConfig.readAddress(".treasury"));
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

            /* ***** Action ***** */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            _transferOwnershipsAndRenounceRoles(roles);
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
            contracts.rewarder = Rewarder(deploymentConfig.readAddress(".rewarder"));
            contracts.treasury = Treasury(deploymentConfig.readAddress(".treasury"));

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

            /* ***** Action ***** */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            _transferOwnershipsAndRenounceRoles(roles);
            vm.stopBroadcast();
        } else {
            console.log("No deployment type selected in .env");
        }
    }
}
