// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../PropertiesBase.sol";
import {MathUtils} from "../../../contracts/protocol/libraries/math/MathUtils.sol";
import {WadRayMath} from "../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {IFlowLimiter} from "../../../contracts/interfaces/base/IFlowLimiter.sol";

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

        lastLiquidityIndexMP[address(minipool)][address(asset)] =
            minipool.getReserveData(address(asset)).liquidityIndex;
        lastVariableBorrowIndexMP[address(minipool)][address(asset)] =
            minipool.getReserveData(address(asset)).variableBorrowIndex;

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

        (,,,,, uint256 healthFactorAfter) = minipool.getUserAccountData(address(user));

        require(success);

        lastLiquidityIndexMP[address(minipool)][address(asset)] =
            minipool.getReserveData(address(asset)).liquidityIndex;
        lastVariableBorrowIndexMP[address(minipool)][address(asset)] =
            minipool.getReserveData(address(asset)).variableBorrowIndex;

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
    /// @custom:invariant 509 - `borrow()` must increase the user debtToken balance by `amount` when flow borrowing is disabled.
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

        // 509 needs to be disabled when flow borrowing is enabled because the debt index is updated in the `borrow()`.
        // So `balanceOf()` used in `debtTokenBalanceBefore` is not coherent for 509 property with the one used in
        // `debtTokenBalanceAfter`.
        if (
            IFlowLimiter(miniPoolProvider.getFlowLimiter()).currentFlow(
                address(asset), address(minipool)
            ) == 0
        ) {
            assertEqApprox(
                aToken6909.balanceOf(address(onBehalfOf), debtTokenID) - debtTokenBalanceBefore,
                randAmt,
                1,
                "509"
            );
        }

        if (address(user) != address(onBehalfOf)) {
            assertEq(
                borrowAllowanceBefore,
                aToken6909.borrowAllowance(debtTokenID, address(onBehalfOf), address(user))
                    + randAmt,
                "510"
            );
        }

        lastLiquidityIndexMP[address(minipool)][address(asset)] =
            minipool.getReserveData(address(asset)).liquidityIndex;
        lastVariableBorrowIndexMP[address(minipool)][address(asset)] =
            minipool.getReserveData(address(asset)).variableBorrowIndex;
    }

    /// @custom:invariant 511 - `repay()` must decrease the onBehalfOf debtToken balance by `amount`.
    /// @custom:invariant 512 - `repay()` must decrease the user asset balance by `amount`.
    /// @custom:invariant 513 - `healthFactorAfter` must be greater than `healthFactorBefore` as long as liquidations are done in time.
    function randRepayMP(
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

        (, uint256 debtTokenID, bool isAToken) = aToken6909.getIdForUnderlying(address(asset));

        uint256 debtTokenBalanceBefore = aToken6909.balanceOf(address(onBehalfOf), debtTokenID);
        uint256 assetBalanceBefore = isAToken
            ? IERC20(IAToken(address(asset)).UNDERLYING_ASSET_ADDRESS()).balanceOf(address(user))
            : asset.balanceOf(address(user));
        (,,,,, uint256 healthFactorBefore) = minipool.getUserAccountData(address(onBehalfOf));

        uint256 randAmt = clampBetween(seedAmt, 0, debtTokenBalanceBefore);

        (bool success,) = user.proxy(
            address(minipool),
            abi.encodeWithSelector(
                minipool.repay.selector,
                address(asset),
                isAToken ? true : false,
                randAmt,
                address(onBehalfOf)
            )
        );

        require(success);

        lastLiquidityIndexMP[address(minipool)][address(asset)] =
            minipool.getReserveData(address(asset)).liquidityIndex;
        lastVariableBorrowIndexMP[address(minipool)][address(asset)] =
            minipool.getReserveData(address(asset)).variableBorrowIndex;

        uint256 debtTokenBalanceAfter = aToken6909.balanceOf(address(onBehalfOf), debtTokenID);
        uint256 assetBalanceAfter = isAToken
            ? IERC20(IAToken(address(asset)).UNDERLYING_ASSET_ADDRESS()).balanceOf(address(user))
            : asset.balanceOf(address(user));
        (,,,,, uint256 healthFactorAfter) = minipool.getUserAccountData(address(onBehalfOf));

        // assertEqApprox(debtTokenBalanceBefore - debtTokenBalanceAfter, randAmt, 1, "511");

        assertEqApprox(
            assetBalanceBefore - assetBalanceAfter,
            isAToken ? IAToken(address(asset)).convertToAssets(randAmt) : randAmt,
            1,
            "512"
        );
        assertGte(healthFactorAfter, healthFactorBefore, "513");
    }

    /// @custom:invariant 514 - `setUseReserveAsCollateral` must not reduce the health factor below 1.
    function randSetUseReserveAsCollateralMP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint8 seedUser,
        uint8 seedAsset,
        bool randIsColl
    ) public {
        randUpdatePriceAndTryLiquidateMP(vul);

        uint256 randMinipool = clampBetween(seedMinipool, 0, totalNbMinipool);
        uint256 randUser = clampBetween(seedUser, 0, totalNbUsers);
        uint256 randAsset = clampBetween(seedAsset, 0, totalNbTokens * 2); // assets + aTokens length

        MiniPool minipool = miniPools[randMinipool];
        User user = users[randUser];
        MintableERC20 asset = MintableERC20(allTokens(randAsset));

        (,,,,, uint256 healthFactorBefore) = minipool.getUserAccountData(address(user));

        (bool success,) = user.proxy(
            address(minipool),
            abi.encodeWithSelector(
                minipool.setUserUseReserveAsCollateral.selector, address(asset), randIsColl
            )
        );
        require(success);

        isUseReserveAsCollateralDeactivatedMP[randMinipool][address(user)][address(asset)] =
            !randIsColl;

        (,,,,, uint256 healthFactorAfter) = minipool.getUserAccountData(address(user));
        if (randIsColl) {
            assertLte(healthFactorBefore, healthFactorAfter, "514");
        } else {
            assertGte(healthFactorBefore, healthFactorAfter, "514");
        }

        if (healthFactorBefore >= 1e18 && healthFactorAfter != healthFactorBefore) {
            assertGte(healthFactorAfter, 1e18, "514");
        }

        lastLiquidityIndexMP[address(minipool)][address(asset)] =
            minipool.getReserveData(address(asset)).liquidityIndex;
        lastVariableBorrowIndexMP[address(minipool)][address(asset)] =
            minipool.getReserveData(address(asset)).variableBorrowIndex;
    }

    struct LocalVars_RandFlashloanMP {
        uint256 randUser;
        uint256 randAsset;
        uint256 randMode;
        uint256 randNbAssets;
        User user;
        MintableERC20 asset;
        VariableDebtToken debtToken;
        address[] assetsFl;
        uint256[] amountsFl;
        uint256[] modesFl;
        bytes params;
        uint256[] assetBalanceBefore;
    }

    /// @custom:invariant 515 - Users must not be able to steal funds from flashloans.
    function randFlashloanMP(
        LocalVars_UPTL memory vul,
        uint8 seedMinipool,
        uint8 seedUser,
        uint8 seedAsset, /* , uint8 seedMode */
        uint8 seedNbAssetFl,
        uint128 seedAmt
    ) public {
        randUpdatePriceAndTryLiquidateMP(vul);

        LocalVars_RandFlashloanMP memory v;

        v.randUser = clampBetween(seedUser, 0, totalNbUsers);
        v.randAsset = clampBetween(seedAsset, 0, totalNbTokens * 2); // assets + aTokens length
        v.randMode = 0; // clampBetween(seedMode, 0, 1);
        v.randNbAssets = clampBetween(seedNbAssetFl, 1, totalNbTokens * 2);

        v.user = users[v.randUser];
        v.asset = MintableERC20(allTokens(v.randAsset));

        v.assetsFl = new address[](v.randNbAssets);
        v.amountsFl = new uint256[](v.randNbAssets);
        v.modesFl = new uint256[](v.randNbAssets);
        v.params = new bytes(0);

        v.assetBalanceBefore = new uint256[](v.randNbAssets);

        MiniPool minipool = miniPools[clampBetween(seedMinipool, 0, totalNbMinipool)];

        for (uint256 i = 0; i < v.randNbAssets; i++) {
            v.assetBalanceBefore[i] = MintableERC20(allTokens(i)).balanceOf(address(v.user));
            v.assetsFl[i] = allTokens(i);
            v.amountsFl[i] =
                clampBetween(seedAmt, 1, minipool.getReserveData(allTokens(i)).currentLiquidityRate);
            v.modesFl[i] = v.randMode;
        }

        IMiniPool.FlashLoanParams memory flp = IMiniPool.FlashLoanParams({
            receiverAddress: address(v.user),
            assets: v.assetsFl,
            onBehalfOf: address(v.user)
        });

        v.user.execFlMP(address(minipool), flp, v.amountsFl, v.modesFl, v.params);

        for (uint256 i = 0; i < v.randNbAssets; i++) {
            assertGte(
                v.assetBalanceBefore[i],
                MintableERC20(allTokens(i)).balanceOf(address(v.user)),
                "515"
            );
        }

        // Premium payment increase indexes => update last indexes
        for (uint256 i = 0; i < totalNbTokens * 2; i++) {
            address asset = allTokens(i);
            lastLiquidityIndexMP[address(minipool)][asset] =
                minipool.getReserveData(asset).liquidityIndex;
            lastVariableBorrowIndexMP[address(minipool)][asset] =
                minipool.getReserveData(asset).variableBorrowIndex;
        }
    }

    // ---------------------- Invariants ----------------------

    /// @custom:invariant 516 - The total value borrowed must always be less than the value of the collaterals when flow borrowing is disabled.
    function globalSolvencyCheckMP() public {
        for (uint256 j = 0; j < totalNbMinipool; j++) {
            MiniPool minipool = miniPools[j];
            ATokenERC6909 aToken6909 = aTokens6909[j];
            uint256 valueColl;
            uint256 valueDebt;
            for (uint256 i = 0; i < totalNbTokens * 2; i++) {
                address asset = allTokens(i);

                if (
                    IFlowLimiter(miniPoolProvider.getFlowLimiter()).currentFlow(
                        address(asset), address(minipool)
                    ) == 0
                ) {
                    return;
                }

                (uint256 aTokenId, uint256 debtTokenId,) =
                    aToken6909.getIdForUnderlying(address(asset));
                uint256 price = oracle.getAssetPrice(asset);
                uint256 decimals = MintableERC20(asset).decimals();

                valueColl += aToken6909.totalSupply(aTokenId) * price / (10 ** decimals);

                valueDebt += aToken6909.totalSupply(debtTokenId) * price / (10 ** decimals);
            }

            assertGte(valueColl, valueDebt, "516");
        }
    }

    /// @custom:invariant 517 - The `liquidityIndex` should monotonically increase when there is collateral.
    /// @custom:invariant 518 - The `variableBorrowIndex` should monotonically increase when there is debt.
    function indexIntegrityMP() public {
        for (uint256 j = 0; j < totalNbMinipool; j++) {
            MiniPool minipool = miniPools[j];
            ATokenERC6909 aToken6909 = aTokens6909[j];

            for (uint256 i = 0; i < totalNbTokens * 2; i++) {
                address asset = allTokens(i);

                uint256 currentLiquidityIndex = minipool.getReserveData(asset).liquidityIndex;
                uint256 currentVariableBorrowIndex =
                    minipool.getReserveData(asset).variableBorrowIndex;

                (uint256 aTokenID, uint256 debtTokenID,) = aToken6909.getIdForUnderlying(asset);

                if (hasCollateralTokens6909(j, aTokenID)) {
                    assertGte(
                        currentLiquidityIndex, lastLiquidityIndexMP[address(minipool)][asset], "517"
                    );
                } else {
                    assertEq(
                        currentLiquidityIndex, lastLiquidityIndexMP[address(minipool)][asset], "517"
                    );
                }

                if (hasDebtTokens6909(j, debtTokenID)) {
                    assertGte(
                        currentVariableBorrowIndex,
                        lastVariableBorrowIndexMP[address(minipool)][asset],
                        "518"
                    );
                } else {
                    assertEq(
                        currentVariableBorrowIndex,
                        lastVariableBorrowIndexMP[address(minipool)][asset],
                        "518"
                    );
                }

                lastLiquidityIndexMP[address(minipool)][asset] = currentLiquidityIndex;
                lastVariableBorrowIndexMP[address(minipool)][asset] = currentVariableBorrowIndex;
            }
        }
    }

    /// @custom:invariant 519 - A user with debt should have at least an AToken6909 balance `setUsingAsCollateral`.
    function userDebtIntegrityMP() public {
        for (uint256 j = 0; j < totalNbMinipool; j++) {
            for (uint256 i = 0; i < users.length; i++) {
                User user = users[i];
                if (hasDebtTokens6909(user, j)) {
                    assertWithMsg(hasATokens6909Strict(user, j), "519");
                }
            }
        }
    }

    /// @custom:invariant 520 - Integrity of Deposit Cap - aToken supply should never exceed the cap.
    function integrityOfDepositCapMP() public {
        for (uint256 j = 0; j < miniPools.length; j++) {
            MiniPool minipool = miniPools[j];
            ATokenERC6909 aToken6909 = aTokens6909[j];

            for (uint256 i = 0; i < totalNbTokens * 2; i++) {
                address asset = allTokens(i);

                DataTypes.MiniPoolReserveData memory reserve = minipool.getReserveData(asset);

                uint256 depositCap = getDepositCap(reserve.configuration);
                uint8 decimals = ERC20(asset).decimals();
                uint256 aTokenSupply = aToken6909.totalSupply(i);
                if (depositCap != 0) {
                    assertWithMsg(
                        aTokenSupply
                            <= WadRayMath.rayMul(
                                minipool.getReserveNormalizedIncome(asset),
                                depositCap * (10 ** decimals)
                            ),
                        "520"
                    );
                }
            }
        }
    }

    /// @custom:invariant 521 - `UserConfigurationMap` integrity: If a user has a given aToken then `isUsingAsCollateralOrBorrowing` and `isUsingAsCollateral` should return true.
    function userConfigurationMapIntegrityLiquidityMP() public {
        for (uint256 j = 0; j < miniPools.length; j++) {
            MiniPool minipool = miniPools[j];
            ATokenERC6909 aToken6909 = aTokens6909[j];

            for (uint256 i = 0; i < users.length; i++) {
                User user = users[i];
                for (uint256 k = 0; k < totalNbTokens * 2; k++) {
                    (uint256 aTokenId,,) = aToken6909.getIdForUnderlying(address(allTokens(k)));
                    DataTypes.UserConfigurationMap memory userConfig =
                        minipool.getUserConfiguration(address(user));
                    if (
                        aToken6909.balanceOf(address(user), aTokenId) != 0
                            && !isUseReserveAsCollateralDeactivatedMP[j][address(user)][address(
                                allTokens(k)
                            )]
                    ) {
                        assertWithMsg(
                            UserConfiguration.isUsingAsCollateralOrBorrowing(userConfig, k), "521"
                        );
                        assertWithMsg(UserConfiguration.isUsingAsCollateral(userConfig, k), "521");
                    }
                }
            }
        }
    }

    /// @custom:invariant 522 - `UserConfigurationMap` integrity: If a user has a given debtToken then `isUsingAsCollateralOrBorrowing`, `isBorrowing` and `isBorrowingAny` should return true.
    function userConfigurationMapIntegrityDebtMP() public {
        for (uint256 j = 0; j < miniPools.length; j++) {
            MiniPool minipool = miniPools[j];
            ATokenERC6909 aToken6909 = aTokens6909[j];

            for (uint256 i = 0; i < users.length; i++) {
                User user = users[i];
                for (uint256 k = 0; k < totalNbTokens * 2; k++) {
                    (, uint256 debtTokenId,) = aToken6909.getIdForUnderlying(address(allTokens(k)));

                    DataTypes.UserConfigurationMap memory userConfig =
                        minipool.getUserConfiguration(address(user));

                    if (aToken6909.balanceOf(address(user), debtTokenId) != 0) {
                        assertWithMsg(
                            UserConfiguration.isUsingAsCollateralOrBorrowing(userConfig, k), "522"
                        );
                        assertWithMsg(UserConfiguration.isBorrowing(userConfig, k), "522");
                        assertWithMsg(UserConfiguration.isBorrowingAny(userConfig), "522");
                    }
                }
            }
        }
    }

    /// @custom:invariant 523 - If a minipool is flow borrowing, for a given reserve, the Lendingpool liquidity interest rate remain lower than the minipool debt interest rate.
    /// @custom:invariant 524 - The aToken remainder of each assets with flow borrowing activated should remain greater than ERROR_REMAINDER_MARGIN.
    function flowBorrowingIntegrityMP() public {
        for (uint256 j = 0; j < miniPools.length; j++) {
            MockMiniPool minipool = MockMiniPool(address(miniPools[j]));

            for (uint256 k = 0; k < totalNbTokens; k++) {
                address asset = address(assets[k]);
                uint256 currentFlow = IFlowLimiter(miniPoolProvider.getFlowLimiter()).currentFlow(
                    asset, address(minipool)
                );

                if (currentFlow != 0) {
                    uint256 minipoolRate = minipool.getDebtInterestRate(asset);
                    uint256 lendingPoolRate = pool.getLiquidityInterestRate(asset, true);

                    assertLte(lendingPoolRate, minipoolRate, "523");
                }

                ATokenERC6909 aToken6909 = aTokens6909[j];
                (uint256 aTokenId,,) = aToken6909.getIdForUnderlying(asset);
                uint256 minipoolRemainder = aToken6909.balanceOf(address(minipool), aTokenId);

                uint256 lastRemainder = lastATokenRemainder[address(minipool)][asset];
                uint256 minRemainder = minipool.ERROR_REMAINDER_MARGIN();
                lastATokenRemainder[address(minipool)][asset] = minipoolRemainder;
                assertGte(
                    minipoolRemainder,
                    lastRemainder < minRemainder ? lastRemainder : minRemainder,
                    "524"
                );
            }
        }
    }

    /// @custom:invariant 525 - If a minipool is flow borrowing then its address must be included in `LendingPool._minipoolFlowBorrowing`.
    /// @custom:invariant 526 - If a minipool is not flow borrowing then its address must not be included in `LendingPool._minipoolFlowBorrowing`.
    function checkMinipoolFlowBorrowingMP() public {
        for (uint256 j = 0; j < miniPools.length; j++) {
            MockMiniPool minipool = MockMiniPool(address(miniPools[j]));

            for (uint256 k = 0; k < totalNbTokens; k++) {
                address asset = address(assets[k]);
                uint256 currentFlow = IFlowLimiter(miniPoolProvider.getFlowLimiter()).currentFlow(
                    asset, address(minipool)
                );

                if (currentFlow != 0) {
                    assertWithMsg(pool.isMinipoolFlowBorrowing(asset, address(minipool)), "525");
                } else {
                    assertWithMsg(!pool.isMinipoolFlowBorrowing(asset, address(minipool)), "526");
                }
            }
        }
    }

    // ---------------------- Helpers ----------------------
}
