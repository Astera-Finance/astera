//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {WETHGateway} from "contracts/misc/WETHGateway.sol";
import {Script} from "lib/forge-std/src/Script.sol";
import {console2} from "lib/forge-std/src/console2.sol";

contract DeployWethGateway is Script {
    address public aWeth = 0xC183Db6066dA39ca4C25e3544E6b50350642Fb7f;
    address public lendingPool = 0x360996dA4E66f6282a142c8F86120F1adFf8Dd26;
    address public miniPool = 0xe4CbE4367CD14352B21b43D73c8288Cdca85ce76;
    WETHGateway public wethGateway;

    function run() external {
        vm.startBroadcast();
        // Deploy WethGateway
        wethGateway = new WETHGateway(aWeth);
        // Authorize the LendingPool
        wethGateway.authorizeLendingPool(address(lendingPool));
        // Authorize the MiniPool
        wethGateway.authorizeMiniPool(address(miniPool));

        console2.log("WETHGateway deployed at:", address(wethGateway));
        vm.stopBroadcast();
    }
}
