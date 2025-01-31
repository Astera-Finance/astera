// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../PropertiesMain.sol";
import "../PropertiesBase.sol";
import "forge-std/Test.sol";

// cmd :: forge t --mt testCallSequence -vvvv
/// @notice This is a foudry test contract to test failing properties echidna fuzzing found.
contract FoundryTestSequence is Test {
    PropertiesMain public propertiesMain;

    constructor() {
        propertiesMain = new PropertiesMain();
    }

    function testCallSequence() public {
        propertiesMain.randDepositLP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0, 0, 0
        );
        propertiesMain.randWithdrawLP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0, 0, 0
        );
    }
}
