// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.sol";
import "./helpers/TransferOwnershipHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";

contract TransferOwnerships is Script, TransferOwnershipHelper, Test {
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

        if (vm.envBool("TESTNET")) {
            console.log("Testnet");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/1_LendingPoolContracts.json");
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
            contracts.cod3xLendDataProvider =
                Cod3xLendDataProvider(deploymentConfig.readAddress(".cod3xLendDataProvider"));

            /* *********** Mini pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/2_MiniPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                deploymentConfig.readAddress(".miniPoolAddressesProvider")
            );

            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(deploymentConfig.readAddress(".miniPoolConfigurator"));

            /* *********** Strategies *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/3_DeployedStrategies.json");
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
                    string.concat(root, "/scripts/outputs/testnet/6_ChangePeripherials.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.rewarder = Rewarder(deploymentConfig.readAddress(".rewarder"));
            contracts.rewarder6909 = Rewarder6909(deploymentConfig.readAddress(".rewarder6909"));

            address dataProviderAddress = deploymentConfig.readAddress(".cod3xLendDataProvider");
            if (dataProviderAddress != address(0)) {
                contracts.cod3xLendDataProvider = Cod3xLendDataProvider(dataProviderAddress);
            }

            require(address(contracts.rewarder) != address(0), "Rewarder's address is 0");
            require(address(contracts.rewarder6909) != address(0), "Rewarder6909's address is 0");

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
                    string.concat(root, "/scripts/outputs/mainnet/1_LendingPoolContracts.json");
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
            contracts.cod3xLendDataProvider =
                Cod3xLendDataProvider(deploymentConfig.readAddress(".cod3xLendDataProvider"));

            /* *********** Mini pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/2_MiniPoolContracts.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                deploymentConfig.readAddress(".miniPoolAddressesProvider")
            );

            /* *********** Strategies *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/3_DeployedStrategies.json");
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
                    string.concat(root, "/scripts/outputs/mainnet/6_ChangePeripherials.json");
                console.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }
            contracts.rewarder = Rewarder(deploymentConfig.readAddress(".rewarder"));
            contracts.rewarder6909 = Rewarder6909(deploymentConfig.readAddress(".rewarder6909"));

            address dataProviderAddress = deploymentConfig.readAddress(".cod3xLendDataProvider");
            if (dataProviderAddress != address(0)) {
                contracts.cod3xLendDataProvider = Cod3xLendDataProvider(dataProviderAddress);
            }

            require(address(contracts.rewarder) != address(0), "Rewarder's address is 0");
            require(address(contracts.rewarder6909) != address(0), "Rewarder6909's address is 0");

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
