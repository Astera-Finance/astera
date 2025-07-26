//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {WETHGateway} from "contracts/misc/WETHGateway.sol";
import {Script} from "lib/forge-std/src/Script.sol";
import {console2} from "lib/forge-std/src/console2.sol";

contract DeployWethGateway is Script {
    address public aWeth = 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A;
    address public lendingPool = 0x17d8a5305A37fe93E13a28f09c46db5bE24E1B9E;
    // address public miniPool = 0xe4CbE4367CD14352B21b43D73c8288Cdca85ce76;
    WETHGateway public wethGateway;

    function run() external {
        vm.startBroadcast();
        // Deploy WethGateway
        wethGateway = new WETHGateway(aWeth);
        // Authorize the LendingPool
        wethGateway.authorizeLendingPool(address(lendingPool));
        // Authorize the MiniPool
        // wethGateway.authorizeMiniPool(address(miniPool));

        console2.log("WETHGateway deployed at:", address(wethGateway));
        vm.stopBroadcast();
    }
}
