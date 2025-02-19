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
    function randTransferLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedRecipient,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

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
    function randTransferFromLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedFrom,
        uint8 seedRecipient,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

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
    function randApproveLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedSender,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

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
    function randIncreaseAllowanceLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedSender,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

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
    function randDecreaseAllowanceLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedSender,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

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

    /// @custom:invariant 318 - Force feeding assets in LendingPool, ATokens, debtTokens, MiniPools or AToken6909 must not change the final result.
    function randForceFeedAssetLP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint128 seedAmt,
        uint8 seedAsset,
        uint8 seedReceiver
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);
        MintableERC20 asset = assets[randAsset];

        uint256 randAmt = clampBetween(seedAmt, 1, asset.balanceOf(address(this)) / 2);
        uint256 randReceiver = clampBetween(seedReceiver, 0, 5);

        uint256 randMinipool = clampBetween(seedMinipool, 0, totalNbMinipool);
        MiniPool minipool = miniPools[randMinipool];
        ATokenERC6909 aToken6909 = aTokens6909[randMinipool];

        if (randReceiver == 0) {
            asset.transfer(address(pool), randAmt);
        } else if (randReceiver == 1) {
            asset.transfer(address(aTokens[randAsset]), randAmt);
        } else if (randReceiver == 2) {
            asset.transfer(address(debtTokens[randAsset]), randAmt);
        } else if (randReceiver == 3) {
            asset.transfer(address(minipool), randAmt);
        } else {
            asset.transfer(address(aToken6909), randAmt);
        }
    }

    /// @custom:invariant 319 - Force feeding aToken in LendingPool, ATokens, debtTokens, MiniPools or AToken6909 must not change the final result.
    function randForceFeedATokensLP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint8 seedUser,
        uint128 seedAmt,
        uint8 seedAsset,
        uint8 seedReceiver
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        User user = users[randUser];
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);
        AToken aToken = aTokens[randAsset];
        uint256 randAmt = clampBetween(seedAmt, 1, aToken.balanceOf(address(user)));
        uint256 randReceiver = clampBetween(seedReceiver, 0, 5);

        uint256 randMinipool = clampBetween(seedMinipool, 0, totalNbMinipool);
        MiniPool minipool = miniPools[randMinipool];
        ATokenERC6909 aToken6909 = aTokens6909[randMinipool];

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
        } else if (randReceiver == 2) {
            user.proxy(
                address(aToken),
                abi.encodeWithSelector(
                    aToken.transfer.selector, address(debtTokens[randAsset]), randAmt
                )
            );
        } else if (randReceiver == 3) {
            user.proxy(
                address(aToken),
                abi.encodeWithSelector(aToken.transfer.selector, address(minipool), randAmt)
            );
        } else {
            user.proxy(
                address(aToken),
                abi.encodeWithSelector(aToken.transfer.selector, address(aToken6909), randAmt)
            );
        }
    }

    // --- ATokenNonRebasing Properties ---

    /// @custom:invariant 322 - `ATokenNonRebasing` `balanceOf()` should be equivalent to `ATokens` adjusted to the conversion rate.
    function randATokenNonRebasingBalanceOfLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedAsset
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        User user = users[randUser];

        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);
        AToken aToken = aTokens[randAsset];
        ATokenNonRebasing aTokenNonRebasing = aTokensNonRebasing[randAsset];

        assertEq(
            aTokenNonRebasing.balanceOf(address(user)),
            aToken.convertToShares(aToken.balanceOf(address(user))),
            "322"
        );
    }

    /// @custom:invariant 303 - Transfers should update accounting correctly.
    /// @custom:invariant 304 - Self transfers should not break accounting.
    /// @custom:invariant 323 - `ATokenNonRebasing` `transfer()` should be equivalent to `ATokens` adjusted to the conversion rate.
    function randATokenNonRebasingTransferLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedReceiver,
        uint8 seedAsset,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        User user = users[clampBetween(seedUser, 0, totalNbUsers)];
        User receiver = users[clampBetween(seedReceiver, 0, totalNbUsers)];

        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);
        AToken aToken = aTokens[randAsset];
        ATokenNonRebasing aTokenNonRebasing = aTokensNonRebasing[randAsset];

        uint256 randAmt = clampBetween(seedAmt, 1, aTokenNonRebasing.balanceOf(address(user)) * 2);

        uint256 senderBalanceBefore = aToken.balanceOf(address(user));
        uint256 receiverBalanceBefore = aToken.balanceOf(address(receiver));

        (bool success,) = user.proxy(
            address(aTokenNonRebasing),
            abi.encodeWithSelector(aTokenNonRebasing.transfer.selector, address(receiver), randAmt)
        );
        if (!success) {
            return;
        }

        if (address(user) != address(receiver)) {
            // Test aTokenNonRebasing balances
            assertEqApprox(
                aToken.convertToShares(senderBalanceBefore),
                aTokenNonRebasing.balanceOf(address(user)) + randAmt,
                1,
                "303"
            );
            assertEqApprox(
                aToken.convertToShares(receiverBalanceBefore),
                aTokenNonRebasing.balanceOf(address(receiver)) - randAmt,
                1,
                "303"
            );

            // Test aToken balances
            assertEqApprox(
                senderBalanceBefore,
                aToken.balanceOf(address(user)) + aToken.convertToAssets(randAmt),
                1,
                "303"
            );
            assertEqApprox(
                receiverBalanceBefore,
                aToken.balanceOf(address(receiver)) - aToken.convertToAssets(randAmt),
                1,
                "303"
            );
        } else {
            // Test aTokenNonRebasing balances
            assertEqApprox(
                aToken.convertToShares(senderBalanceBefore),
                aTokenNonRebasing.balanceOf(address(user)),
                1,
                "304"
            );

            // Test aToken balances
            assertEqApprox(senderBalanceBefore, aToken.balanceOf(address(user)), 1, "304");
        }

        (success,) = receiver.proxy(
            address(aTokenNonRebasing),
            abi.encodeWithSelector(aTokenNonRebasing.transfer.selector, address(user), randAmt)
        );

        assertEqApprox(
            aToken.convertToShares(senderBalanceBefore),
            aTokenNonRebasing.balanceOf(address(user)),
            1,
            "323"
        );
        assertEqApprox(
            aToken.convertToShares(receiverBalanceBefore),
            aTokenNonRebasing.balanceOf(address(receiver)),
            1,
            "323"
        );

        assertEqApprox(senderBalanceBefore, aToken.balanceOf(address(user)), 1, "323");
        assertEqApprox(receiverBalanceBefore, aToken.balanceOf(address(receiver)), 1, "323");
    }

    /// @custom:invariant 303 - Transfers should update accounting correctly.
    /// @custom:invariant 304 - Self transfers should not break accounting.
    /// @custom:invariant 324 - `ATokenNonRebasing` `transferFrom()` should be equivalent to `ATokens` adjusted to the conversion rate.
    function randATokenNonRebasingTransferFromLP(
        LocalVars_UPTL memory vul,
        uint8 seedOwner,
        uint8 seedSpender,
        uint8 seedReceiver,
        uint8 seedAsset,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        User owner = users[clampBetween(seedOwner, 0, totalNbUsers)];
        User spender = users[clampBetween(seedSpender, 0, totalNbUsers)];
        User receiver = users[clampBetween(seedReceiver, 0, totalNbUsers)];

        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);
        AToken aToken = aTokens[randAsset];
        ATokenNonRebasing aTokenNonRebasing = aTokensNonRebasing[randAsset];

        uint256 randAmt = clampBetween(seedAmt, 1, aTokenNonRebasing.balanceOf(address(owner)) * 2);

        uint256 ownerBalanceBefore = aToken.balanceOf(address(owner));
        uint256 receiverBalanceBefore = aToken.balanceOf(address(receiver));

        // Approve spender
        owner.proxy(
            address(aTokenNonRebasing),
            abi.encodeWithSelector(aTokenNonRebasing.approve.selector, address(spender), randAmt)
        );

        // Execute transferFrom
        (bool success,) = spender.proxy(
            address(aTokenNonRebasing),
            abi.encodeWithSelector(
                aTokenNonRebasing.transferFrom.selector, address(owner), address(receiver), randAmt
            )
        );
        if (!success) {
            return;
        }

        if (address(owner) != address(receiver)) {
            // Test aTokenNonRebasing balances
            assertEqApprox(
                aToken.convertToShares(ownerBalanceBefore),
                aTokenNonRebasing.balanceOf(address(owner)) + randAmt,
                1,
                "324"
            );
            assertEqApprox(
                aToken.convertToShares(receiverBalanceBefore),
                aTokenNonRebasing.balanceOf(address(receiver)) - randAmt,
                1,
                "324"
            );

            // Test aToken balances
            assertEqApprox(
                ownerBalanceBefore,
                aToken.balanceOf(address(owner)) + aToken.convertToAssets(randAmt),
                1,
                "324"
            );
            assertEqApprox(
                receiverBalanceBefore,
                aToken.balanceOf(address(receiver)) - aToken.convertToAssets(randAmt),
                1,
                "324"
            );
        } else {
            // Test aTokenNonRebasing balances
            assertEqApprox(
                aToken.convertToShares(ownerBalanceBefore),
                aTokenNonRebasing.balanceOf(address(owner)),
                1,
                "324"
            );

            // Test aToken balances
            assertEqApprox(ownerBalanceBefore, aToken.balanceOf(address(owner)), 1, "324");
        }
    }

    /// @custom:invariant 312 - `approve()` must never revert.
    /// @custom:invariant 325 - Allowance must be modified correctly via `ATokenNonRebasing.approve()`.
    /// @custom:invariant 326 - `ATokenNonRebasing.approve()` must not modify `AToken.allowance()`.
    function randATokenNonRebasingApproveLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedSender,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randSender = clampBetween(seedSender, 0, totalNbUsers);
        uint256 randAToken = clampBetween(seedAToken, 0, totalNbTokens);

        User user = users[randUser];
        User sender = users[randUser];
        AToken aToken = aTokens[randAToken];
        ATokenNonRebasing aTokenNonRebasing = aTokensNonRebasing[randAToken];

        uint256 randAmt = clampBetween(seedAmt, 0, initialMint * 2);

        uint256 aTokenAllowanceBefore = aToken.allowance(address(user), address(sender));

        (bool success, bytes memory data) = user.proxy(
            address(aTokenNonRebasing),
            abi.encodeWithSelector(aTokenNonRebasing.approve.selector, address(sender), randAmt)
        );

        assertWithMsg(success, "312");

        assertEq(aTokenNonRebasing.allowance(address(user), address(sender)), randAmt, "325");
        assertEq(aToken.allowance(address(user), address(sender)), aTokenAllowanceBefore, "326");
    }

    // ---------------------- Invariants ----------------------

    /// @custom:invariant 320 - A user must not hold more than total supply.
    /// @custom:invariant 321 - Sum of users' balances must not exceed total supply.
    function balanceIntegrityLP(LocalVars_UPTL memory vul) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        for (uint256 j = 0; j < aTokens.length; j++) {
            AToken t = aTokens[j];
            uint256 sum = 0;
            uint256 ts = t.totalSupply();
            for (uint256 i = 0; i < users.length; i++) {
                uint256 bu = t.balanceOf(address(users[i]));
                sum += bu;
                assertLte(bu, ts, "320");
            }
            if (bootstrapLiquidity) {
                sum += t.balanceOf(address(bootstraper));
            }
            assertEqApprox(sum, ts, 1e10, "321");
        }
    }

    // ---------------------- Helpers ----------------------
}
