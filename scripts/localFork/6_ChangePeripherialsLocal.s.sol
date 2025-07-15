// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../DeployDataTypes.sol";
import "../helpers/ChangePeripherialsHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {AddAssetsLocal} from "./4_AddAssetsLocal.s.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {ERC4626Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC4626Mock.sol";

contract ChangePeripherialsLocal is Script, ChangePeripherialsHelper, Test {
    using stdJson for string;

    function writeJsonData(string memory root, string memory path) internal {
        /* Write important contracts into the file */
        vm.serializeAddress(
            "peripherials", "asteraLendDataProvider", address(contracts.asteraLendDataProvider)
        );
        vm.serializeAddress("peripherials", "rewarder", address(contracts.rewarder));

        string memory output =
            vm.serializeAddress("peripherials", "rewarder6909", address(contracts.rewarder6909));

        vm.writeJson(output, "./scripts/localFork/outputs/6_DeployedPeripherials.json");

        path = string.concat(root, "/scripts/localFork/outputs/6_DeployedPeripherials.json");
        console.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);
    }

    function run() external returns (DeployedContracts memory) {
        console.log("6_ChangePeripherials");
        // Config fetching
        // Providers
        string memory root = vm.projectRoot();
        string memory path =
            string.concat(root, "/scripts/localFork/outputs/1_LendingPoolContracts.json");
        console.log("PATH: ", path);
        string memory config = vm.readFile(path);

        address lendingPoolAddressesProvider = config.readAddress(".lendingPoolAddressesProvider");

        path = string.concat(root, "/scripts/localFork/outputs/2_MiniPoolContracts.json");
        console.log("PATH: ", path);
        config = vm.readFile(path);

        address miniPoolAddressesProvider = config.readAddress(".miniPoolAddressesProvider");

        // Inputs from Peripherials
        path = string.concat(root, "/scripts/inputs/6_ChangePeripherials.json");
        console.log("PATH: ", path);
        config = vm.readFile(path);

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
        DataProvider memory asteraLendDataProvider =
            abi.decode(config.parseRaw(".asteraLendDataProvider"), (DataProvider));

        address profitHandler = config.readAddress(".profitHandler");

        require(treasury.length == rehypothecation.length, "Lengths settings must be the same");

        /* Fork Identifier */
        {
            string memory RPC = vm.envString("BASE_RPC_URL");
            uint256 FORK_BLOCK = 21838058;
            uint256 fork;
            fork = vm.createSelectFork(RPC, FORK_BLOCK);
        }
        /* Config fetching */
        AddAssetsLocal addAssets = new AddAssetsLocal();
        contracts = addAssets.run();

        vm.startPrank(FOUNDRY_DEFAULT);
        for (uint8 idx = 0; idx < vault.length; idx++) {
            vault[idx].newAddress = address(new ERC4626Mock(vault[idx].tokenAddress));
        }
        console.log("Changing peripherials");
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
        if (asteraLendDataProvider.deploy) {
            contracts.asteraLendDataProvider = new AsteraLendDataProvider(
                asteraLendDataProvider.networkBaseTokenAggregator,
                asteraLendDataProvider.marketReferenceCurrencyAggregator
            );
            contracts.asteraLendDataProvider.setLendingPoolAddressProvider(
                lendingPoolAddressesProvider
            );
            contracts.asteraLendDataProvider.setMiniPoolAddressProvider(miniPoolAddressesProvider);
        }
        vm.stopPrank();

        writeJsonData(root, path);
        return contracts;
    }
}
