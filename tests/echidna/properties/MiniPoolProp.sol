// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../PropertiesBase.sol";

contract MiniPoolProp is PropertiesBase {
    constructor() {}

    // --------------------- state updates ---------------------

    /// @custom:invariant 500 - Users must always be able to deposit in normal condition.
    /// @custom:invariant 501 - `deposit()` must increase the user AToken6909 balance by `amount`.
    /// @custom:invariant 502 - `deposit()` must decrease the user asset balance by `amount`.
    function randDepositMP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint8 seedUser,
        uint8 seedOnBeHalfOf,
        uint8 seedAsset,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateMP(vul);

        uint256 randMinipool = clampBetween(seedMinipool, 0, totalNbMinipool);
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens * 2); // assets + aTokens length

        MiniPool minipool = miniPools[randMinipool];
        ATokenERC6909 aToken6909 = aTokens6909[randMinipool];
        User user = users[clampBetween(seedUser, 0, totalNbUsers)];
        User onBehalfOf = users[clampBetween(seedOnBeHalfOf, 0, totalNbUsers)];
        MintableERC20 asset = MintableERC20(allTokens(randAsset));

        uint256 randAmt = clampBetween(seedAmt, 1, asset.balanceOf(address(user)) / 20);

        (uint256 aTokenID,, bool isAToken) = aToken6909.getIdForUnderlying(address(asset));

        uint256 aTokenBalanceBefore = aToken6909.balanceOf(address(onBehalfOf), aTokenID);
        uint256 assetBalanceBefore = isAToken
            ? IERC20(IAToken(address(asset)).UNDERLYING_ASSET_ADDRESS()).balanceOf(address(user))
            : asset.balanceOf(address(user));

        (bool success,) = user.proxy(
            address(minipool),
            abi.encodeWithSelector(
                minipool.deposit.selector,
                address(asset),
                isAToken ? true : false,
                randAmt,
                address(onBehalfOf)
            )
        );

        assertWithMsg(success, "500");

        uint256 aTokenBalanceAfter = aToken6909.balanceOf(address(onBehalfOf), aTokenID);
        uint256 assetBalanceAfter = isAToken
            ? IERC20(IAToken(address(asset)).UNDERLYING_ASSET_ADDRESS()).balanceOf(address(user))
            : asset.balanceOf(address(user));
        assertEqApprox(aTokenBalanceAfter - aTokenBalanceBefore, randAmt, 1, "501");
        assertEq(
            assetBalanceBefore - assetBalanceAfter,
            isAToken ? IAToken(address(asset)).convertToAssets(randAmt) : randAmt,
            "502"
        );
    }

    /// @custom:invariant 503 - `withdraw()` must decrease the user AToken6909 balance by `amount`.
    /// @custom:invariant 504 - `withdraw()` must increase the user asset balance by `amount`.
    /// @custom:invariant 505 - `withdraw()` must not result in a health factor of less than 1.
    function randWithdrawMP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint8 seedUser,
        uint8 seedTo,
        uint8 seedAsset,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateMP(vul);

        uint256 randMinipool = clampBetween(seedMinipool, 0, totalNbMinipool);
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens * 2); // assets + aTokens length

        MiniPool minipool = miniPools[randMinipool];
        ATokenERC6909 aToken6909 = aTokens6909[randMinipool];
        User user = users[clampBetween(seedUser, 0, totalNbUsers)];
        User to = users[clampBetween(seedTo, 0, totalNbUsers)];
        MintableERC20 asset = MintableERC20(allTokens(randAsset));

        (uint256 aTokenID,, bool isAToken) = aToken6909.getIdForUnderlying(address(asset));

        uint256 aTokenBalanceBefore = aToken6909.balanceOf(address(user), aTokenID);
        uint256 assetBalanceBefore = isAToken
            ? IERC20(IAToken(address(asset)).UNDERLYING_ASSET_ADDRESS()).balanceOf(address(to))
            : asset.balanceOf(address(to));

        uint256 randAmt = clampBetween(seedAmt, 0, aTokenBalanceBefore);

        (bool success,) = user.proxy(
            address(minipool),
            abi.encodeWithSelector(
                minipool.withdraw.selector,
                address(asset),
                isAToken ? true : false,
                randAmt,
                address(to)
            )
        );

        (,,,,, uint256 healthFactorAfter) = minipool.getUserAccountData(address(to));

        require(success);

        if (healthFactorAfter < 1e18) {
            assertWithMsg(!success, "505");
        }

        uint256 aTokenBalanceAfter = aToken6909.balanceOf(address(user), aTokenID);
        uint256 assetBalanceAfter = isAToken
            ? IERC20(IAToken(address(asset)).UNDERLYING_ASSET_ADDRESS()).balanceOf(address(to))
            : asset.balanceOf(address(to));
        assertEqApprox(aTokenBalanceBefore - aTokenBalanceAfter, randAmt, 1, "503");
        assertEq(
            assetBalanceAfter - assetBalanceBefore,
            isAToken ? IAToken(address(asset)).convertToAssets(randAmt) : randAmt,
            "504"
        );
    }

    /// @custom:invariant 506 - A user must not be able to `borrow()` if they don't own AToken6909.
    /// @custom:invariant 507 - `borrow()` must only be possible if the user health factor is greater than 1.
    /// @custom:invariant 508 - `borrow()` must not result in a health factor of less than 1.
    /// @custom:invariant 509 - `borrow()` must increase the user debtToken balance by `amount`.
    /// @custom:invariant 510 - `borrow()` must decrease `borrowAllowance()` by `amount` if `user != onBehalf`.
    function randBorrowMP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint8 seedUser,
        uint8 seedOnBeHalfOf,
        uint8 seedAsset,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateMP(vul);

        uint256 randMinipool = clampBetween(seedMinipool, 0, totalNbMinipool);

        MockMiniPool minipool = miniPools[randMinipool];
        ATokenERC6909 aToken6909 = aTokens6909[randMinipool];
        MintableERC20 asset =
            MintableERC20(allTokens(clampBetween(seedAsset, 0, totalNbTokens * 2))); // assets + aTokens length
        User onBehalfOf = users[clampBetween(seedOnBeHalfOf, 0, totalNbUsers)];
        User user = users[clampBetween(seedUser, 0, totalNbUsers)];

        (, uint256 debtTokenID, bool isAToken) = aToken6909.getIdForUnderlying(address(asset));

        uint256 randAmt = clampBetween(
            seedAmt, 1, minipool.getUserMaxBorrowCapacity(address(onBehalfOf), address(asset))
        );

        bool success;
        if (address(user) != address(onBehalfOf)) {
            (success,) = onBehalfOf.proxy(
                address(aToken6909),
                abi.encodeWithSelector(
                    aToken6909.approveDelegation.selector, address(user), debtTokenID, randAmt
                )
            );
            assert(success);
        }

        uint256 borrowAllowanceBefore =
            aToken6909.borrowAllowance(debtTokenID, address(onBehalfOf), address(user));
        uint256 debtTokenBalanceBefore = aToken6909.balanceOf(address(onBehalfOf), debtTokenID);
        (,,,,, uint256 healthFactorBefore) = minipool.getUserAccountData(address(onBehalfOf));

        (success,) = user.proxy(
            address(minipool),
            abi.encodeWithSelector(
                minipool.borrow.selector,
                address(asset),
                isAToken ? true : false,
                randAmt,
                address(onBehalfOf)
            )
        );

        if (!hasATokens6909(onBehalfOf, randMinipool)) {
            assertWithMsg(!success, "506");
        }

        if (healthFactorBefore < 1e18) {
            assertWithMsg(!success, "507");
        }

        require(success);

        assertEqApprox(
            aToken6909.balanceOf(address(onBehalfOf), debtTokenID) - debtTokenBalanceBefore,
            randAmt,
            1,
            "509"
        );

        if (address(user) != address(onBehalfOf)) {
            assertEq(
                borrowAllowanceBefore,
                aToken6909.borrowAllowance(debtTokenID, address(onBehalfOf), address(user))
                    + randAmt,
                "510"
            );
        }
    }

    // ---------------------- Invariants ----------------------

    // ---------------------- Helpers ----------------------
}
