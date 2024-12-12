// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../PropertiesBase.sol";
import "../util/Hevm.sol";

contract ATokenProp is PropertiesBase {
    constructor() {}

    // --------------------- state updates ---------------------

    /// @custom:invariant 300 - Zero amount transfers should not break accounting.
    /// @custom:invariant 301 - Once a user has a debt, he must not be able to transfer aTokens if this result in a hf < 1.
    /// @custom:invariant 302 - Transfers for more than available balance should not be allowed.
    /// @custom:invariant 303 - Transfers should update accounting correctly.
    /// @custom:invariant 304 - Self transfers should not break accounting.
    function randTransfer(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedRecipient,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randRecipient = clampBetween(seedRecipient, 0, totalNbUsers);
        uint256 randAToken = clampBetween(seedAToken, 0, totalNbTokens);

        User user = users[randUser];
        User recipient = users[randRecipient];
        AToken aToken = aTokens[randAToken];

        uint256 userBalanceATokenBefore = aToken.balanceOf(address(user));
        uint256 recipientBalanceATokenBefore = aToken.balanceOf(address(recipient));

        uint256 randAmt = clampBetween(seedAmt, 0, userBalanceATokenBefore * 2); // "300" : zero amt transfer possible

        (bool success, bytes memory data) = user.proxy(
            address(aToken),
            abi.encodeWithSelector(aToken.transfer.selector, address(recipient), randAmt)
        );

        (,,,,, uint256 hf) = pool.getUserAccountData(address(user));

        if (hf < 1e18) {
            assertWithMsg(!success, "301");
        }

        if (randAmt > userBalanceATokenBefore) {
            assertWithMsg(!success, "302");
        }

        require(success);

        if (address(user) != address(recipient)) {
            assertEqApprox(
                userBalanceATokenBefore, aToken.balanceOf(address(user)) + randAmt, 1, "303"
            );
            assertEqApprox(
                recipientBalanceATokenBefore,
                aToken.balanceOf(address(recipient)) - randAmt,
                1,
                "303"
            );
        } else {
            assertEqApprox(userBalanceATokenBefore, aToken.balanceOf(address(user)), 1, "304");
        }
    }

    /// @custom:invariant 305 - Zero amount transfers must not break accounting.
    /// @custom:invariant 306 - Once a user has a debt, he must not be able to transfer aTokens if this result in a hf < 1.
    /// @custom:invariant 307 - Transfers for more than available balance must not be allowed.
    /// @custom:invariant 308 - `transferFrom()` must only transfer if the sender has enough allowance from the `from` address.
    /// @custom:invariant 309 - Transfers must update accounting correctly.
    /// @custom:invariant 310 - Self transfers must not break accounting.
    /// @custom:invariant 311 - `transferFrom()` must decrease allowance.
    function randTransferFrom(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedFrom,
        uint8 seedRecipient,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randFrom = clampBetween(seedFrom, 0, totalNbUsers);
        uint256 randRecipient = clampBetween(seedRecipient, 0, totalNbUsers);
        uint256 randAToken = clampBetween(seedAToken, 0, totalNbTokens);

        User from = users[randFrom];
        User recipient = users[randRecipient];
        AToken aToken = aTokens[randAToken];
        User user = users[randUser];

        uint256 fromAllowanceBefore = aToken.allowance(address(from), address(user));
        uint256 fromBalanceATokenBefore = aToken.balanceOf(address(from));
        uint256 recipientBalanceATokenBefore = aToken.balanceOf(address(recipient));

        uint256 randAmt = clampBetween(seedAmt, 0, fromBalanceATokenBefore * 2); // "305" : zero amt transfer possible

        (bool success, bytes memory data) = user.proxy(
            address(aToken),
            abi.encodeWithSelector(
                aToken.transferFrom.selector, address(from), address(recipient), randAmt
            )
        );

        (,,,,, uint256 hf) = pool.getUserAccountData(address(from));

        if (hf < 1e18) {
            assertWithMsg(!success, "306");
        }

        if (randAmt > fromBalanceATokenBefore) {
            assertWithMsg(!success, "307");
        }

        if (randAmt > fromAllowanceBefore) {
            assertWithMsg(!success, "308");
        }

        require(success);

        if (address(from) != address(recipient)) {
            assertEqApprox(
                fromBalanceATokenBefore, aToken.balanceOf(address(from)) + randAmt, 1, "309"
            );
            assertEqApprox(
                recipientBalanceATokenBefore,
                aToken.balanceOf(address(recipient)) - randAmt,
                1,
                "309"
            );
        } else {
            assertEqApprox(fromBalanceATokenBefore, aToken.balanceOf(address(from)), 1, "310");
        }

        assertEqApprox(
            fromAllowanceBefore, aToken.allowance(address(from), address(user)) + randAmt, 1, "311"
        );
    }

    /// @custom:invariant 312 - `approve()` must never revert.
    /// @custom:invariant 313 - Allowance must be modified correctly via `approve()`.
    function randApprove(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedSender,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randSender = clampBetween(seedSender, 0, totalNbUsers);
        uint256 randAToken = clampBetween(seedAToken, 0, totalNbTokens);

        User user = users[randUser];
        User sender = users[randUser];
        AToken aToken = aTokens[randAToken];

        uint256 randAmt = clampBetween(seedAmt, 0, initialMint * 2);

        (bool success, bytes memory data) = user.proxy(
            address(aToken),
            abi.encodeWithSelector(aToken.approve.selector, address(sender), randAmt)
        );

        assertWithMsg(success, "312");
        assertEq(aToken.allowance(address(user), address(sender)), randAmt, "313");
    }

    /// @custom:invariant 314 - `increaseAllowance()` must never revert.
    /// @custom:invariant 315 - Allowance must be modified correctly via `increaseAllowance()`.
    function randIncreaseAllowance(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedSender,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randSender = clampBetween(seedSender, 0, totalNbUsers);
        uint256 randAToken = clampBetween(seedAToken, 0, totalNbTokens);

        User user = users[randUser];
        User sender = users[randUser];
        AToken aToken = aTokens[randAToken];

        uint256 allowanceBefore = aToken.allowance(address(user), address(sender));
        uint256 randAmt = clampBetween(seedAmt, 0, initialMint * 2);

        (bool success, bytes memory data) = user.proxy(
            address(aToken),
            abi.encodeWithSelector(aToken.increaseAllowance.selector, address(sender), randAmt)
        );

        assertWithMsg(success, "314");
        assertEq(allowanceBefore + randAmt, aToken.allowance(address(user), address(sender)), "315");
    }

    /// @custom:invariant 316 - `decreaseAllowance()` must revert when user tries to decrease more than currently allowed.
    /// @custom:invariant 317 - Allowance must be modified correctly via `decreaseAllowance()`.
    function randDecreaseAllowance(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedSender,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randSender = clampBetween(seedSender, 0, totalNbUsers);
        uint256 randAToken = clampBetween(seedAToken, 0, totalNbTokens);

        User user = users[randUser];
        User sender = users[randUser];
        AToken aToken = aTokens[randAToken];

        uint256 allowanceBefore = aToken.allowance(address(user), address(sender));
        uint256 randAmt = clampBetween(seedAmt, 0, initialMint * 2);

        (bool success, bytes memory data) = user.proxy(
            address(aToken),
            abi.encodeWithSelector(aToken.decreaseAllowance.selector, address(sender), randAmt)
        );

        if (randAmt > allowanceBefore) {
            assertWithMsg(!success, "316");
        }

        assertEq(allowanceBefore - randAmt, aToken.allowance(address(user), address(sender)), "317");
    }

    // todo
    // /// @custom:invariant 318 - User nonce must increase by one.
    // /// @custom:invariant 319 - Mutation in the signature must make `permit()` revert.
    // /// @custom:invariant 320 - Mutation in parameters must make `permit()` revert.
    // /// @custom:invariant 321 - User allowance must be equal to `amount` when sender call `permit()`.
    // function randPermit(LocalVars_UPTL memory vul, uint8 seedUser, uint8 seedSender, uint8 seedAToken, uint128 seedAmt, uint48 randDeadline) public {
    //     randUpdatePriceAndTryLiquidate(vul);
    //     uint randUser = clampBetween(seedUser, 0 ,totalNbUsers);
    //     uint randSender = clampBetween(seedSender, 0 ,totalNbUsers);
    //     uint randAToken = clampBetween(seedAToken, 0 ,totalNbTokens);
    //     uint randAmt = clampBetween(seedAmt, 0, initialMint * 2);
    //     uint deadline = clampBetween(seedAmt, block.timestamp, block.timestamp * 100);

    //     User user = users[randUser];
    //     User sender = users[randUser];
    //     AToken aToken = aTokens[randAToken];

    //     (uint8 r, bytes32 v, bytes32 s) = Hevm.sign();

    //     (bool success, bytes memory data) = sender.proxy(
    //         address(aToken),
    //         abi.encodeWithSelector(
    //             aToken.permit.selector,
    //             address(user),
    //             address(sender),
    //             randAmt,
    //             deadline,
    //             v,
    //             r,
    //             s
    //         )
    //     );

    //     assertEq(aToken.allowance(address(user), address(sender)), randAmt, "321");
    // }

    /// @custom:invariant 322 - Force feeding assets in LendingPool, ATokens or debtTokens must not change the final result.
    function randForceFeedAsset(
        LocalVars_UPTL memory vul,
        uint128 seedAmt,
        uint8 seedAsset,
        uint8 seedReceiver
    ) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint256 randAmt = clampBetween(seedAmt, 1, type(uint80).max);
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);
        uint256 randReceiver = clampBetween(seedReceiver, 0, 3);

        MintableERC20 asset = assets[randAsset];

        if (randReceiver == 0) {
            asset.transfer(address(pool), randAmt);
        } else if (randReceiver == 1) {
            asset.transfer(address(aTokens[randAsset]), randAmt);
        } else {
            asset.transfer(address(debtTokens[randAsset]), randAmt);
        }
    }

    /// @custom:invariant 323 - Force feeding aToken in LendingPool, ATokens or debtTokens must not change the final result.
    function randForceFeedATokens(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint128 seedAmt,
        uint8 seedAsset,
        uint8 seedReceiver
    ) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        User user = users[randUser];
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);
        AToken aToken = aTokens[randAsset];
        uint256 randAmt = clampBetween(seedAmt, 1, aToken.balanceOf(address(user)));
        uint256 randReceiver = clampBetween(seedReceiver, 0, 3);

        if (randReceiver == 0) {
            user.proxy(
                address(aToken),
                abi.encodeWithSelector(aToken.transfer.selector, address(pool), randAmt)
            );
        } else if (randReceiver == 1) {
            user.proxy(
                address(aToken),
                abi.encodeWithSelector(aToken.transfer.selector, address(aToken), randAmt)
            );
        } else {
            user.proxy(
                address(aToken),
                abi.encodeWithSelector(
                    aToken.transfer.selector, address(debtTokens[randAsset]), randAmt
                )
            );
        }
    }

    // --- ATokenNonRebasing Properties ---

    /// @custom:invariant 326 - `ATokenNonRebasing` `balanceOf()` should be equivalent to `ATokens` adjusted to the conversion rate.
    function randATokenNonRebasingBalanceOf(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedAsset
    ) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        User user = users[randUser];

        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);
        AToken aToken = aTokens[randAsset];
        ATokenNonRebasing aTokenNonRebasing = aTokensNonRebasing[randAsset];

        assertEq(
            aTokenNonRebasing.balanceOf(address(user)),
            aToken.convertToShares(aToken.balanceOf(address(user))),
            "326"
        );
    }

    /// @custom:invariant 327 - `ATokenNonRebasing` `transfer()` should be equivalent to `ATokens` adjusted to the conversion rate.
    // function randATokenNonRebasingTransfer(
    //     LocalVars_UPTL memory vul,
    //     uint8 seedUser,
    //     uint8 seedAsset,
    //     uint8 seedAmt,
    //     uint8 seedReceiver
    // ) public {
    //     randUpdatePriceAndTryLiquidate(vul);

    //     uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
    //     User user = users[randUser];

    //     uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);
    //     AToken aToken = aTokens[randAsset];
    //     ATokenNonRebasing aTokenNonRebasing = aTokensNonRebasing[randAsset];

    //     uint256 randAmt = clampBetween(seedAmt, 1, aTokenNonRebasing.balanceOf(address(user)));
    //     uint256 randReceiver = clampBetween(seedReceiver, 0, 3);

    //     address receiver;
    //     if (randReceiver == 0) {
    //         receiver = address(pool);
    //     } else if (randReceiver == 1) {
    //         receiver = address(aToken);
    //     } else {
    //         receiver = address(debtTokens[randAsset]);
    //     }

    //     uint256 senderBalanceBefore = aToken.balanceOf(address(user));
    //     uint256 receiverBalanceBefore = aToken.balanceOf(receiver);

    //     user.proxy(
    //         address(aTokenNonRebasing),
    //         abi.encodeWithSelector(aTokenNonRebasing.transfer.selector, receiver, randAmt)
    //     );

    //     assertEq(
    //         aTokenNonRebasing.balanceOf(address(user)),
    //         aToken.convertToShares(aToken.balanceOf(address(user))),
    //         "327"
    //     );
    //     assertEq(
    //         aTokenNonRebasing.balanceOf(receiver),
    //         aToken.convertToShares(aToken.balanceOf(receiver)),
    //         "327"
    //     );
    // }

    // ---------------------- Invariants ----------------------

    // todo - failing
    /// @custom:invariant 324 -A user must not hold more than total supply.
    /// @custom:invariant 325- Sum of users balance must not exceed total supply.
    // function balanceIntegrity(LocalVars_UPTL memory vul) public {
    //     randUpdatePriceAndTryLiquidate(vul);
    //     for (uint256 j = 0; j < aTokens.length; j++) {
    //         AToken t = aTokens[j];
    //         uint sum = 0;
    //         uint ts = t.totalSupply();
    //         for (uint256 i = 0; i < users.length; i++) {
    //             uint bu = t.balanceOf(address(users[i]));
    //             sum += bu;
    //             assertLt(bu, ts, "324");
    //         }
    //         if (bootstrapLiquidity)
    //             sum += t.balanceOf(address(bootstraper));
    //         assertEqApprox(sum, ts, 1e10, "325");
    //     }
    // }

    // ---------------------- Helpers ----------------------
}
