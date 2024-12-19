// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./PropertiesMain.sol";
import "./PropertiesBase.sol";

/// @notice This is a foudry test contract to test failing properties echidna fuzzing found.
contract FoundryTestSequence {
    PropertiesMain public propertiesMain;

    constructor() {
        propertiesMain = new PropertiesMain();
    }

    // function testCallSequence() public {
    //     propertiesMain.randDepositLP(
    //         PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false), 0, 0, 0, 2000
    //     );
    //     propertiesMain.randBorrowLP(
    //         PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false), 0, 0, 1, 10
    //     );
    //     propertiesMain.randATokenNonRebasingTransferFromLP(
    //         PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false),
    //         0,
    //         0,
    //         1,
    //         0,
    //         2000
    //     );
    //     propertiesMain.userDebtIntegrityLP();
    // }

    function testCallSequence() public {
        propertiesMain.randDepositLP(
            PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false), 0, 1, 0, 4
        );
        propertiesMain.randBorrowLP(
            PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false),
            0,
            1,
            1,
            99963373682
        );
        propertiesMain.randBorrowLP(
            PropertiesBase.LocalVars_UPTL(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false), 0, 1, 1, 12
        );
    }
}
