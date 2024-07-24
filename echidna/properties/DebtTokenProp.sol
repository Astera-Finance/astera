// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../GranaryPropertiesBase.sol";

contract DebtTokenProp is GranaryPropertiesBase {
    constructor() {}

    // --------------------- state updates ---------------------

    // function randApproveDelegation() public {

    // }

    /// @custom:invariant 400 - `approveDelegation()` must never revert.
    /// @custom:invariant 401 - Allowance must be modified correctly via `approve()`.
    function randApproveDelegation(LocalVars_UPTL memory vul, uint seedUser, uint seedSender, uint seedVToken, uint seedAmt) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint randUser = clampBetween(seedUser, 0 ,totalNbUsers);
        uint randSender = clampBetween(seedSender, 0 ,totalNbUsers);
        uint randVToken = clampBetween(seedVToken, 0 ,totalNbTokens);

        User user = users[randUser];
        User sender = users[randUser];
        VariableDebtToken debtTokens = debtTokens[randVToken];

        uint randAmt = clampBetween(seedAmt, 0, initialMint * 2);

        (bool success, bytes memory data) = user.proxy(
            address(debtTokens),
            abi.encodeWithSelector(
                debtTokens.approveDelegation.selector,
                address(sender),
                randAmt
            )
        );

        assertWithMsg(success, "400");
        assertEq(debtTokens.borrowAllowance(address(user), address(sender)), randAmt, "401");
    }

    // ---------------------- Invariants ----------------------
    
    // ---------------------- Helpers ----------------------
}
