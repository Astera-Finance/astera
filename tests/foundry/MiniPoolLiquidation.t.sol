// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolDepositBorrow.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import "contracts/protocol/lendingpool/minipool/MiniPoolCollateralManager.sol";
import "forge-std/StdUtils.sol";

contract MiniPoolLiquidationTest is MiniPoolDepositBorrowTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    struct LiquidationVars {
        uint256 healthFactor;
        DataTypes.MiniPoolReserveData collateralReserveDataBefore;
        DataTypes.MiniPoolReserveData borrowReserveDataBefore;
        DataTypes.MiniPoolReserveData collateralReserveDataAfter;
        DataTypes.MiniPoolReserveData borrowReserveDataAfter;
        uint256 expectedCollateralLiquidated;
        uint256 currentVariableDebt;
        uint256 liquidatorDebtTokenBalance;
        uint256 userCollateralBalance;
        uint256 liquidatorCollaterallBalance;
        uint256 liquidationBonus;
        uint256 amountToLiquidate;
        uint256 scaledVariableDebt;
    }

    function testMiniPoolLiquidation(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 priceDecrease
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in LendingPool and MiniPool must be configured
         * 2. Lending Pool must be properly funded
         * 3. Flow limiter must be set to proper value for miniPool
         * Test Scenario:
         * 1. Users add tokens as collateral into the miniPool
         * 2. Users borrow tokens that are not available in miniPool
         * 3. Some time elapse - collateral token drops in value or borrowed token increases in value
         * 4. Protocol executes liquidation
         * Invariants:
         * 1. Liquidator shall end up with more collateral tokens
         * 2. User's debtToken balance shall decrease
         * 3. Health factor shall be greater than 1
         *
         */

        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
        vm.assume(collateralOffset != borrowOffset);
        console.log("[collateral]Offset: ", collateralOffset);
        console.log("[borrow]Offset: ", borrowOffset);

        /* Test vars */
        address user = makeAddr("user");
        TokenParams memory collateralParams = TokenParams(
            erc20Tokens[collateralOffset],
            aTokensWrapper[collateralOffset],
            oracle.getAssetPrice(address(erc20Tokens[collateralOffset]))
        );
        TokenParams memory borrowParams = TokenParams(
            erc20Tokens[borrowOffset],
            aTokensWrapper[borrowOffset],
            oracle.getAssetPrice(address(erc20Tokens[borrowOffset]))
        );
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        /* Assumptions */
        amount = bound(
            amount,
            10 ** (borrowParams.token.decimals() - 2),
            borrowParams.token.balanceOf(address(this)) / 10
        );

        LiquidationVars memory liquidationVars;
        (,,,,, liquidationVars.healthFactor) = IMiniPool(miniPool).getUserAccountData(user);
        console.log("1. Health factor: ", liquidationVars.healthFactor);

        fixture_miniPoolBorrow(
            amount, collateralOffset, borrowOffset, collateralParams, borrowParams, user
        );

        (,,,,, liquidationVars.healthFactor) = IMiniPool(miniPool).getUserAccountData(user);
        console.log("2. Health factor: ", liquidationVars.healthFactor);

        priceDecrease = bound(priceDecrease, 2_000, 5_000); /* price descrease by 20 - 50% */
        fixture_changePriceOfToken(collateralParams, priceDecrease, false);

        (,,,,, liquidationVars.healthFactor) = IMiniPool(miniPool).getUserAccountData(user);
        console.log("3. Health factor: ", liquidationVars.healthFactor);

        {
            address miniPoolCollateralManager = address(new MiniPoolCollateralManager());
            vm.prank(miniPoolContracts.miniPoolAddressesProvider.owner());
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolCollateralManager(
                miniPoolCollateralManager
            );
        }

        liquidationVars.collateralReserveDataBefore =
            IMiniPool(miniPool).getReserveData(address(collateralParams.token));
        liquidationVars.borrowReserveDataBefore =
            IMiniPool(miniPool).getReserveData(address(borrowParams.token));

        console.log("liquidityIndex: ", liquidationVars.borrowReserveDataBefore.liquidityIndex);
        console.log(
            "variableBorrowIndex: ", liquidationVars.borrowReserveDataBefore.variableBorrowIndex
        );
        console.log(
            "currentLiquidityRate: ", liquidationVars.borrowReserveDataBefore.currentLiquidityRate
        );
        console.log(
            "currentVariableBorrowRate: ",
            liquidationVars.borrowReserveDataBefore.currentVariableBorrowRate
        );

        console.log("liquidityIndex: ", liquidationVars.collateralReserveDataBefore.liquidityIndex);
        console.log(
            "variableBorrowIndex: ", liquidationVars.collateralReserveDataBefore.variableBorrowIndex
        );
        console.log(
            "currentLiquidityRate: ",
            liquidationVars.collateralReserveDataBefore.currentLiquidityRate
        );
        console.log(
            "currentVariableBorrowRate: ",
            liquidationVars.collateralReserveDataBefore.currentVariableBorrowRate
        );

        /**
         * LIQUIDATION PROCESS - START ***********
         */
        liquidationVars.amountToLiquidate;
        liquidationVars.scaledVariableDebt;

        {
            (uint256 debtToCover, uint256 _scaledVariableDebt) =
                aErc6909Token.getScaledUserBalanceAndSupply(user, 2128 + borrowOffset);
            liquidationVars.amountToLiquidate = debtToCover / 2; // maximum possible liquidation amount
            console.log("1.[OUT] debtToCover: ", debtToCover);
            (debtToCover, _scaledVariableDebt) =
                aErc6909Token.getScaledUserBalanceAndSupply(user, 2000 + borrowOffset);
            liquidationVars.amountToLiquidate = debtToCover / 2; // maximum possible liquidation amount
            console.log("2.[OUT] debtToCover: ", debtToCover);
            liquidationVars.scaledVariableDebt = _scaledVariableDebt;
        }
        {
            /* prepare funds */
            address liquidator = makeAddr("liquidator");

            borrowParams.token.transfer(liquidator, liquidationVars.amountToLiquidate);

            // uint256 userVariableDebt;
            // (,address debtToken) = deployedContracts.protocolDataProvider.getReserveTokensAddresses(address(token1Params.token), true);
            // console.log("MP userVariableDebt for user %s: %s", user, userVariableDebt);
            // console.log("LP userVariableDebt for user %s: %s", user, userVariableDebt);
            liquidationVars.currentVariableDebt = aErc6909Token.balanceOf(user, 2128 + borrowOffset);
            liquidationVars.liquidatorDebtTokenBalance = borrowParams.token.balanceOf(liquidator);
            liquidationVars.userCollateralBalance =
                aErc6909Token.balanceOf(user, 1128 + collateralOffset);
            liquidationVars.liquidatorCollaterallBalance =
                collateralParams.token.balanceOf(liquidator);
            console.log("Mini pool aToken: ", address(aErc6909Token));
            console.log("Borrow ID: ", 2128 + borrowOffset);
            console.log(
                "1. miniPool user debt token balance before: %s",
                liquidationVars.currentVariableDebt
            );
            console.log(
                "1. miniPool user collateral balance before: %s",
                liquidationVars.userCollateralBalance
            );
            // console.log("?? lendingPool user balance before: %s", borrowParams.aToken.balanceOf(user));
            console.log(
                "2. liquidator debt token balance before: %s",
                liquidationVars.liquidatorDebtTokenBalance
            );
            console.log(
                "2. liquidator collateral balance before: %s",
                liquidationVars.liquidatorCollaterallBalance
            );

            vm.startPrank(liquidator);
            borrowParams.token.approve(miniPool, liquidationVars.amountToLiquidate);
            IMiniPool(miniPool).liquidationCall(
                address(collateralParams.token),
                address(borrowParams.token),
                user,
                liquidationVars.amountToLiquidate,
                false
            );
            console.log(
                "--- aToken %s and token %s",
                address(borrowParams.aToken),
                address(borrowParams.token)
            );
            console.log("--- aToken %s", address(aErc6909Token));
            console.log(
                "1. miniPool user balance after: %s",
                aErc6909Token.balanceOf(user, 2128 + borrowOffset)
            );
            console.log(
                "2. miniPool user balance after: %s",
                aErc6909Token.balanceOf(user, 1128 + collateralOffset)
            );

            console.log(
                "3. lendingPool liquidator balance after: %s",
                collateralParams.token.balanceOf(liquidator)
            );
            console.log(
                "4. lendingPool liquidator balance after: %s",
                borrowParams.token.balanceOf(liquidator)
            );

            console.log(
                "User collateral token balance after liquidation shall be less or equal than user collateral balance before"
            );
            assertLe(
                aErc6909Token.balanceOf(user, 1128 + collateralOffset),
                liquidationVars.userCollateralBalance / 2,
                "444"
            );

            console.log(
                "User debt token balance after liquidation shall be less by {amountToLiquidate} than user debt balance before"
            );
            assertEq(
                liquidationVars.currentVariableDebt,
                aErc6909Token.balanceOf(user, 2128 + borrowOffset)
                    + liquidationVars.amountToLiquidate
            );

            console.log(
                "Liquidator collateral token balance after liquidation shall be greater or equal than half of user collateral balance + liquidator collateral balance before"
            );
            assertGe(
                collateralParams.token.balanceOf(liquidator),
                liquidationVars.liquidatorCollaterallBalance
                    + liquidationVars.userCollateralBalance / 2
            );

            console.log(
                "Liquidator debt token balance after liquidation shall be less by {amountToLiquidate} than user debt balance before"
            );
            assertEq(
                liquidationVars.liquidatorDebtTokenBalance,
                aErc6909Token.balanceOf(liquidator, 2128 + borrowOffset)
                    + liquidationVars.amountToLiquidate
            );

            (,,,,, uint256 healthFactorAfterLiquidation) =
                IMiniPool(miniPool).getUserAccountData(user);
            console.log(
                "4. Health factor %s vs healthFactorAfterLiquidation %s: ",
                liquidationVars.healthFactor,
                healthFactorAfterLiquidation
            );
            //assertGt(healthFactorAfterLiquidation, liquidationVars.healthFactor); // @issue9 Health factor after liquidation shall be greater than 1
            vm.stopPrank();
        }

        {
            liquidationVars.collateralReserveDataAfter =
                IMiniPool(miniPool).getReserveData(address(collateralParams.token));
            liquidationVars.borrowReserveDataAfter =
                IMiniPool(miniPool).getReserveData(address(borrowParams.token));
            DataTypes.ReserveConfigurationMap memory configuration =
                IMiniPool(miniPool).getConfiguration(address(collateralParams.token));
            (,, liquidationVars.liquidationBonus,,) = configuration.getParamsMemory();
            liquidationVars.expectedCollateralLiquidated = borrowParams.price
                * (liquidationVars.amountToLiquidate * liquidationVars.liquidationBonus / 10_000)
                * 10 ** collateralParams.token.decimals()
                / (collateralParams.price * 10 ** borrowParams.token.decimals());
        }
        uint256 variableDebtBeforeTx = fixture_calcExpectedVariableDebtTokenBalance(
            liquidationVars.borrowReserveDataBefore.currentVariableBorrowRate,
            liquidationVars.borrowReserveDataBefore.variableBorrowIndex,
            liquidationVars.borrowReserveDataBefore.lastUpdateTimestamp,
            liquidationVars.scaledVariableDebt,
            block.timestamp
        );
        liquidationVars.currentVariableDebt = aErc6909Token.balanceOf(user, 2128 + borrowOffset);

        console.log(
            "Debt before liquidation shall be greater by {amountToLiquidate=%s} than debt after liquidation",
            liquidationVars.amountToLiquidate
        );
        assertApproxEqRel(
            liquidationVars.currentVariableDebt,
            variableDebtBeforeTx - liquidationVars.amountToLiquidate,
            0.01e18
        );
        console.log(
            "Liquidity index for debt token after liquidation shall be greater than liquidity index before liquidation"
        );
        assertGe(
            liquidationVars.borrowReserveDataAfter.liquidityIndex,
            liquidationVars.borrowReserveDataBefore.liquidityIndex
        );
        console.log(
            "Liquidity rate after liquidation shall be less than liquidity rate before liquidation"
        );
        assertLt(
            liquidationVars.borrowReserveDataAfter.currentLiquidityRate,
            liquidationVars.borrowReserveDataBefore.currentLiquidityRate
        );
    }

    function testLendingPoolLiquidatesMiniPool() public {
        /**
         * Preconditions:
         * 1. Reserves in LendingPool and MiniPool must be configured
         * 2. Lending Pool must be properly funded
         * 3. Flow limiter must be set to proper value for miniPool
         * Test Scenario:
         * 1. User1 add tokens as collateral into the lendingPool
         * 2. User2 add tokens as collateral into the miniPool
         * 3. User2 borrow token that is not available in miniPool
         * 4. Other users borrow the same asset that miniPool borrows from lendingPool creating high borrow rate
         * 4. Some time elapse - aTokens and debtTokens appreciate in specific rate
         * Invariants:
         * 1. Health of miniPool position shall not go under 1 allowing lendingPool to liquidate position
         *
         */
    }

    //@issue5 - Failing but this is interest rate augmented functionality which will be rewroked
    function testLiquidationsWithFlowFromLendingPool(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 skipDuration,
        uint256 priceDecrease
    ) public {
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        skipDuration = bound(skipDuration, 0, 300 days);
        vm.assume(borrowOffset != collateralOffset && borrowOffset < tokens.length - 1);
        console.log("Offsets: token0: %s token1: %s", collateralOffset, borrowOffset);

        TokenParams memory collateralParams = TokenParams(
            erc20Tokens[collateralOffset],
            aTokensWrapper[collateralOffset],
            oracle.getAssetPrice(address(erc20Tokens[collateralOffset]))
        );
        TokenParams memory borrowParams = TokenParams(
            erc20Tokens[borrowOffset],
            aTokensWrapper[borrowOffset],
            oracle.getAssetPrice(address(erc20Tokens[borrowOffset]))
        );
        address user = makeAddr("user");
        amount = bound(
            amount,
            10 ** borrowParams.token.decimals() / 100,
            borrowParams.token.balanceOf(address(this)) / 10
        );

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");
        vm.label(address(borrowParams.aToken), "token1");
        vm.label(address(collateralParams.token), "token0");

        fixture_miniPoolBorrowWithFlowFromLendingPool(
            amount, borrowOffset, collateralParams, borrowParams, user
        );

        (,,,,, uint256 healthFactor) = IMiniPool(miniPool).getUserAccountData(user);
        console.log("1. MiniPool User healthFactor: %e", healthFactor);

        priceDecrease = bound(priceDecrease, 2_000, 5_000); /* price descrease by 20 - 50% */

        fixture_changePriceOfToken(collateralParams, priceDecrease, false);

        (,,,,, healthFactor) = IMiniPool(miniPool).getUserAccountData(user);
        console.log("2. MiniPool User healthFactor for user %s: %e", user, healthFactor);

        address miniPoolCollateralManager = address(new MiniPoolCollateralManager());
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.owner());
        miniPoolContracts.miniPoolAddressesProvider.setMiniPoolCollateralManager(
            miniPoolCollateralManager
        );

        /**
         * LIQUIDATION PROCESS - START ***********
         */
        uint256 amountToLiquidate;
        uint256 scaledVariableDebt;

        {
            (uint256 debtToCover, uint256 _scaledVariableDebt) =
                aErc6909Token.getScaledUserBalanceAndSupply(user, 2000 + borrowOffset);
            amountToLiquidate = debtToCover / 2; // maximum possible liquidation amount
            console.log("[OUTwith] debtToCover: ", debtToCover);
            scaledVariableDebt = _scaledVariableDebt;
        }
        {
            /* prepare funds */
            address liquidator = makeAddr("liquidator");
            borrowParams.token.transfer(liquidator, amountToLiquidate);

            // uint256 userVariableDebt;
            // (,address debtToken) = deployedContracts.protocolDataProvider.getReserveTokensAddresses(address(token1Params.token), true);
            // console.log("MP userVariableDebt for user %s: %s", user, userVariableDebt);
            // console.log("LP userVariableDebt for user %s: %s", user, userVariableDebt);

            vm.startPrank(liquidator);
            borrowParams.token.approve(miniPool, amountToLiquidate);
            console.log("address(collateralParams.token) : ", address(collateralParams.token));
            IMiniPool(miniPool).liquidationCall(
                address(collateralParams.token),
                address(borrowParams.token),
                user,
                amountToLiquidate,
                false
            );
            vm.stopPrank();
        }
        /**
         * LIQUIDATION PROCESS - END ***********
         */
    }
}
