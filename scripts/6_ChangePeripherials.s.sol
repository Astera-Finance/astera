// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.sol";
import "./helpers/ChangePeripherialsHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console2.sol";

import {DataTypes} from "../contracts/protocol/libraries/types/DataTypes.sol";
import {ERC4626Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC4626Mock.sol";

contract ChangePeripherials is Script, ChangePeripherialsHelper, Test {
    using stdJson for string;

    function writeJsonData(string memory path) internal {
        /* Write important contracts into the file */
        vm.serializeAddress(
            "peripherials", "asteraDataProvider", address(contracts.asteraDataProvider)
        );
        vm.serializeAddress("peripherials", "rewarder", address(contracts.rewarder));

        string memory output =
            vm.serializeAddress("peripherials", "rewarder6909", address(contracts.rewarder6909));

        vm.writeJson(output, path);

        console2.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);
    }

    function run() external returns (DeployedContracts memory) {
        console2.log("6_ChangePeripherials");
        // Config fetching
        // Providers
        string memory root = vm.projectRoot();

        // Inputs from Peripherials
        string memory path = string.concat(root, "/scripts/inputs/6_ChangePeripherials.json");
        console2.log("PATH: ", path);
        string memory config = vm.readFile(path);

        NewPeripherial[] memory vault = abi.decode(config.parseRaw(".vault"), (NewPeripherial[]));
        NewPeripherial[] memory treasury =
            abi.decode(config.parseRaw(".treasury"), (NewPeripherial[]));
        NewMiniPoolPeripherial memory miniPoolAsteraTreasury =
            abi.decode(config.parseRaw(".miniPoolAsteraTreasury"), (NewMiniPoolPeripherial));
        NewPeripherial[] memory rewarder =
            abi.decode(config.parseRaw(".rewarder"), (NewPeripherial[]));
        NewPeripherial[] memory rewarder6909 =
            abi.decode(config.parseRaw(".rewarder6909"), (NewPeripherial[]));

        Rehypothecation[] memory rehypothecation =
            abi.decode(config.parseRaw(".rehypothecation"), (Rehypothecation[]));

        uint256 miniPoolId = config.readUint(".miniPoolId");
        DataProvider memory asteraDataProvider =
            abi.decode(config.parseRaw(".asteraDataProvider"), (DataProvider));

        address profitHandler = config.readAddress(".profitHandler");

        require(treasury.length == rehypothecation.length, "Lengths settings must be the same");

        if (!vm.envBool("MAINNET")) {
            console2.log("Testnet");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/1_LendingPoolContracts.json");
                console2.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }

            contracts.lendingPool = LendingPool(config.readAddress(".lendingPool"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(config.readAddress(".lendingPoolConfigurator"));
            contracts.lendingPoolAddressesProvider =
                LendingPoolAddressesProvider(config.readAddress(".lendingPoolAddressesProvider"));

            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/2_MiniPoolContracts.json");
                config = vm.readFile(outputPath);
            }

            contracts.miniPoolAddressesProvider =
                MiniPoolAddressesProvider(config.readAddress(".miniPoolAddressesProvider"));
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(config.readAddress(".miniPoolConfigurator"));

            /* Read all mocks deployed */
            path = string.concat(root, "/scripts/outputs/testnet/0_MockedTokens.json");
            console2.log("PATH: ", path);
            config = vm.readFile(path);
            address[] memory mockedTokens = config.readAddressArray(".mockedTokens");

            require(
                mockedTokens.length >= vault.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            {
                // for (uint8 idx = 0; idx < vault.length; idx++) {
                //     for (uint8 i = 0; i < mockedTokens.length; i++) {
                //         if (
                //             keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
                //                 == keccak256(abi.encodePacked(vault[idx].symbol))
                //         ) {
                //             console2.log(
                //                 "Assigning %s instead of %s",
                //                 address(mockedTokens[i]),
                //                 vault[idx].tokenAddress
                //             );
                //             vault[idx].tokenAddress = address(mockedTokens[i]);
                //             rehypothecation[idx].tokenAddress = address(mockedTokens[i]);
                //             treasury[idx].tokenAddress = address(mockedTokens[i]);
                //             rewarder[idx].tokenAddress = address(mockedTokens[i]);
                //             rewarder6909[idx].tokenAddress = address(mockedTokens[i]);
                //             break;
                //         }
                //     }
                //     require(vault[idx].tokenAddress != address(0), "Mocked token not assigned");
                //     require(
                //         rehypothecation[idx].tokenAddress != address(0), "Mocked token not assigned"
                //     );
                //     require(treasury[idx].tokenAddress != address(0), "Mocked token not assigned");
                //     require(rewarder[idx].tokenAddress != address(0), "Mocked token not assigned");
                //     require(
                //         rewarder6909[idx].tokenAddress != address(0), "Mocked token not assigned"
                //     );
                // }
            }

            /* Change peripherials */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            for (uint8 idx = 0; idx < vault.length; idx++) {
                vault[idx].newAddress = address(new ERC4626Mock(vault[idx].tokenAddress));
            }
            _changePeripherials(
                treasury,
                miniPoolAsteraTreasury,
                vault,
                rewarder,
                rewarder6909,
                miniPoolId,
                profitHandler
            );
            _turnOnRehypothecation(rehypothecation);
            /* Data Provider */
            if (asteraDataProvider.deploy) {
                contracts.asteraDataProvider = new AsteraDataProvider2(
                    asteraDataProvider.networkBaseTokenAggregator,
                    asteraDataProvider.marketReferenceCurrencyAggregator
                );
                contracts.asteraDataProvider.setLendingPoolAddressProvider(
                    address(contracts.lendingPoolAddressesProvider)
                );
                contracts.asteraDataProvider.setMiniPoolAddressProvider(
                    address(contracts.miniPoolAddressesProvider)
                );
            }
            vm.stopBroadcast();
            path = string.concat(root, "/scripts/outputs/testnet/6_ChangePeripherials.json");
        } else if (vm.envBool("MAINNET")) {
            console2.log("Mainnet");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/1_LendingPoolContracts.json");
                console2.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }

            contracts.lendingPool = LendingPool(config.readAddress(".lendingPool"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(config.readAddress(".lendingPoolConfigurator"));

            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/2_MiniPoolContracts.json");
                config = vm.readFile(outputPath);
            }

            contracts.miniPoolAddressesProvider =
                MiniPoolAddressesProvider(config.readAddress(".miniPoolAddressesProvider"));
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(config.readAddress(".miniPoolConfigurator"));

            /* Change peripherials */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            _changePeripherials(
                treasury,
                miniPoolAsteraTreasury,
                vault,
                rewarder,
                rewarder6909,
                miniPoolId,
                profitHandler
            );
            _turnOnRehypothecation(rehypothecation);
            /* Data Provider */
            if (asteraDataProvider.deploy) {
                contracts.asteraDataProvider = new AsteraDataProvider2(
                    asteraDataProvider.networkBaseTokenAggregator,
                    asteraDataProvider.marketReferenceCurrencyAggregator
                );
                contracts.asteraDataProvider.setLendingPoolAddressProvider(
                    address(contracts.lendingPoolAddressesProvider)
                );
                contracts.asteraDataProvider.setMiniPoolAddressProvider(
                    address(contracts.miniPoolAddressesProvider)
                );
            }
            vm.stopBroadcast();
            path = string.concat(root, "/scripts/outputs/mainnet/6_ChangePeripherials.json");
        } else {
            console2.log("No deployment type selected in .env");
        }
        writeJsonData(path);
        return contracts;
    }
}
