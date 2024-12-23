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
        propertiesMain.randDepositMP(PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3627169055486385356, false),0,0,2,1,37);
        propertiesMain.randBorrowMP(PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false),0,0,2,0,1);
        propertiesMain.randWithdrawMP(PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false),0,2,2,1,50709400810492495077782802097815808);
    }
}
