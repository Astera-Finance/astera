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
        propertiesMain.randApproveDelegation(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0, 0, 0
        );
        propertiesMain.randApproveDelegation(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0, 0, 0
        );
        propertiesMain.randATokenNonRebasingBalanceOfLP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0
        );
        propertiesMain.randDepositLP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15989, false)),
            0,
            0,
            1,
            50
        );
        propertiesMain.randFlashloanLP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0, 0, 0
        );
        propertiesMain.randApproveMP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)),
            0,
            0,
            0,
            0,
            0
        );
        propertiesMain.randForceFeedAssetLP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0, 0, 0
        );
        propertiesMain.randATokenNonRebasingBalanceOfLP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0
        );
        propertiesMain.randATokenNonRebasingBalanceOfLP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0
        );
        propertiesMain.randApproveDelegation(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0, 0, 0
        );
        propertiesMain.randFlashloanLP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0, 0, 0
        );
        propertiesMain.randBorrowLP(
            (PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)), 0, 0, 0, 3
        );
    }
}
