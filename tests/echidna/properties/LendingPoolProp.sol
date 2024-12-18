// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../PropertiesBase.sol";

contract LendingPoolProp is PropertiesBase {
    constructor() {}

    // --------------------- state updates ---------------------

    /// @custom:invariant 200 - Users must always be able to deposit in normal condition.
    /// @custom:invariant 201 - `deposit()` must increase the user aToken balance by `amount`.
    /// @custom:invariant 202 - `deposit()` must decrease the user asset balance by `amount`.
    function randDepositLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedOnBeHalfOf,
        uint8 seedAsset,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randOnBehalfOf = clampBetween(seedOnBeHalfOf, 0, totalNbUsers);
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);

        User user = users[randUser];
        User onBehalfOf = users[randOnBehalfOf];
        MintableERC20 asset = assets[randAsset];
        AToken aToken = aTokens[randAsset];

        uint256 randAmt = clampBetween(seedAmt, 1, asset.balanceOf(address(user)) / 10);

        uint256 aTokenBalanceBefore = aToken.balanceOf(address(onBehalfOf));
        uint256 assetBalanceBefore = asset.balanceOf(address(user));

        user.approveERC20(IERC20(address(asset)), address(pool));

        (bool success,) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.deposit.selector, address(asset), true, randAmt, address(onBehalfOf)
            )
        );
        assertWithMsg(success, "200");

        uint256 aTokenBalanceAfter = aToken.balanceOf(address(onBehalfOf));
        uint256 assetBalanceAfter = asset.balanceOf(address(user));
        assertEqApprox(aTokenBalanceAfter - aTokenBalanceBefore, randAmt, 1, "201");
        assertEq(assetBalanceBefore - assetBalanceAfter, randAmt, "202");
    }

    /// @custom:invariant 230 - `withdraw()` must not result in a health factor of less than 1.
    /// @custom:invariant 227 - Rehypothecation: if the external rehypothecation vault is liquid, users should always be able to withdraw if all other withdrawal conditions are met.
    /// @custom:invariant 203 - `withdraw()` must decrease the user aToken balance by `amount`.
    /// @custom:invariant 204 - `withdraw()` must increase the user asset balance by `amount`.
    function randWithdrawLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedTo,
        uint8 seedAsset,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randTo = clampBetween(seedTo, 0, totalNbUsers);
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);

        User user = users[randUser];
        User to = users[randTo];
        MintableERC20 asset = assets[randAsset];
        AToken aToken = aTokens[randAsset];

        uint256 aTokenBalanceBefore = aToken.balanceOf(address(user));
        uint256 assetBalanceBefore = asset.balanceOf(address(to));

        uint256 randAmt = clampBetween(seedAmt, 0, aTokenBalanceBefore);

        (bool success,) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.withdraw.selector, address(asset), true, randAmt, address(to)
            )
        );

        (,,,,, uint256 healthFactorAfter) = pool.getUserAccountData(address(to));
        // if (healthFactorAfter >= 1e18){
        //     assertWithMsg(success, "227");
        // }

        require(success);

        if (healthFactorAfter < 1e18) {
            assertWithMsg(!success, "230");
        }

        uint256 aTokenBalanceAfter = aToken.balanceOf(address(user));
        uint256 assetBalanceAfter = asset.balanceOf(address(to));
        assertEqApprox(aTokenBalanceBefore - aTokenBalanceAfter, randAmt, 1, "203");
        assertEq(assetBalanceAfter - assetBalanceBefore, randAmt, "204");
    }

    /// @custom:invariant 205 - A user must not be able to `borrow()` if he doesn't own aTokens.
    /// @custom:invariant 206 - `borrow()` must only be possible if the user health factor is greater than 1.
    /// @custom:invariant 207 - `borrow()` must not result in a health factor of less than 1.
    /// @custom:invariant 208 - `borrow()` must increase the user debtToken balance by `amount`.
    /// @custom:invariant 209 - `borrow()` must decrease `borrowAllowance()` by `amount` if `user != onBehalf`.
    function randBorrowLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedOnBeHalfOf,
        uint8 seedAsset,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randOnBehalfOf = clampBetween(seedOnBeHalfOf, 0, totalNbUsers);
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);

        User onBehalfOf = users[randOnBehalfOf];
        MintableERC20 asset = assets[randAsset];
        VariableDebtToken debtToken = debtTokens[randAsset];
        User user = users[randUser];

        uint256 randAmt = clampBetween(
            seedAmt, 1, pool.getUserMaxBorrowCapacity(address(onBehalfOf), address(asset))
        );

        bool success;
        if (address(user) != address(onBehalfOf)) {
            (success,) = onBehalfOf.proxy(
                address(debtToken),
                abi.encodeWithSelector(debtToken.approveDelegation.selector, address(user), randAmt)
            );
            assert(success);
        }

        uint256 borrowAllowanceBefore =
            debtToken.borrowAllowance(address(onBehalfOf), address(user));
        uint256 vTokenBalanceBefore = debtToken.balanceOf(address(onBehalfOf));
        (,,,,, uint256 healthFactorBefore) = pool.getUserAccountData(address(onBehalfOf));

        (success,) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.borrow.selector, address(asset), true, randAmt, address(onBehalfOf)
            )
        );

        if (!hasATokens(onBehalfOf)) {
            assertWithMsg(!success, "205");
        }

        if (healthFactorBefore < 1e18) {
            assertWithMsg(!success, "206");
        }

        // (,,,,, uint256 healthFactorAfter) = pool.getUserAccountData(address(onBehalfOf));
        // if (healthFactorAfter < 1e18){
        //     assertWithMsg(!success, "207");
        // }

        require(success);

        uint256 vTokenBalanceAfter = debtToken.balanceOf(address(onBehalfOf));
        assertEqApprox(vTokenBalanceAfter - vTokenBalanceBefore, randAmt, 1, "208");

        if (address(user) != address(onBehalfOf)) {
            assertEq(
                borrowAllowanceBefore,
                debtToken.borrowAllowance(address(onBehalfOf), address(user)) + randAmt,
                "209"
            );
        }
    }

    /// @custom:invariant 210 - `repay()` must decrease the onBehalfOf debtToken balance by `amount`.
    /// @custom:invariant 211 - `repay()` must decrease the user asset balance by `amount`.
    /// @custom:invariant 212 - `healthFactorAfter` must be greater than `healthFactorBefore` as long as liquidations are done in time.
    function randRepayLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedOnBeHalfOf,
        uint8 seedAsset,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randOnBehalfOf = clampBetween(seedOnBeHalfOf, 0, totalNbUsers);
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);

        User user = users[randUser];
        User onBehalfOf = users[randOnBehalfOf];
        MintableERC20 asset = assets[randAsset];
        AToken aToken = aTokens[randAsset];
        VariableDebtToken debtToken = debtTokens[randAsset];

        uint256 vTokenBalanceBefore = debtToken.balanceOf(address(onBehalfOf));
        uint256 assetBalanceBefore = asset.balanceOf(address(user));
        (,,,,, uint256 healthFactorBefore) = pool.getUserAccountData(address(onBehalfOf));

        uint256 randAmt = clampBetween(seedAmt, 0, vTokenBalanceBefore);

        (bool success,) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.repay.selector, address(asset), true, randAmt, address(onBehalfOf)
            )
        );

        require(success);

        uint256 vTokenBalanceAfter = debtToken.balanceOf(address(onBehalfOf));
        uint256 assetBalanceAfter = asset.balanceOf(address(user));
        (,,,,, uint256 healthFactorAfter) = pool.getUserAccountData(address(onBehalfOf));

        assertEqApprox(vTokenBalanceBefore - vTokenBalanceAfter, randAmt, 1, "210");
        assertEqApprox(assetBalanceBefore - assetBalanceAfter, randAmt, 1, "211");
        assertGte(healthFactorAfter, healthFactorBefore, "212");
    }

    /// @custom:invariant 228 - Rehypothecation: farming percentage must be respected (+/- the drift) after a rebalance occured.
    /// @custom:invariant 229 - Rehypothecation: The profit handler address must see its balance increase after reaching the claiming threshold.
    function randRehypothecationRebalanceLP(LocalVars_UPTL memory vul, uint8 seedAToken) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        uint256 randAToken = clampBetween(seedAToken, 0, totalNbTokens);
        AToken aToken = aTokens[randAToken];

        if (aToken._farmingPct() != 0 && address(aToken._vault()) != address(0)) {
            uint256 balanceProfitHandlerBefore =
                ERC20(aToken.UNDERLYING_ASSET_ADDRESS()).balanceOf(aToken._profitHandler());

            poolConfigurator.rebalance(address(aToken));

            uint256 balanceProfitHandlerAfter =
                ERC20(aToken.UNDERLYING_ASSET_ADDRESS()).balanceOf(aToken._profitHandler());

            assertEqApproxPct(
                aToken._farmingBal(),
                aToken._underlyingAmount() * aToken._farmingPct() / BPS,
                aToken._farmingPctDrift() * 15000 / BPS, // +10% margin
                "228"
            );

            uint256 vaultBalance = ERC20(address(aToken._vault())).balanceOf(address(aToken));
            uint256 vaultAssets = aToken._vault().convertToAssets(vaultBalance);
            if (vaultAssets - aToken._farmingBal() >= aToken._claimingThreshold()) {
                assertGt(
                    balanceProfitHandlerBefore,
                    balanceProfitHandlerAfter - balanceProfitHandlerBefore,
                    "229"
                );
            }
        }
    }

    /// @custom:invariant 213 - `setUseReserveAsCollateral` must not reduce the health factor below 1.
    function randSetUseReserveAsCollateralLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedAsset,
        bool randIsColl
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens);

        User user = users[randUser];
        MintableERC20 asset = assets[randAsset];

        (,,,,, uint256 healthFactorBefore) = pool.getUserAccountData(address(user));

        (bool success,) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.setUserUseReserveAsCollateral.selector, address(asset), true, randIsColl
            )
        );
        require(success);

        (,,,,, uint256 healthFactorAfter) = pool.getUserAccountData(address(user));
        if (randIsColl) {
            assertLte(healthFactorBefore, healthFactorAfter, "213");
        } else {
            assertGte(healthFactorBefore, healthFactorAfter, "213");
        }

        if (healthFactorBefore >= 1e18 && healthFactorAfter != healthFactorBefore) {
            assertGte(healthFactorAfter, 1e18, "213");
        }
    }

    struct LocalVars_RandFlashloanLP {
        uint256 randUser;
        uint256 randAsset;
        uint256 randMode;
        uint256 randNbAssets;
        User user;
        MintableERC20 asset;
        VariableDebtToken debtToken;
        address[] assetsFl;
        bool[] reserveTypesFl;
        uint256[] amountsFl;
        uint256[] modesFl;
        bytes params;
        uint256[] assetBalanceBefore;
    }

    /// @custom:invariant 214 - Users must not be able to steal funds from flashloans.
    function randFlashloanLP(
        LocalVars_UPTL memory vul,
        uint8 seedUser,
        uint8 seedAsset, /* , uint8 seedMode */
        uint8 seedNbAssetFl,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateLP(vul);

        LocalVars_RandFlashloanLP memory v;

        v.randUser = clampBetween(seedUser, 0, totalNbUsers);
        v.randAsset = clampBetween(seedAsset, 0, totalNbTokens);
        v.randMode = 0; // clampBetween(seedMode, 0, 1);
        v.randNbAssets = clampBetween(seedNbAssetFl, 1, totalNbTokens);

        v.user = users[v.randUser];
        v.asset = assets[v.randAsset];
        v.debtToken = debtTokens[v.randAsset];

        v.assetsFl = new address[](v.randNbAssets);
        v.reserveTypesFl = new bool[](v.randNbAssets);
        v.amountsFl = new uint256[](v.randNbAssets);
        v.modesFl = new uint256[](v.randNbAssets);
        v.params = new bytes(0);

        v.assetBalanceBefore = new uint256[](v.randNbAssets);

        for (uint256 i = 0; i < v.randNbAssets; i++) {
            v.assetBalanceBefore[i] = assets[i].balanceOf(address(v.user));
            v.assetsFl[i] = address(assets[i]);
            v.reserveTypesFl[i] = true;
            v.amountsFl[i] = clampBetween(seedAmt, 1, aTokens[i].getTotalManagedAssets());
            v.modesFl[i] = v.randMode;
        }

        ILendingPool.FlashLoanParams memory flp = ILendingPool.FlashLoanParams({
            receiverAddress: address(v.user),
            assets: v.assetsFl,
            reserveTypes: v.reserveTypesFl,
            onBehalfOf: address(v.user)
        });

        v.user.execFlLP(flp, v.amountsFl, v.modesFl, v.params);

        for (uint256 i = 0; i < v.randNbAssets; i++) {
            assertGte(v.assetBalanceBefore[i], assets[i].balanceOf(address(v.user)), "214");
        }

        // Premium payment increase indexes => update last indexes
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = address(assets[i]);
            lastLiquidityIndexLP[asset] = pool.getReserveData(asset, true).liquidityIndex;
            lastVariableBorrowIndexLP[asset] = pool.getReserveData(asset, true).variableBorrowIndex;
        }
    }

    // ---------------------- Invariants ----------------------

    /// @custom:invariant 228 - Rehypothecation: farming percentage must be respected (+/- the drift) after a rebalance occured.
    function invariantRehypothecationLP() public {
        for (uint256 i = 0; i < aTokens.length; i++) {
            AToken aToken = aTokens[i];
            if (aToken._farmingPct() != 0 && address(aToken._vault()) != address(0)) {
                assertEqApproxPct(
                    aToken._farmingBal(),
                    aToken._underlyingAmount() * aToken._farmingPct() / BPS,
                    aToken._farmingPctDrift() * 15000 / BPS, // +50% margin
                    "228"
                );
            }
        }
    }

    /// @custom:invariant 215 - The total value borrowed must always be less than the value of the collaterals.
    function globalSolvencyCheckLP() public {
        uint256 valueColl;
        uint256 valueDebt;
        for (uint256 i = 0; i < aTokens.length; i++) {
            AToken aToken = aTokens[i];
            VariableDebtToken vToken = debtTokens[i];
            MintableERC20 asset = assets[i];
            uint256 price = oracle.getAssetPrice(address(asset));
            uint256 decimals = MintableERC20(asset).decimals();

            valueColl += aToken.totalSupply() * price / (10 ** decimals);

            valueDebt += vToken.totalSupply() * price / (10 ** decimals);
        }
        assertGte(valueColl, valueDebt, "215");
    }

    /// @custom:invariant 217 - The `liquidityIndex` should monotonically increase when there's total debt.
    /// @custom:invariant 218 - The `variableBorrowIndex` should monotonically increase when there's total debt.
    function indexIntegrityLP() public {
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = address(assets[i]);

            uint256 currentLiquidityIndex = pool.getReserveData(asset, true).liquidityIndex;
            uint256 currentVariableBorrowIndex =
                pool.getReserveData(asset, true).variableBorrowIndex;

            if (hasDebtTotal()) {
                assertGte(currentLiquidityIndex, lastLiquidityIndexLP[asset], "217");
                assertGte(currentVariableBorrowIndex, lastVariableBorrowIndexLP[asset], "218");
            } else {
                assertEq(currentLiquidityIndex, lastLiquidityIndexLP[asset], "217");
                assertEq(currentVariableBorrowIndex, lastVariableBorrowIndexLP[asset], "218");
            }
            lastLiquidityIndexLP[asset] = currentLiquidityIndex;
            lastVariableBorrowIndexLP[asset] = currentVariableBorrowIndex;
        }
    }

    /// @custom:invariant 219 - A user with debt should have at least an aToken balance `setUsingAsCollateral`.
    function userDebtIntegrityLP() public {
        for (uint256 i = 0; i < users.length; i++) {
            User user = users[i];
            if (hasDebt(user)) {
                assertWithMsg(hasATokensStrict(user), "219");
            }
        }
    }

    /// @custom:invariant 220 - If all debt is repaid, all `aToken` holder should be able to claim their collateral.
    /// @custom:invariant 221 - If all users withdraw their liquidity, there must not be aTokens supply left.
    // function usersFullCollateralClaimLP() public {
    //     if (!hasDebtTotal()) {
    //         for (uint256 i = 0; i < users.length; i++) {
    //             User user = users[i];
    //             for (uint256 j = 0; j < aTokens.length; j++) {
    //                 uint256 balanceAToken = aTokens[j].balanceOf(address(user));
    //                 if (balanceAToken != 0) {
    //                     (bool success,) = user.proxy(
    //                         address(pool),
    //                         abi.encodeWithSelector(
    //                             pool.withdraw.selector,
    //                             address(assets[j]),
    //                             true,
    //                             balanceAToken,
    //                             address(user)
    //                         )
    //                     );
    //                     assertWithMsg(success, "220");
    //                 }
    //             }
    //         }

    //         if (bootstrapLiquidity) {
    //             for (uint256 j = 0; j < aTokens.length; j++) {
    //                 uint256 balanceAToken = aTokens[j].balanceOf(address(bootstraper));
    //                 if (balanceAToken != 0) {
    //                     (bool success,) = bootstraper.proxy(
    //                         address(pool),
    //                         abi.encodeWithSelector(
    //                             pool.withdraw.selector,
    //                             address(assets[j]),
    //                             true,
    //                             balanceAToken,
    //                             address(bootstraper)
    //                         )
    //                     );
    //                     assertWithMsg(success, "220");
    //                 }
    //             }
    //         }

    //         assertWithMsg(!hasATokenTotal(), "221");
    //     }
    // }
}
