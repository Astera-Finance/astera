// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.sol";
import "./helpers/TransferOwnershipHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console2.sol";

contract TransferOwnerships is Script, TransferOwnershipHelper, Test {
    using stdJson for string;

    function _checkOwnerships(MiniPoolRole memory miniPoolRole, bool transferMiniPoolRole)
        internal
    {
        assertEq(
            contracts.miniPoolAddressesProvider.getLendingPoolAddressesProvider(),
            address(contracts.lendingPoolAddressesProvider),
            "AddressesProviders are different between mini pool and main pool. Did you run 1 and 2 scripts ?"
        );

        assertNotEq(
            contracts.asteraLendDataProvider.owner(),
            vm.addr(vm.envUint("PRIVATE_KEY")),
            "Owner of data provider is still local address"
        );
        assertNotEq(
            contracts.lendingPoolAddressesProvider.owner(),
            vm.addr(vm.envUint("PRIVATE_KEY")),
            "Owner of address provider is still local address"
        );
        assertNotEq(
            contracts.lendingPoolAddressesProvider.getEmergencyAdmin(),
            vm.addr(vm.envUint("PRIVATE_KEY")),
            "Emergency admin of lendingPoolAddressesProvider is still local address"
        );
        assertNotEq(
            contracts.lendingPoolAddressesProvider.getPoolAdmin(),
            vm.addr(vm.envUint("PRIVATE_KEY")),
            "Pool admin of lendingPoolAddressesProvider is still local address"
        );
        assertNotEq(
            contracts.oracle.owner(),
            vm.addr(vm.envUint("PRIVATE_KEY")),
            "Owner of oracle is still local address"
        );
        assertNotEq(
            contracts.wethGateway.owner(),
            vm.addr(vm.envUint("PRIVATE_KEY")),
            "Owner of wethGateway is still local address"
        );
        assertNotEq(
            contracts.miniPoolAddressesProvider.owner(),
            vm.addr(vm.envUint("PRIVATE_KEY")),
            "Owner of miniPoolAddressesProvider is still local address"
        );
        assertNotEq(
            contracts.rewarder.owner(),
            vm.addr(vm.envUint("PRIVATE_KEY")),
            "Owner of rewarder is still local address"
        );
        assertNotEq(
            contracts.rewarder6909.owner(),
            vm.addr(vm.envUint("PRIVATE_KEY")),
            "Owner of rewarder6909 is still local address"
        );
        assertNotEq(
            contracts.miniPoolAddressesProvider.getMainPoolAdmin(),
            vm.addr(vm.envUint("PRIVATE_KEY")),
            "Main admin pool of miniPoolAddressesProvider is still local address"
        );

        if (transferMiniPoolRole) {
            assertNotEq(
                contracts.miniPoolAddressesProvider.getPoolAdmin(miniPoolRole.miniPoolId),
                vm.addr(vm.envUint("PRIVATE_KEY")),
                "Admin pool of miniPoolAddressesProvider is still local address"
            );
        }

        for (uint8 idx = 0; idx < contracts.piStrategies.length; idx++) {
            assertNotEq(
                contracts.piStrategies[idx].owner(),
                vm.addr(vm.envUint("PRIVATE_KEY")),
                "Pi strategy owner is still local address"
            );
        }
        for (uint8 idx = 0; idx < contracts.miniPoolPiStrategies.length; idx++) {
            assertNotEq(
                contracts.miniPoolPiStrategies[idx].owner(),
                vm.addr(vm.envUint("PRIVATE_KEY")),
                "Mini pool pi strategy owner is still local address"
            );
        }
    }

    function run() external returns (DeployedContracts memory) {
        console2.log("7_TransferOwnerships");
        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/7_TransferOwnerships.json");
        console2.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);

        bool transferMiniPoolRole = deploymentConfig.readBool(".transferMiniPoolRole");
        Roles memory roles = abi.decode(deploymentConfig.parseRaw(".roles"), (Roles));
        MiniPoolRole memory miniPoolRole =
            abi.decode(deploymentConfig.parseRaw(".miniPoolRole"), (MiniPoolRole));

        if (!vm.envBool("MAINNET")) {
            console2.log("Testnet");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/1_LendingPoolContracts.json");
                console2.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );
            // contracts.treasury = Treasury(deploymentConfig.readAddress(".treasury"));
            contracts.oracle = Oracle(deploymentConfig.readAddress(".oracle"));
            contracts.asteraLendDataProvider =
                AsteraLendDataProvider(deploymentConfig.readAddress(".asteraLendDataProvider"));
            contracts.wethGateway =
                WETHGateway(payable(deploymentConfig.readAddress(".wethGateway")));

            /* *********** Mini pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/2_MiniPoolContracts.json");
                console2.log("PATH: ", outputPath);
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
                console2.log("PATH: ", outputPath);
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
                console2.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.rewarder = Rewarder(deploymentConfig.readAddress(".rewarder"));
            contracts.rewarder6909 = Rewarder6909(deploymentConfig.readAddress(".rewarder6909"));

            address dataProviderAddress = deploymentConfig.readAddress(".asteraLendDataProvider");
            if (dataProviderAddress != address(0)) {
                contracts.asteraLendDataProvider = AsteraLendDataProvider(dataProviderAddress);
            }

            require(address(contracts.rewarder) != address(0), "Rewarder's address is 0");
            require(address(contracts.rewarder6909) != address(0), "Rewarder6909's address is 0");

            /* ***** Action ***** */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            if (transferMiniPoolRole) {
                console2.log("MiniPool ownership transfer");
                _transferMiniPoolOwnership(miniPoolRole);
            } else {
                console2.log("MainPool ownership transfer");
                _transferOwnershipsAndRenounceRoles(roles);
            }
            vm.stopBroadcast();
        } else if (vm.envBool("MAINNET")) {
            console2.log("Mainnet Deployment");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/1_LendingPoolContracts.json");
                console2.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
                deploymentConfig.readAddress(".lendingPoolAddressesProvider")
            );

            // contracts.treasury = Treasury(deploymentConfig.readAddress(".treasury"));
            contracts.oracle = Oracle(deploymentConfig.readAddress(".oracle"));
            contracts.asteraLendDataProvider =
                AsteraLendDataProvider(deploymentConfig.readAddress(".asteraLendDataProvider"));
            contracts.wethGateway =
                WETHGateway(payable(deploymentConfig.readAddress(".wethGateway")));

            /* *********** Mini pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/2_MiniPoolContracts.json");
                console2.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }

            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                deploymentConfig.readAddress(".miniPoolAddressesProvider")
            );

            /* *********** Strategies *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/3_DeployedStrategies.json");
                console2.log("PATH: ", outputPath);
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
                console2.log("PATH: ", outputPath);
                deploymentConfig = vm.readFile(outputPath);
            }
            contracts.rewarder = Rewarder(deploymentConfig.readAddress(".rewarder"));
            contracts.rewarder6909 = Rewarder6909(deploymentConfig.readAddress(".rewarder6909"));

            address dataProviderAddress = deploymentConfig.readAddress(".asteraLendDataProvider");
            if (dataProviderAddress != address(0)) {
                contracts.asteraLendDataProvider = AsteraLendDataProvider(dataProviderAddress);
            }

            require(address(contracts.rewarder) != address(0), "Rewarder's address is 0");
            require(address(contracts.rewarder6909) != address(0), "Rewarder6909's address is 0");

            /* ***** Action ***** */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            if (transferMiniPoolRole) {
                console2.log("MiniPool ownership transfer");
                _transferMiniPoolOwnership(miniPoolRole);
            } else {
                console2.log("MainPool ownership transfer");
                _transferOwnershipsAndRenounceRoles(roles);
            }
            vm.stopBroadcast();
        } else {
            console2.log("No deployment type selected in .env");
        }
        _checkOwnerships(miniPoolRole, transferMiniPoolRole);
    }
}
