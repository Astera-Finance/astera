//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {FixReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/lendingpool/FixReserveInterestRateStrategy.sol";
import {Script} from "lib/forge-std/src/Script.sol";
import {console2} from "lib/forge-std/src/console2.sol";

contract DeployWethGateway is Script {
    uint256 constant BORROW_RATE = 5e25;

    function run() external {
        vm.startBroadcast();
        // Deploy WethGateway
        FixReserveInterestRateStrategy fixReserveInterestRateStrategy =
            new FixReserveInterestRateStrategy(BORROW_RATE);

        console2.log(
            "fixReserveInterestRateStrategy deployed at:", address(fixReserveInterestRateStrategy)
        );
        vm.stopBroadcast();
    }
}
