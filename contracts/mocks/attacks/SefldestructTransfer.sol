// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

contract SelfdestructTransfer {
    function destroyAndTransfer(address payable to) external payable {
        selfdestruct(to);
    }
}
