// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolDepositBorrow.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {LendingPoolTest} from "./LendingPool.t.sol";
import {MockStrategy} from "../../contracts/mocks/tokens/MockStrategy.sol";

import "forge-std/StdUtils.sol";

// // struct InitReserveInput {
// //     address aTokenImpl;
// //     address variableDebtTokenImpl;
// //     uint8 underlyingAssetDecimals;
// //     address interestRateStrategyAddress;
// //     address underlyingAsset;
// //     address treasury;
// //     address incentivesController;
// //     string underlyingAssetName;
// //     bool reserveType;
// //     string aTokenName;
// //     string aTokenSymbol;
// //     string variableDebtTokenName;
// //     string variableDebtTokenSymbol;
// //     bytes params;
// // }

contract RehypothecationTest is Common, LendingPoolTest {
    function testRebalance(uint256 idx) public {
        idx = bound(idx, 0, tokens.length - 1);
        ERC20 token = erc20Tokens[idx];
        uint256 depositSize = 10 ** token.decimals();

        token.approve(address(deployedContracts.lendingPool), type(uint256).max);
        deployedContracts.lendingPool.deposit(address(token), true, depositSize, address(this));
        turnOnRehypothecation(
            deployedContracts.lendingPoolConfigurator,
            address(commonContracts.aTokens[idx]),
            address(commonContracts.mockVaultUnits[idx]),
            admin,
            2000,
            10 ** (token.decimals() - 1),
            200
        );

        assertEq(token.balanceOf(address(commonContracts.aTokens[idx])), depositSize);

        vm.startPrank(admin);
        deployedContracts.lendingPoolConfigurator.setPoolPause(true);
        deployedContracts.lendingPoolConfigurator.rebalance(address(commonContracts.aTokens[idx]));
        vm.stopPrank();

        uint256 remainingPct = 10000 - (commonContracts.aTokens[idx]._farmingPct());
        assertEq(
            token.balanceOf(address(commonContracts.aTokens[idx])),
            depositSize * remainingPct / 10000
        );
        assertEq(commonContracts.aTokens[idx].getTotalManagedAssets(), depositSize);
    }

    function testDepositAndWithdrawYield(uint256 timeDiff) public {
        timeDiff = 100 days; // bound(timeDiff, 0, 1000 days);
        // idx = bound(idx, 0, tokens.length - 1);
        TokenTypes memory usdcTypes = TokenTypes({
            token: erc20Tokens[0],
            aToken: commonContracts.aTokens[0],
            debtToken: commonContracts.variableDebtTokens[0]
        });

        TokenTypes memory wbtcTypes = TokenTypes({
            token: erc20Tokens[1],
            aToken: commonContracts.aTokens[1],
            debtToken: commonContracts.variableDebtTokens[1]
        });
        MockVaultUnit wbtcVault = commonContracts.mockVaultUnits[1];
        uint256 depositSize = 10000 * 10 ** usdcTypes.token.decimals();

        address user = makeAddr("user");

        uint256 initialAdminBalance = wbtcTypes.token.balanceOf(address(admin));
        uint256 availableFundsAfterBorrow;
        deal(address(usdcTypes.token), address(this), 2 * depositSize);
        uint256 maxValToBorrow =
            fixture_getMaxValueToBorrow(usdcTypes.token, wbtcTypes.token, depositSize);
        deal(address(wbtcTypes.token), user, 2 * maxValToBorrow);
        {
            (uint256 maxBorrowTokenToBorrowInCollateralUnit) =
                fixture_depositAndBorrow(usdcTypes, wbtcTypes, user, address(this), depositSize);

            turnOnRehypothecation(
                deployedContracts.lendingPoolConfigurator,
                address(wbtcTypes.aToken),
                address(wbtcVault),
                admin,
                2000,
                10 ** (wbtcTypes.token.decimals() - 3), // 0.001 WBTC
                200
            );

            console2.log("maxValToBorrow: ", maxValToBorrow);
            console2.log(
                "maxBorrowTokenToBorrowInCollateralUnit: ", maxBorrowTokenToBorrowInCollateralUnit
            );
            availableFundsAfterBorrow = (maxBorrowTokenToBorrowInCollateralUnit * 15 / 10)
                - maxBorrowTokenToBorrowInCollateralUnit;
        }
        // Starting here, vault should be able to handle asset
        assertEq(
            wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)),
            availableFundsAfterBorrow,
            "WBTC amount wrong"
        );
        assertEq(
            usdcTypes.token.balanceOf(address(usdcTypes.aToken)), depositSize, "USDC amount wrong"
        );

        uint256 remainingPct = 10000 - (wbtcTypes.aToken._farmingPct());
        console2.log("1. WBTC amount: ", wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)));
        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.rebalance(address(wbtcTypes.aToken));
        console2.log("2. WBTC amount: ", wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)));
        console2.log("2. ", (availableFundsAfterBorrow * remainingPct));
        assertApproxEqAbs(
            wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)),
            ((availableFundsAfterBorrow * remainingPct) + 5000) / 10000,
            1,
            "WBTC amount after rebalance is wrong"
        );
        uint256 vaultBalanceAfterFirstRebalance = wbtcTypes.token.balanceOf(address(wbtcVault));
        uint256 tokenBalanceAfterFirstRebalance =
            wbtcTypes.token.balanceOf(address(wbtcTypes.aToken));

        assertEq(
            vaultBalanceAfterFirstRebalance,
            availableFundsAfterBorrow * (wbtcTypes.aToken._farmingPct()) / 10000,
            "WBTC vault amount after rebalance is wrong"
        );
        console2.log("1. Balance in vault: ", vaultBalanceAfterFirstRebalance);
        console2.log(
            "1. totalSupply: %s, totalAsset: %s", wbtcVault.totalSupply(), wbtcVault.totalAssets()
        );
        console2.log("TimeDiff: ", timeDiff);
        skip(timeDiff);

        // Artificially increasing balance of vault should result in yield for the graintoken
        uint256 yieldAmount;
        {
            uint256 index = deployedContracts.lendingPool.getReserveNormalizedIncome(
                address(wbtcTypes.token), true
            );
            console2.log("index: ", index);
            yieldAmount = index * wbtcVault.totalSupply() / 1e27 - wbtcVault.totalSupply();
            console2.log("yieldAmount: ", yieldAmount);
            console2.log(
                "1.5 BEFORE: totalSupply: %s, totalAsset: %s",
                wbtcVault.totalSupply(),
                wbtcVault.totalAssets()
            );
            deal(
                address(wbtcTypes.token), address(wbtcVault), wbtcVault.totalSupply() + yieldAmount
            );
            console2.log(
                "1.5 AFTER DEAL: totalSupply: %s, totalAsset: %s",
                wbtcVault.totalSupply(),
                wbtcVault.totalAssets()
            );
        }

        console2.log("2. Balance in vault: ", wbtcTypes.token.balanceOf(address(wbtcVault)));
        console2.log(
            "2. totalSupply: %s, totalAsset: %s", wbtcVault.totalSupply(), wbtcVault.totalAssets()
        );
        skip(timeDiff);
        console2.log("3. Balance in vault: ", wbtcTypes.token.balanceOf(address(wbtcVault)));
        console2.log(
            "3. totalSupply: %s, totalAsset: %s", wbtcVault.totalSupply(), wbtcVault.totalAssets()
        );

        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.rebalance(address(wbtcTypes.aToken));
        assertApproxEqAbs(
            tokenBalanceAfterFirstRebalance,
            wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)),
            1,
            "Token's balance is not the same as before rebalance"
        );
        console2.log(
            "Vault balance %s vs expected: %s",
            wbtcTypes.token.balanceOf(address(wbtcVault)),
            vaultBalanceAfterFirstRebalance
        );
        assertApproxEqAbs(
            wbtcTypes.token.balanceOf(address(wbtcVault)),
            vaultBalanceAfterFirstRebalance,
            1,
            "Vault balance is not the same as before rebalance"
        );
        console2.log(
            "Admin balance %s vs profit: %s", wbtcTypes.token.balanceOf(address(admin)), yieldAmount
        );
        assertApproxEqAbs(
            wbtcTypes.token.balanceOf(address(admin)),
            initialAdminBalance + yieldAmount,
            1,
            "Profit handler doesn't have profit"
        );
    }

    struct TokenVars {
        MockVaultUnit vault;
        uint256 depositSize;
        uint256 initialBalance;
        uint256 remainingPct;
    }

    function testRehypothecationWithVariousVaultReturns(uint256 vaultReturnPct, uint256 amount)
        public
    {
        vaultReturnPct = bound(vaultReturnPct, 10, 19000); //0.01% to 200 %
        for (uint8 idx = 0; idx < tokens.length; idx++) {
            amount = bound(amount, 1e2, erc20Tokens[idx].balanceOf(address(this)));
            TokenTypes memory tokenTypes = TokenTypes({
                token: erc20Tokens[idx],
                aToken: commonContracts.aTokens[idx],
                debtToken: commonContracts.variableDebtTokens[idx]
            });
            TokenVars memory tokenVars = TokenVars({
                vault: commonContracts.mockVaultUnits[idx],
                depositSize: amount,
                initialBalance: tokenTypes.token.balanceOf(address(this)),
                remainingPct: 0
            });
            turnOnRehypothecation(
                deployedContracts.lendingPoolConfigurator,
                address(tokenTypes.aToken),
                address(tokenVars.vault),
                admin,
                8000,
                erc20Tokens[idx].balanceOf(address(this)), // make profit unreachable in this test
                200
            );
            fixture_deposit(
                tokenTypes.token,
                tokenTypes.aToken,
                address(this),
                address(this),
                tokenVars.depositSize
            );
            tokenVars.remainingPct = 10000 - (tokenTypes.aToken._farmingPct());

            assertApproxEqAbs(
                tokenTypes.token.balanceOf(address(tokenTypes.aToken)),
                ((tokenVars.depositSize * tokenVars.remainingPct) + 5000) / 10000,
                1,
                "token amount in aToken is wrong"
            );
            uint256 expectedVaultBalance =
                (tokenVars.depositSize * tokenTypes.aToken._farmingPct() + 5000) / 10000;
            assertApproxEqAbs(
                tokenTypes.token.balanceOf(address(tokenVars.vault)),
                expectedVaultBalance,
                1,
                "token amount in vault is wrong"
            );

            uint256 absReturn =
                tokenTypes.token.balanceOf(address(tokenVars.vault)) * vaultReturnPct / 10000;
            deal(address(tokenTypes.token), address(tokenVars.vault), absReturn);
            // aToken rebalance shall be done despite of negative (< vault balance) or positive return
            console2.log("Rebalancing for value: %s vs %s", absReturn, expectedVaultBalance);
            vm.startPrank(admin);
            if (absReturn < expectedVaultBalance + 2 && absReturn > expectedVaultBalance - 2) {
                deployedContracts.lendingPoolConfigurator.rebalance(address(tokenTypes.aToken));
                assertApproxEqAbs(
                    tokenTypes.token.balanceOf(address(tokenVars.vault)),
                    tokenTypes.token.balanceOf(address(tokenVars.vault)),
                    1,
                    "token amount in vault is not the same after rebalance"
                );
            } else if (absReturn < expectedVaultBalance) {
                // Negative return
                deployedContracts.lendingPoolConfigurator.rebalance(address(tokenTypes.aToken));
                // Refund
                deal(address(tokenTypes.token), address(tokenVars.vault), expectedVaultBalance);
                deployedContracts.lendingPoolConfigurator.rebalance(address(tokenTypes.aToken));
                assertApproxEqAbs(
                    tokenTypes.token.balanceOf(address(tokenVars.vault)),
                    tokenTypes.token.balanceOf(address(tokenVars.vault)),
                    1,
                    "token amount in vault is wrong after rebalance and refund"
                );
            } else {
                deployedContracts.lendingPoolConfigurator.rebalance(address(tokenTypes.aToken));
                assertGt(
                    tokenTypes.token.balanceOf(address(tokenVars.vault)),
                    expectedVaultBalance,
                    "token amount in vault is wrong after rebalance"
                );
            }

            vm.stopPrank();
        }
    }

    function testDepositBorrowRepayAndWithdrawWithRehypoOn(uint256 timeDiff) public {
        timeDiff = 100 days; // bound(timeDiff, 0, 1000 days);
        // idx = bound(idx, 0, tokens.length - 1);
        TokenTypes memory usdcTypes = TokenTypes({
            token: erc20Tokens[0],
            aToken: commonContracts.aTokens[0],
            debtToken: commonContracts.variableDebtTokens[0]
        });

        TokenTypes memory wbtcTypes = TokenTypes({
            token: erc20Tokens[1],
            aToken: commonContracts.aTokens[1],
            debtToken: commonContracts.variableDebtTokens[1]
        });

        TokenVars memory usdcVars = TokenVars({
            vault: commonContracts.mockVaultUnits[0],
            depositSize: 10000 * 10 ** usdcTypes.token.decimals(),
            initialBalance: usdcTypes.token.balanceOf(address(this)),
            remainingPct: 0
        });
        TokenVars memory wbtcVars = TokenVars({
            vault: commonContracts.mockVaultUnits[1],
            depositSize: 10 ** (wbtcTypes.token.decimals() - 1),
            initialBalance: wbtcTypes.token.balanceOf(address(this)),
            remainingPct: 0
        });

        address user = makeAddr("user");

        uint256 availableFundsAfterBorrow;
        uint256 maxBorrowTokenToBorrowInCollateralUnit;
        {
            turnOnRehypothecation(
                deployedContracts.lendingPoolConfigurator,
                address(usdcTypes.aToken),
                address(usdcVars.vault),
                admin,
                2000,
                10 ** (usdcTypes.token.decimals()), // 1 USDC
                200
            );

            turnOnRehypothecation(
                deployedContracts.lendingPoolConfigurator,
                address(wbtcTypes.aToken),
                address(wbtcVars.vault),
                admin,
                2000,
                10 ** (wbtcTypes.token.decimals() - 3), // 0.001 WBTC
                200
            );

            deal(address(usdcTypes.token), address(this), 2 * usdcVars.depositSize);
            maxBorrowTokenToBorrowInCollateralUnit =
                fixture_getMaxValueToBorrow(usdcTypes.token, wbtcTypes.token, usdcVars.depositSize);
            deal(address(wbtcTypes.token), user, 2 * maxBorrowTokenToBorrowInCollateralUnit);

            usdcVars.initialBalance = usdcTypes.token.balanceOf(address(this));
            wbtcVars.initialBalance = wbtcTypes.token.balanceOf(address(this));

            maxBorrowTokenToBorrowInCollateralUnit = fixture_depositAndBorrow(
                usdcTypes, wbtcTypes, user, address(this), usdcVars.depositSize
            );
            console2.log(
                "maxBorrowTokenToBorrowInCollateralUnit: ", maxBorrowTokenToBorrowInCollateralUnit
            );
            availableFundsAfterBorrow = (maxBorrowTokenToBorrowInCollateralUnit * 15 / 10)
                - maxBorrowTokenToBorrowInCollateralUnit;
        }
        // Starting here, vault should be able to handle asset
        usdcVars.remainingPct = 10000 - (usdcTypes.aToken._farmingPct());
        wbtcVars.remainingPct = 10000 - (wbtcTypes.aToken._farmingPct());

        assertApproxEqAbs(
            usdcTypes.token.balanceOf(address(usdcTypes.aToken)),
            ((usdcVars.depositSize * usdcVars.remainingPct) + 5000) / 10000,
            1,
            "USDC amount in aToken is wrong"
        );

        assertApproxEqAbs(
            wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)),
            ((availableFundsAfterBorrow * wbtcVars.remainingPct) + 5000) / 10000,
            1,
            "WBTC amount in aToken is wrong"
        );

        assertApproxEqAbs(
            usdcTypes.token.balanceOf(address(usdcVars.vault)),
            ((usdcVars.depositSize * usdcTypes.aToken._farmingPct()) + 5000) / 10000,
            1,
            "USDC amount in vault is wrong"
        );

        assertApproxEqAbs(
            wbtcTypes.token.balanceOf(address(wbtcVars.vault)),
            ((availableFundsAfterBorrow * wbtcTypes.aToken._farmingPct()) + 5000) / 10000,
            1,
            "WBTC amount in vault is wrong"
        );

        uint256 wbtcBalanceBeforeRepay = wbtcTypes.token.balanceOf(address(this));
        uint256 wbtcDebtBeforeRepay = wbtcTypes.debtToken.balanceOf(address(this));
        console2.log("wbtcBalanceBeforeRepay: ", wbtcBalanceBeforeRepay);
        console2.log("wbtcDebtBeforeRepay: ", wbtcDebtBeforeRepay);

        console2.log(
            "maxBorrowTokenToBorrowInCollateralUnit %s vs availableFundsAfterBorrow %s",
            maxBorrowTokenToBorrowInCollateralUnit,
            availableFundsAfterBorrow
        );

        wbtcTypes.token.approve(
            address(deployedContracts.lendingPool), maxBorrowTokenToBorrowInCollateralUnit
        );
        deployedContracts.lendingPool.repay(
            address(wbtcTypes.token), true, maxBorrowTokenToBorrowInCollateralUnit, address(this)
        );
        assertEq(
            wbtcBalanceBeforeRepay,
            wbtcTypes.token.balanceOf(address(this)) + maxBorrowTokenToBorrowInCollateralUnit,
            "User after repayment has less borrowed tokens"
        );
        assertEq(
            wbtcDebtBeforeRepay,
            wbtcTypes.debtToken.balanceOf(address(this)) + maxBorrowTokenToBorrowInCollateralUnit,
            "User after repayment has less debt"
        );
        console2.log("Debt: ", wbtcTypes.debtToken.balanceOf(address(this)));

        fixture_withdraw(usdcTypes.token, address(this), address(this), usdcVars.depositSize);
        fixture_withdraw(
            wbtcTypes.token,
            user,
            user,
            availableFundsAfterBorrow + maxBorrowTokenToBorrowInCollateralUnit
        );

        assertEq(
            usdcVars.initialBalance,
            usdcTypes.token.balanceOf(address(this)),
            "Balance of usdc at the end is not equal to initial balance"
        );

        assertEq(
            wbtcVars.initialBalance,
            wbtcTypes.token.balanceOf(address(this)),
            "Balance of wbtc at the end is not equal to initial balance"
        );
    }

    /* TEST UNUSED DUE TO LACK OF COMPATIBILITY WITH VAULTV2 BUT CAN BE REUSED IN THE FUTURE */
    // function testDepositAndWithdrawYield(uint256 timeDiff) public {
    //     timeDiff = 100 days; //bound(timeDiff, 0, 1000 days);
    //     // idx = bound(idx, 0, tokens.length - 1);
    //     TokenTypes memory usdcTypes = TokenTypes({
    //         token: erc20Tokens[0],
    //         aToken: aTokens[0],
    //         debtToken: variableDebtTokens[0]
    //     });

    //     TokenTypes memory wbtcTypes = TokenTypes({
    //         token: erc20Tokens[1],
    //         aToken: aTokens[1],
    //         debtToken: variableDebtTokens[1]
    //     });
    //     MockVaultUnit wbtcVault = mockVaultUnits[1];
    //     uint256 depositSize = 10000 * 10 ** usdcTypes.token.decimals();
    //     MockStrategy strat = new MockStrategy(address(wbtcTypes.token), address(wbtcVault));
    //     // mockVaultUnits[1].addStrategy(address(strat), 1000, 8000);
    //     // usdcTypes.token.approve(address(deployedContracts.lendingPool), type(uint256).max);
    //     // deployedContracts.lendingPool.deposit(
    //     //     address(usdcTypes.token), true, depositSize, address(this)
    //     // );
    //     address user = makeAddr("user");

    //     uint256 initialAdminBalance = usdcTypes.token.balanceOf(address(admin));
    //     uint256 availableFundsAfterBorrow;
    //     {
    //         (uint256 maxBorrowTokenToBorrowInCollateralUnit) =
    //             fixture_depositAndBorrow(usdcTypes, wbtcTypes, user, address(this), depositSize);

    //         turnOnRehypothecation(
    //             deployedContracts.lendingPoolConfigurator,
    //             address(wbtcTypes.aToken),
    //             address(wbtcVault),
    //             admin,
    //             2000,
    //             10 ** (wbtcTypes.token.decimals() - 3), // 0.001 WBTC
    //             200
    //         );

    //         uint256 maxValToBorrow =
    //             fixture_getMaxValueToBorrow(usdcTypes.token, wbtcTypes.token, depositSize);
    //         console2.log("maxValToBorrow: ", maxValToBorrow);
    //         console2.log(
    //             "maxBorrowTokenToBorrowInCollateralUnit: ", maxBorrowTokenToBorrowInCollateralUnit
    //         );
    //         availableFundsAfterBorrow = (maxBorrowTokenToBorrowInCollateralUnit * 15 / 10)
    //             - maxBorrowTokenToBorrowInCollateralUnit;
    //     }
    //     // Starting here, vault should be able to handle asset
    //     assertEq(
    //         wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)),
    //         availableFundsAfterBorrow,
    //         "WBTC amount wrong"
    //     );
    //     assertEq(
    //         usdcTypes.token.balanceOf(address(usdcTypes.aToken)), depositSize, "USDC amount wrong"
    //     );

    //     uint256 remainingPct = 10000 - (wbtcTypes.aToken.farmingPct());
    //     console2.log("1. WBTC amount: ", wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)));
    //     vm.prank(admin);
    //     deployedContracts.lendingPoolConfigurator.rebalance(address(wbtcTypes.aToken));
    //     console2.log("2. WBTC amount: ", wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)));
    //     console2.log("2. ", (availableFundsAfterBorrow * remainingPct));
    //     assertApproxEqAbs(
    //         wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)),
    //         ((availableFundsAfterBorrow * remainingPct) + 5000) / 10000,
    //         1,
    //         "WBTC amount after rebalance is wrong"
    //     );
    //     uint256 vaultBalanceAfterFirstRebalance = wbtcTypes.token.balanceOf(address(wbtcVault));
    //     assertApproxEqAbs(
    //         wbtcTypes.token.balanceOf(address(wbtcVault)),
    //         ((2000 * vaultBalanceAfterFirstRebalance) + 5000) / 10000,
    //         1,
    //         "Remaining amount in the vault after harvest is wrong"
    //     );
    //     // assertEq(vaultBalanceAfterFirstRebalance, wbtcVault.balance());
    //     uint256 tokenBalanceAfterFirstRebalance =
    //         wbtcTypes.token.balanceOf(address(wbtcTypes.aToken));

    //     // assertEq(
    //     //     tokenBalanceAfterFirstRebalance,
    //     //     maxValToBorrow * remainingPct / 10000,
    //     //     "WBTC amount after rebalance is wrong"
    //     // );
    //     // assertEq(
    //     //     vaultBalanceAfterFirstRebalance,
    //     //     availableFundsAfterBorrow * (wbtcTypes.aToken.farmingPct()) / 10000,
    //     //     "WBTC vault amount after rebalance is wrong"
    //     // );
    //     console2.log("1. Balance in vault: ", vaultBalanceAfterFirstRebalance);
    //     console2.log(
    //         "1. totalSupply: %s, totalAsset: %s", wbtcVault.totalSupply(), wbtcVault.totalAssets()
    //     );
    //     console2.log("TimeDiff: ", timeDiff);
    //     skip(timeDiff);

    //     // Artificially increasing balance of vault should result in yield for the graintoken
    //     uint256 yieldAmount;
    //     {
    //         uint256 index = deployedContracts.lendingPool.getReserveNormalizedIncome(
    //             address(wbtcTypes.token), true
    //         );
    //         console2.log("index: ", index);
    //         yieldAmount = index * wbtcVault.totalSupply() / 1e27 - wbtcVault.totalSupply();
    //         console2.log("yieldAmount: ", yieldAmount);
    //         console2.log(
    //             "1.5 BEFORE: totalSupply: %s, totalAsset: %s",
    //             wbtcVault.totalSupply(),
    //             wbtcVault.totalAssets()
    //         );
    //         deal(
    //             address(wbtcTypes.token), address(wbtcVault), wbtcVault.totalSupply() + yieldAmount
    //         );
    //         console2.log(
    //             "1.5 AFTER DEAL: totalSupply: %s, totalAsset: %s",
    //             wbtcVault.totalSupply(),
    //             wbtcVault.totalAssets()
    //         );
    //     }

    //     console2.log("2. Balance in vault: ", wbtcTypes.token.balanceOf(address(wbtcVault)));
    //     console2.log(
    //         "2. totalSupply: %s, totalAsset: %s", wbtcVault.totalSupply(), wbtcVault.totalAssets()
    //     );
    //     skip(timeDiff);
    //     strat.harvest();
    //     console2.log("3. Balance in vault: ", wbtcTypes.token.balanceOf(address(wbtcVault)));
    //     console2.log(
    //         "3. totalSupply: %s, totalAsset: %s", wbtcVault.totalSupply(), wbtcVault.totalAssets()
    //     );

    //     vm.prank(admin);
    //     deployedContracts.lendingPoolConfigurator.rebalance(address(wbtcTypes.aToken));
    //     assertEq(
    //         tokenBalanceAfterFirstRebalance,
    //         wbtcTypes.token.balanceOf(address(wbtcTypes.aToken)),
    //         "Token's balance is not the same as before rebalance"
    //     );
    //     console2.log(
    //         "Vault balance %s vs expected: %s",
    //         wbtcTypes.token.balanceOf(address(wbtcVault)),
    //         vaultBalanceAfterFirstRebalance
    //     );
    //     // assertEq(
    //     //     wbtcTypes.token.balanceOf(address(wbtcVault)),
    //     //     depositSize * (wbtcTypes.aToken.farmingPct()) / 10000,
    //     //     "Vault balance is not the same as before rebalance"
    //     // );
    //     console2.log(
    //         "Admin balance %s vs profit: %s", wbtcTypes.token.balanceOf(address(admin)), yieldAmount
    //     );
    //     // assertEq(
    //     //     wbtcTypes.token.balanceOf(address(admin)),
    //     //     initialAdminBalance + yieldAmount,
    //     //     "Profit handler doesn't have profit"
    //     // );
    //     assert(false);
    // }
}
