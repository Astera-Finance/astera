//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Script} from "lib/forge-std/src/Script.sol";
import {console2} from "lib/forge-std/src/console2.sol";
import {MiniPoolV2} from "contracts/protocol/core/minipool/MiniPoolV2.sol";
import {ATokenERC6909V2} from "contracts/protocol/tokenization/ERC6909/ATokenERC6909V2.sol";

contract DeployNewImpl is Script {
    uint256 constant BORROW_RATE = 0;

    function run() external {
        vm.startBroadcast();

        // MiniPoolV2 newMiniPool = new MiniPoolV2();
        // console2.log("MiniPool Impl deployed at:", address(newMiniPool));

        ATokenERC6909V2 aTokenERC6909V2 = new ATokenERC6909V2();
        console2.log("ATokenERC6909 Impl deployed at:", address(aTokenERC6909V2));

        vm.stopBroadcast();
    }
}
