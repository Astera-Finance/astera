// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../DeployDataTypes.sol";
import "../helpers/TransferOwnershipHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {ChangePeripherialsLocal} from "./6_ChangePeripherialsLocal.s.sol";

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

        /* Fork Identifier */
        string memory RPC = vm.envString("BASE_RPC_URL");
        uint256 FORK_BLOCK = 21838058;
        uint256 fork;
        fork = vm.createSelectFork(RPC, FORK_BLOCK);

        /* Config fetching */
        ChangePeripherialsLocal changePeripherials = new ChangePeripherialsLocal();
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
    }
}
