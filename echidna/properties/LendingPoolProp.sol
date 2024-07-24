// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../GranaryPropertiesBase.sol";
import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";


contract LendingPoolProp is GranaryPropertiesBase {
    constructor() {}

    // --------------------- state updates ---------------------

    /// @custom:invariant 200 - Users must always be able to deposit in normal condition.
    /// @custom:invariant 201 - `deposit()` must increase the user aToken balance by `amount`.
    /// @custom:invariant 202 - `deposit()` must decrease the user asset balance by `amount`.
    function randDeposit(LocalVars_UPTL memory vul, uint seedUser, uint seedOnBeHalfOf, uint seedAsset, uint seedAmt) public {
        randUpdatePriceAndTryLiquidate(vul);
        
        uint randUser = clampBetween(seedUser, 0 ,totalNbUsers);
        uint randOnBehalfOf = clampBetween(seedOnBeHalfOf, 0 ,totalNbUsers);
        uint randAsset = clampBetween(seedAsset, 0 ,totalNbTokens);

        User user = users[randUser];
        User onBehalfOf  = users[randOnBehalfOf];
        ERC20 asset = assets[randAsset];
        AToken aToken = aTokens[randAsset];

        uint randAmt = clampBetween(seedAmt, 1, asset.balanceOf(address(user)) / 2);

        uint aTokenBalanceBefore = aToken.balanceOf(address(onBehalfOf));
        uint assetBalanceBefore = asset.balanceOf(address(user));

        (bool success, ) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.deposit.selector,
                address(asset),
                false,
                randAmt,
                address(onBehalfOf)
            )
        );
        assertWithMsg(success, "200");

        uint aTokenBalanceAfter = aToken.balanceOf(address(onBehalfOf));
        uint assetBalanceAfter = asset.balanceOf(address(user));
        assertEqApprox(aTokenBalanceAfter - aTokenBalanceBefore, randAmt, 1, "201");
        assertEq(assetBalanceBefore - assetBalanceAfter, randAmt, "202");
    }

    /// @custom:invariant 203 - `withdraw()` must decrease the user aToken balance by `amount`.
    /// @custom:invariant 204 - `withdraw()` must increase the user asset balance by `amount`.
    function randWithdraw(LocalVars_UPTL memory vul, uint seedUser, uint seedTo, uint seedAsset, uint seedAmt) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint randUser = clampBetween(seedUser, 0 ,totalNbUsers);
        uint randTo = clampBetween(seedTo, 0 ,totalNbUsers);
        uint randAsset = clampBetween(seedAsset, 0 ,totalNbTokens);

        User user = users[randUser];
        User to  = users[randTo];
        ERC20 asset = assets[randAsset];
        AToken aToken = aTokens[randAsset];

        uint aTokenBalanceBefore = aToken.balanceOf(address(user));
        uint assetBalanceBefore = asset.balanceOf(address(to));

        uint randAmt = clampBetween(seedAmt, 0, aTokenBalanceBefore);

        (bool success, ) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.withdraw.selector,
                address(asset),
                false,
                randAmt,
                address(to)
            )
        );
        require(success);

        uint aTokenBalanceAfter = aToken.balanceOf(address(user));
        uint assetBalanceAfter = asset.balanceOf(address(to));
        assertEqApprox(aTokenBalanceBefore - aTokenBalanceAfter, randAmt, 1, "203");
        assertEq(assetBalanceAfter - assetBalanceBefore, randAmt, "204");
    }

    /// @custom:invariant 205 - A user must not be able to `borrow()` if he doesn't own aTokens.
    /// @custom:invariant 206 - `borrow()` must only be possible if the user health factor is greater than 1.
    /// @custom:invariant 207 - `borrow()` must not result in a health factor of less than 1.
    /// @custom:invariant 208 - `borrow()` must increase the user debtToken balance by `amount`.
    /// @custom:invariant 209 - `borrow()` must decrease `borrowAllowance()` by `amount` if `user != onBehalf`.
    function randBorrow(LocalVars_UPTL memory vul, uint seedUser, uint seedOnBeHalfOf, uint seedAsset, uint seedAmt) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint randUser = clampBetween(seedUser, 0 ,totalNbUsers);
        uint randOnBehalfOf = clampBetween(seedOnBeHalfOf, 0 ,totalNbUsers);
        uint randAsset = clampBetween(seedAsset, 0 ,totalNbTokens);

        User onBehalfOf  = users[randOnBehalfOf];
        ERC20 asset = assets[randAsset];
        VariableDebtToken debtToken = debtTokens[randAsset];
        User user = users[randUser];

        uint randAmt = clampBetween(seedAmt, 1, pool.getUserMaxBorrowCapacity(address(onBehalfOf) , address(asset), false));

        bool success;
        if (address(user) != address(onBehalfOf)) {
            (success, ) = onBehalfOf.proxy(
                address(debtToken),
                abi.encodeWithSelector(
                    debtToken.approveDelegation.selector,
                    address(user),
                    randAmt
                )
            );
            assert(success);
        }
        
        uint borrowAllowanceBefore = debtToken.borrowAllowance(address(onBehalfOf), address(user));
        uint vTokenBalanceBefore = debtToken.balanceOf(address(onBehalfOf));
        (,,,,, uint256 healthFactorBefore) = pool.getUserAccountData(address(onBehalfOf));

        (success, ) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.borrow.selector,
                address(asset),
                false,
                randAmt,
                address(onBehalfOf)
            )
        );

        if (!hasATokens(onBehalfOf)) 
            assertWithMsg(!success, "205");

        if (healthFactorBefore < 1e18)
            assertWithMsg(!success, "206");

        (,,,,, uint256 healthFactorAfter) = pool.getUserAccountData(address(onBehalfOf));
        if (healthFactorAfter < 1e18)
            assertWithMsg(!success, "207");

        require(success);

        uint vTokenBalanceAfter = debtToken.balanceOf(address(onBehalfOf));
        assertEqApprox(vTokenBalanceAfter - vTokenBalanceBefore, randAmt, 1, "208");

        if (address(user) != address(onBehalfOf))
            assertEq(borrowAllowanceBefore, debtToken.borrowAllowance(address(onBehalfOf), address(user)) + randAmt, "209");

    }

    /// @custom:invariant 210 - `repay()` must decrease the onBehalfOf debtToken balance by `amount`.
    /// @custom:invariant 211 - `repay()` must decrease the user asset balance by `amount`.
    /// @custom:invariant 212 - `healthFactorAfter` must be greater than `healthFactorBefore`.
    function randRepay(LocalVars_UPTL memory vul, uint seedUser, uint seedOnBeHalfOf, uint seedAsset, uint seedAmt) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint randUser = clampBetween(seedUser, 0 ,totalNbUsers);
        uint randOnBehalfOf = clampBetween(seedOnBeHalfOf, 0 ,totalNbUsers);
        uint randAsset = clampBetween(seedAsset, 0 ,totalNbTokens);

        User user = users[randUser];
        User onBehalfOf = users[randOnBehalfOf];
        ERC20 asset = assets[randAsset];
        AToken aToken = aTokens[randAsset];
        VariableDebtToken debtToken = debtTokens[randAsset];

        uint vTokenBalanceBefore = debtToken.balanceOf(address(onBehalfOf));
        uint assetBalanceBefore = asset.balanceOf(address(user));
        (,,,,, uint256 healthFactorBefore) = pool.getUserAccountData(address(onBehalfOf));

        uint randAmt = clampBetween(seedAmt, 0, vTokenBalanceBefore);    

        (bool success, ) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.repay.selector,
                address(asset),
                false,
                randAmt,
                address(onBehalfOf)
            )
        );

        require(success);
        
        uint vTokenBalanceAfter = debtToken.balanceOf(address(onBehalfOf));
        uint assetBalanceAfter = asset.balanceOf(address(user));
        (,,,,, uint256 healthFactorAfter) = pool.getUserAccountData(address(onBehalfOf));

        assertEqApprox(vTokenBalanceBefore - vTokenBalanceAfter, randAmt, 1, "210");
        assertEqApprox(assetBalanceBefore - assetBalanceAfter, randAmt, 1, "211");
        assertGte(healthFactorAfter, healthFactorBefore, "212");
    }
    
    /// @custom:invariant 213 - `setUseReserveAsCollateral` must not reduce the health factor below 1.
    function randSetUseReserveAsCollateral(LocalVars_UPTL memory vul, uint seedUser, uint seedAsset, bool randIsColl) public {
        randUpdatePriceAndTryLiquidate(vul);

        uint randUser = clampBetween(seedUser, 0 ,totalNbUsers);
        uint randAsset = clampBetween(seedAsset, 0 ,totalNbTokens);

        User user = users[randUser];
        ERC20 asset = assets[randAsset];

        (,,,,, uint256 healthFactorBefore) = pool.getUserAccountData(address(user));

        (bool success, ) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.setUserUseReserveAsCollateral.selector,
                address(asset),
                false,
                randIsColl
            )   
        );
        require(success);

        (,,,,, uint256 healthFactorAfter) = pool.getUserAccountData(address(user));
        if (randIsColl)
            assertLte(healthFactorBefore, healthFactorAfter, "213");        
        else
            assertGte(healthFactorBefore, healthFactorAfter, "213");

        if (healthFactorAfter != healthFactorBefore)
            assertGte(healthFactorAfter, 1e18, "213");
    }

    struct LocalVars_RandFlashloan {
        uint randUser;
        uint randAsset;
        uint randMode;
        uint randNbAssets;
        uint randAmt;

        User user;

        ERC20 asset;
        VariableDebtToken debtToken;

        address[] assetsFl;
        bool[] reserveTypesFl;
        uint256[] amountsFl;
        uint256[] modesFl;
        bytes params;
        uint256[] assetBalanceBefore;
    }

    /// @custom:invariant 214 - Users must not be able to steal funds from flashloans.
    function randFlashloan(LocalVars_UPTL memory vul, uint seedUser, uint seedAsset, uint seedMode, uint seedNbAssetFl, uint seedAmt) public {
        randUpdatePriceAndTryLiquidate(vul);
        
        LocalVars_RandFlashloan memory v;

        v.randUser = clampBetween(seedUser, 0 ,totalNbUsers);
        v.randAsset = clampBetween(seedAsset, 0 ,totalNbTokens);
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

        v.randAmt = clampBetween(seedAmt, 1, v.asset.balanceOf(address(aTokens[v.randAsset])));

        v.assetBalanceBefore = new uint256[](v.randNbAssets);

        for (uint256 i = 0; i < v.randNbAssets; i++) {
            v.assetBalanceBefore[i] = assets[i].balanceOf(address(v.user));
            v.assetsFl[i] = address(assets[i]);
            v.reserveTypesFl[i] = false;
            uint256 maxFlashloanable = assets[i].balanceOf(address(aTokens[i]));
            v.amountsFl[i] = v.randAmt > maxFlashloanable ? maxFlashloanable : v.randAmt;
            v.modesFl[i] = v.randMode;
        }

        ILendingPool.FlashLoanParams memory flp = ILendingPool.FlashLoanParams({
            receiverAddress: address(v.user),
            assets: v.assetsFl,
            reserveTypes: v.reserveTypesFl,
            onBehalfOf: address(v.user)
        });

        v.user.execFl(
            flp,
            v.amountsFl,
            v.modesFl,
            v.params
        );

        for (uint256 i = 0; i < v.randNbAssets; i++) {
            assertGte(v.assetBalanceBefore[i] , assets[i].balanceOf(address(v.user)), "214");
        }

        // Premium payment increase indexes => update last indexes
        for (uint i = 0; i < assets.length; i++) {
            address asset = address(assets[i]);
            lastLiquidityIndex[asset] = pool.getReserveData(asset, false).liquidityIndex;
            lastVariableBorrowIndex[asset] = pool.getReserveData(asset, false).variableBorrowIndex;
        }
    }

    // ---------------------- Invariants ----------------------
    
    /// @custom:invariant 215 - The total value borrowed must always be less than the value of the collaterals.
    function globalSolvencyCheck() public {
        uint valueColl;
        uint valueDebt;
        for (uint i = 0; i < aTokens.length; i++) {
            AToken aToken = aTokens[i];
            MockAggregator aTokenOracle = aggregators[i];
            
            valueColl += aToken.totalSupply() * uint(aggregators[i].latestAnswer()) / (10 ** assets[i].decimals());
        }

        for (uint i = 0; i < debtTokens.length; i++) {
            VariableDebtToken vToken = debtTokens[i];
            MockAggregator aTokenOracle = aggregators[i];
            
            valueDebt += vToken.totalSupply() * uint(aggregators[i].latestAnswer()) / (10 ** assets[i].decimals());
        }

        assertGte(valueColl, valueDebt, "215");
    }

    /// @custom:invariant 216 - each user postions must remain solvent.
    function usersSolvencyCheck() public {
        for (uint256 j = 0; j < users.length; j++) {
            User user = users[j];
            uint valueColl = 0;
            uint valueDebt = 0;

            for (uint i = 0; i < aTokens.length; i++)
                valueColl += aTokens[i].balanceOf(address(user)) * uint(aggregators[i].latestAnswer()) 
                                / (10 ** assets[i].decimals());

            for (uint i = 0; i < debtTokens.length; i++)                 
                valueDebt += debtTokens[i].balanceOf(address(user)) * uint(aggregators[i].latestAnswer()) 
                                / (10 ** assets[i].decimals());
            
            assertGte(valueColl, valueDebt, "216");
        }
    }

    /// @custom:invariant 217 - The `liquidityIndex` should monotonically increase when there's total debt.
    /// @custom:invariant 218 - The `variableBorrowIndex` should monotonically increase when there's total debt.
    function indexIntegrity() public {
        for (uint i = 0; i < assets.length; i++) {
            address asset = address(assets[i]);

            uint currentLiquidityIndex = pool.getReserveData(asset, false).liquidityIndex;
            uint currentVariableBorrowIndex = pool.getReserveData(asset, false).variableBorrowIndex;

            if (hasDebtTotal()) {
                assertGte(currentLiquidityIndex, lastLiquidityIndex[asset], "217");
                assertGte(currentVariableBorrowIndex, lastVariableBorrowIndex[asset], "218");
            }
            else {
                assertEq(currentLiquidityIndex, lastLiquidityIndex[asset], "217");
                assertEq(currentVariableBorrowIndex, lastVariableBorrowIndex[asset], "218");
            }
            lastLiquidityIndex[asset] = currentLiquidityIndex;
            lastVariableBorrowIndex[asset] = currentVariableBorrowIndex;
        }
    }

    /// @custom:invariant 219 - A user with debt should have at least an aToken balance `setUsingAsCollateral`.
    function userDebtIntegrity() public {
        for (uint i = 0; i < users.length; i++) {
            User user = users[i];
            if (hasDebt(user))
                assertWithMsg(hasDebt(user), "219");
        }
    }

    /// @custom:invariant 220 - If all debt is repaid, all `aToken` holder should be able to claim their collateral.
    /// @custom:invariant 221 - If all users withdraw their liquidity, there must not be aTokens supply left. 
    // function usersFullCollateralClaim() public {
    //     if (!hasDebtTotal()) {
    //         for (uint i = 0; i < users.length; i++) {
    //             User user = users[i];
    //             for (uint256 j = 0; j < aTokens.length; j++) {
    //                 uint balanceAToken = aTokens[j].balanceOf(address(user));
    //                 if (balanceAToken != 0) {
    //                     (bool success, ) = user.proxy(
    //                         address(pool),
    //                         abi.encodeWithSelector(
    //                             pool.withdraw.selector,
    //                             address(assets[j]),
    //                             false,
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
    //                 uint balanceAToken = aTokens[j].balanceOf(address(bootstraper));
    //                 if (balanceAToken != 0) {
    //                     (bool success, ) = bootstraper.proxy(
    //                         address(pool),
    //                         abi.encodeWithSelector(
    //                             pool.withdraw.selector,
    //                             address(assets[j]),
    //                             false,
    //                             balanceAToken,
    //                             address(bootstraper)
    //                         )
    //                     );
    //                     assertWithMsg(success, "220");
    //                 }
    //             }
    //         }
    //         // assertWithMsg(!hasATokenTotal(), "221");
    //     }
    // }
}
