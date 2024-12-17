// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../PropertiesBase.sol";

contract ATokenERC6909Prop is PropertiesBase {
    constructor() {}

    // --------------------- state updates ---------------------

    /// @custom:invariant 600 - Zero amount transfers should not break accounting.
    /// @custom:invariant 601 - Once a user has a debt, they must not be able to transfer aTokens if this results in a health factor less than 1.
    /// @custom:invariant 602 - Transfers for more than available balance should not be allowed.
    /// @custom:invariant 603 - Transfers should update accounting correctly.
    /// @custom:invariant 604 - Self transfers should not break accounting.
    function randTransferMP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint8 seedUser,
        uint8 seedRecipient,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateMP(vul);

        uint256 randMinipool = clampBetween(seedMinipool, 0, totalNbMinipool);

        User user = users[clampBetween(seedUser, 0, totalNbUsers)];
        User recipient = users[clampBetween(seedRecipient, 0, totalNbUsers)];
        ATokenERC6909 aToken6909 = aTokens6909[randMinipool];
        MintableERC20 asset = MintableERC20(allTokens(clampBetween(seedAToken, 0, totalNbTokens)));

        (uint256 aTokenID,,) = aToken6909.getIdForUnderlying(address(asset));

        uint256 userBalanceATokenBefore = aToken6909.balanceOf(address(user), aTokenID);
        uint256 recipientBalanceATokenBefore = aToken6909.balanceOf(address(recipient), aTokenID);

        uint256 randAmt = clampBetween(seedAmt, 0, userBalanceATokenBefore * 2); // "600" : zero amt transfer possible

        {
            (bool success,) = user.proxy(
                address(aToken6909),
                abi.encodeWithSelector(
                    aToken6909.transfer.selector, address(recipient), aTokenID, randAmt
                )
            );

            (,,,,, uint256 hf) = miniPools[randMinipool].getUserAccountData(address(user));

            if (hf < 1e18) {
                assertWithMsg(!success, "601");
            }

            if (randAmt > userBalanceATokenBefore) {
                assertWithMsg(!success, "602");
            }

            require(success);
        }

        if (address(user) != address(recipient)) {
            assertEqApprox(
                userBalanceATokenBefore,
                aToken6909.balanceOf(address(user), aTokenID) + randAmt,
                1,
                "603"
            );
            assertEqApprox(
                recipientBalanceATokenBefore,
                aToken6909.balanceOf(address(recipient), aTokenID) - randAmt,
                1,
                "603"
            );
        } else {
            assertEqApprox(
                userBalanceATokenBefore, aToken6909.balanceOf(address(user), aTokenID), 1, "604"
            );
        }
    }

    /// @custom:invariant 605 - Zero amount transfers must not break accounting.
    /// @custom:invariant 606 - Once a user has a debt, they must not be able to transfer AToken6909s if this results in a health factor less than 1.
    /// @custom:invariant 607 - Transfers for more than available balance must not be allowed.
    /// @custom:invariant 608 - `transferFrom()` must only transfer if the sender has enough allowance from the `from` address.
    /// @custom:invariant 609 - Transfers must update accounting correctly.
    /// @custom:invariant 610 - Self transfers must not break accounting.
    /// @custom:invariant 611 - `transferFrom()` must decrease allowance.
    function randTransferFromMP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint8 seedUser,
        uint8 seedFrom,
        uint8 seedRecipient,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateMP(vul);

        uint256 randMinipool = clampBetween(seedMinipool, 0, totalNbMinipool);

        User from = users[clampBetween(seedFrom, 0, totalNbUsers)];
        User recipient = users[clampBetween(seedRecipient, 0, totalNbUsers)];
        User user = users[clampBetween(seedUser, 0, totalNbUsers)];
        ATokenERC6909 aToken6909 = aTokens6909[randMinipool];
        MintableERC20 asset = MintableERC20(allTokens(clampBetween(seedAToken, 0, totalNbTokens)));

        (uint256 aTokenID,,) = aToken6909.getIdForUnderlying(address(asset));

        uint256 fromAllowanceBefore = aToken6909.allowance(address(from), address(user), aTokenID);
        uint256 fromBalanceATokenBefore = aToken6909.balanceOf(address(from), aTokenID);
        uint256 recipientBalanceATokenBefore = aToken6909.balanceOf(address(recipient), aTokenID);

        uint256 randAmt = clampBetween(seedAmt, 0, fromBalanceATokenBefore * 2); // "605" : zero amt transfer possible

        {
            (bool success,) = user.proxy(
                address(aToken6909),
                abi.encodeWithSelector(
                    aToken6909.transferFrom.selector,
                    address(from),
                    address(recipient),
                    aTokenID,
                    randAmt
                )
            );

            (,,,,, uint256 hf) = miniPools[randMinipool].getUserAccountData(address(from));

            if (hf < 1e18) {
                assertWithMsg(!success, "606");
            }

            if (randAmt > fromBalanceATokenBefore) {
                assertWithMsg(!success, "607");
            }

            if (randAmt > fromAllowanceBefore) {
                assertWithMsg(!success, "608");
            }

            require(success);
        }

        if (address(from) != address(recipient)) {
            assertEqApprox(
                fromBalanceATokenBefore,
                aToken6909.balanceOf(address(from), aTokenID) + randAmt,
                1,
                "609"
            );
            assertEqApprox(
                recipientBalanceATokenBefore,
                aToken6909.balanceOf(address(recipient), aTokenID) - randAmt,
                1,
                "609"
            );
        } else {
            assertEqApprox(
                fromBalanceATokenBefore, aToken6909.balanceOf(address(from), aTokenID), 1, "610"
            );
        }

        assertEqApprox(
            fromAllowanceBefore,
            aToken6909.allowance(address(from), address(user), aTokenID) + randAmt,
            1,
            "611"
        );
    }

    /// @custom:invariant 612 - `approve()` must never revert.
    /// @custom:invariant 613 - Allowance must be modified correctly via `approve()`.
    function randApproveMP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint8 seedUser,
        uint8 seedSender,
        uint8 seedAToken,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateMP(vul);

        uint256 randMinipool = clampBetween(seedMinipool, 0, totalNbMinipool);
        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randSender = clampBetween(seedSender, 0, totalNbUsers);

        User user = users[randUser];
        User sender = users[randSender];
        ATokenERC6909 aToken6909 = aTokens6909[randMinipool];
        MintableERC20 asset = MintableERC20(allTokens(clampBetween(seedAToken, 0, totalNbTokens)));

        (uint256 aTokenID,,) = aToken6909.getIdForUnderlying(address(asset));

        uint256 randAmt = clampBetween(seedAmt, 0, initialMint * 2);

        (bool success,) = user.proxy(
            address(aToken6909),
            abi.encodeWithSelector(aToken6909.approve.selector, address(sender), aTokenID, randAmt)
        );

        assertWithMsg(success, "612");
        assertEq(aToken6909.allowance(address(user), address(sender), aTokenID), randAmt, "613");
    }

    /// @custom:invariant 614 - Force feeding assets in MiniPools or AToken6909 must not change the final result.
    function randForceFeedAssetMP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint128 seedAmt,
        uint8 seedAsset,
        bool seedReceiver
    ) public {
        randUpdatePriceAndTryLiquidateMP(vul);

        uint256 randMinipool = clampBetween(seedMinipool, 0, totalNbMinipool);
        uint256 randAmt = clampBetween(seedAmt, 1, type(uint80).max);
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens * 2);

        MintableERC20 asset = MintableERC20(allTokens(randAsset));
        ATokenERC6909 aToken6909 = aTokens6909[randMinipool];
        MiniPool minipool = miniPools[randMinipool];

        if (seedReceiver) {
            asset.transfer(address(minipool), randAmt);
        } else {
            asset.transfer(address(aToken6909), randAmt);
        }
    }

    // ---------------------- Invariants ----------------------

    // ---------------------- Helpers ----------------------
}
