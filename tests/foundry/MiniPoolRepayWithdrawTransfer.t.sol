// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolDepositBorrow.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

import "forge-std/StdUtils.sol";

contract MiniPoolRepayWithdrawTransferTest is MiniPoolDepositBorrowTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    struct ReserveTokenParams {
        uint256 liquidationThreshold;
        uint256 collateralBalanceInUsd;
        uint256 borrowBalanceInUsd;
        uint256 currentHealth;
    }

    event Withdraw(
        address indexed reserve, address indexed user, address indexed to, uint256 amount
    );
    event Repay(
        address indexed reserve, address indexed user, address indexed repayer, uint256 amount
    );

    function fixture_calculateHealthFactorFromBalances(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 liquidationThreshold
    ) internal pure returns (uint256) {
        if (totalDebtInETH == 0) return type(uint256).max;

        return (totalCollateralInETH.percentMul(liquidationThreshold)).wadDiv(totalDebtInETH);
    }

    function testWithdrawalsZeroDebt(uint256 amount, uint256 offset) public {
        offset = bound(offset, 0, tokens.length - 1);
        console.log("[Withdrawal]Offset: ", offset);

        TokenParams memory tokenParams = TokenParams(erc20Tokens[offset], aTokensWrapper[offset], 0);

        address user = makeAddr("user");
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");

        vm.assume(amount <= tokenParams.token.balanceOf(address(this)) / 2);
        vm.assume(amount > 10 ** tokenParams.token.decimals() / 100);
        fixture_MiniPoolDeposit(amount, offset, user, tokenParams);

        console.log("Balance of 6909 grain tokens: ", aErc6909Token.balanceOf(user, 1000));
        console.log("Balance of 6909 tokens: ", aErc6909Token.balanceOf(user, 1128));

        uint256 usdcAmount = amount;
        console.log(usdcAmount);
        uint256 grainUsdcAmount = amount;
        console.log(grainUsdcAmount);

        vm.startPrank(user);
        IMiniPool(miniPool).withdraw(address(tokenParams.token), usdcAmount, user);
        assertEq(tokenParams.token.balanceOf(user), usdcAmount);
        IMiniPool(miniPool).withdraw(address(tokenParams.aToken), grainUsdcAmount, user);
        assertEq(tokenParams.aToken.balanceOf(user), grainUsdcAmount);
        vm.stopPrank();
    }

    function testTransferCollateral(uint256 amount, uint256 offset) public {
        offset = bound(offset, 0, tokens.length - 1);
        uint256 tokenId = 1128 + offset;
        uint256 aTokenId = 1000 + offset;

        address user = makeAddr("user");
        address user2 = makeAddr("user2");
        TokenParams memory tokenParams = TokenParams(erc20Tokens[offset], aTokensWrapper[offset], 0);
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");

        vm.assume(amount <= tokenParams.token.balanceOf(address(this)) / 2);
        vm.assume(amount > 10 ** tokenParams.token.decimals() / 10);

        fixture_MiniPoolDeposit(amount, offset, user, tokenParams);
        {
            uint256 grainTotalSupplyBefore = aErc6909Token.scaledTotalSupply(aTokenId);
            uint256 graingrainTotalSupplyBefore = aErc6909Token.scaledTotalSupply(tokenId);

            uint256 userBalance = aErc6909Token.balanceOf(user, tokenId);
            uint256 user2Balance = aErc6909Token.balanceOf(user2, tokenId);
            vm.startPrank(user);
            aErc6909Token.transfer(user2, tokenId, amount);
            assertEq(userBalance, user2Balance + amount);

            userBalance = aErc6909Token.balanceOf(user, aTokenId);
            user2Balance = aErc6909Token.balanceOf(user2, aTokenId);
            aErc6909Token.transfer(user2, aTokenId, amount);
            assertEq(userBalance, user2Balance + amount);
            vm.stopPrank();

            assertEq(grainTotalSupplyBefore, aErc6909Token.scaledTotalSupply(aTokenId));
            assertEq(graingrainTotalSupplyBefore, aErc6909Token.scaledTotalSupply(tokenId));
        }

        address user3 = makeAddr("user3");
        vm.startPrank(user2);
        aErc6909Token.approve(user3, tokenId, amount);
        vm.stopPrank();
        vm.startPrank(user3);
        aErc6909Token.transferFrom(user2, user3, tokenId, amount);
        vm.stopPrank();
    }

    function testMiniPoolNormalBorrowRepay(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * Test Scenario:
         * 1. User adds token as collateral into the miniPool
         * 2. User borrows tokens
         * 3. User repays tokens
         * Invariants:
         * 1. Balance of debtToken for user in IERC6909 standard shall decrease
         * 2. Total supply of debtToken shall decrease
         * 3. Health of user's position shall increase
         * 4. User's borrowed assets balance shall decrease
         *
         */

        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);

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
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        amount = bound(
            amount,
            10 ** borrowParams.token.decimals() / 100,
            borrowParams.token.balanceOf(address(this)) / 10
        );

        /* Borrow */
        fixture_miniPoolBorrow(
            amount, collateralOffset, borrowOffset, collateralParams, borrowParams, user
        );

        /* Repay */
        vm.startPrank(user);
        Balances memory balances;
        (,,,,, uint256 healthFactorBefore) = IMiniPool(miniPool).getUserAccountData(user);
        /* AToken repayment */
        balances.totalSupply = aErc6909Token.scaledTotalSupply(2000 + borrowOffset);
        balances.debtToken = aErc6909Token.balanceOf(user, 2000 + borrowOffset);
        balances.token = borrowParams.aToken.balanceOf(user);
        borrowParams.aToken.approve(address(miniPool), amount);
        IMiniPool(miniPool).repay(address(borrowParams.aToken), amount, user);

        console.log("Balance of total supply must be lower than before borrow");
        assertEq(
            aErc6909Token.scaledTotalSupply(2000 + borrowOffset), balances.totalSupply - amount
        );
        console.log("Balance of AToken debt must be lower than before borrow");
        assertEq(aErc6909Token.balanceOf(user, 2000 + borrowOffset), balances.debtToken - amount);
        console.log("Balance of AToken must be lower than before borrow");
        assertEq(borrowParams.aToken.balanceOf(user), balances.token - amount);

        /* Token repayment */
        balances.totalSupply = aErc6909Token.scaledTotalSupply(2128 + borrowOffset);
        balances.debtToken = aErc6909Token.balanceOf(user, 2128 + borrowOffset);
        balances.token = borrowParams.token.balanceOf(user);
        borrowParams.token.approve(address(miniPool), amount);
        IMiniPool(miniPool).repay(address(borrowParams.token), amount, user);
        console.log("total supply: ", balances.totalSupply);
        console.log("debt token: ", balances.debtToken);
        console.log("token: ", balances.token);
        console.log("amount: ", amount);

        console.log("Balance of total supply must be lower than before borrow");
        assertEq(aErc6909Token.scaledTotalSupply(2128 + borrowOffset), balances.debtToken - amount);
        console.log("Balance of token debt must be lower than before borrow");
        assertEq(aErc6909Token.balanceOf(user, 2128 + borrowOffset), balances.totalSupply - amount);
        console.log("Balance of token must be lower than before borrow");
        assertEq(borrowParams.token.balanceOf(user), balances.token - amount);

        (,,,,, uint256 healthFactorAfter) = IMiniPool(miniPool).getUserAccountData(user);
        assertLt(
            healthFactorBefore, healthFactorAfter, "Health before is greater than health after"
        );
        vm.stopPrank();
    }

    function testMiniPoolBorrowRepayWithFlowFromLendingPool(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 skipDuration
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

        // skip(skipDuration); TODO

        Balances memory balances;
        (,,,,, uint256 healthFactorBefore) = IMiniPool(miniPool).getUserAccountData(user);
        balances.totalSupply = aErc6909Token.scaledTotalSupply(2000 + borrowOffset);
        balances.debtToken = aErc6909Token.balanceOf(user, 2000 + borrowOffset);
        balances.token = borrowParams.aToken.balanceOf(user);
        console.log("total supply: ", balances.totalSupply);
        console.log("debt token: ", balances.debtToken);
        console.log("token: ", balances.token);
        console.log("amount: ", amount);

        console.log("Repaying...");
        vm.startPrank(user);
        borrowParams.aToken.approve(address(miniPool), amount);
        IMiniPool(miniPool).repay(address(borrowParams.aToken), amount, user);

        console.log("Balance of total supply must be lower than before borrow");
        assertEq(
            aErc6909Token.scaledTotalSupply(2000 + borrowOffset), balances.totalSupply - amount
        );
        console.log("Balance of AToken debt must be lower than before borrow");
        assertEq(aErc6909Token.balanceOf(user, 2000 + borrowOffset), balances.debtToken - amount);
        console.log("Balance of AToken must be lower than before borrow");
        assertEq(borrowParams.aToken.balanceOf(user), balances.token - amount);
        console.log("Repaid");
        (,,,,, uint256 healthFactorAfter) = IMiniPool(miniPool).getUserAccountData(user);
        assertLt(
            healthFactorBefore, healthFactorAfter, "health before is greater than health after"
        );
        vm.stopPrank();
    }

    function testCannotWithdrawWhenBorrowedMaxLtv(
        uint256 borrowAmount,
        uint256 withdrawAmount,
        uint256 collateralOffset,
        uint256 borrowOffset
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * 2. Mini Pool must be properly funded
         * 3. Flow limiter must be set to proper value for miniPool
         * 4. User's ltv must be close to max allowed value
         * Test Scenario:
         * 1. User adds tokens as collateral into the miniPool
         * 2. User borrows tokens from miniPool
         * 3. User tries to withdraw
         * Invariants:
         * 1. Withdraw shall not be possible when user's position health goes below 1
         */
        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
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
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        borrowAmount = bound(
            borrowAmount,
            10 ** borrowParams.token.decimals() / 100,
            borrowParams.token.balanceOf(address(this)) / 10
        );
        vm.assume(withdrawAmount < borrowAmount);

        /* Borrow */
        fixture_miniPoolBorrow(
            borrowAmount, collateralOffset, borrowOffset, collateralParams, borrowParams, user
        );

        // TODO
        // ReserveTokenParams memory reserveTokenParams;

        // {
        //     DataTypes.MiniPoolReserveData storage collateralReserve = IMiniPool(miniPool).getReserveData(address(collateralParams.token), true);

        //     (, reserveTokenParams.liquidationThreshold,,,) = collateralReserve.configuration.getParams();
        // }

        // reserveTokenParams.collateralBalanceInUsd = collateralParams.token.balanceOf(address(collateralParams.aToken)) * collateralParams.price / collateralParams.token.decimals();
        // reserveTokenParams.borrowBalanceInUsd = aErc6909Token.balanceOf(user, 2128 + borrowOffset) * borrowParams.price / borrowParams.token.decimals();

        // console.log("collateralBalanceInUsd: ", reserveTokenParams.collateralBalanceInUsd);
        // console.log("borrowBalanceInUsd: ", reserveTokenParams.borrowBalanceInUsd);

        // reserveTokenParams.currentHealth = fixture_calculateHealthFactorFromBalances(
        //     collateralParams.token.balanceOf(address(collateralParams.aToken)),
        //     aErc6909Token.balanceOf(user, 2128 + borrowOffset),
        //     reserveTokenParams.liquidationThreshold * reserveTokenParams.collateralBalanceInUsd);

        vm.startPrank(user);
        console.log("Withdraw function for token shall revert");
        uint256 balanceOfCollateral = aErc6909Token.balanceOf(user, 1128 + collateralOffset);
        // vm.expectRevert();
        vm.expectRevert(bytes(Errors.VL_TRANSFER_NOT_ALLOWED));
        IMiniPool(miniPool).withdraw(address(collateralParams.token), balanceOfCollateral, user);
        // console.log("Withdraw function for AToken shall revert");
        // vm.expectRevert(bytes(Errors.VL_TRANSFER_NOT_ALLOWED));
        // IMiniPool(miniPool).withdraw(address(collateralParams.aToken), true, aErc6909Token.balanceOf(user, 1000 + collateralOffset), user);
        vm.stopPrank();
    }

    function testWithdrawWhenBorrowed(
        uint256 borrowAmount,
        uint256 withdrawAmount,
        uint256 collateralOffset,
        uint256 borrowOffset
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * 2. Mini Pool must be properly funded
         * 3. User's ltv must be close to max allowed value
         * Test Scenario:
         * 1. User adds tokens as collateral into the miniPool
         * 2. User borrows tokens from miniPool
         * 3. User withdraws amount that not exceed ltv
         * Invariants:
         * 1. Withdraw shall be possible when user's position health is above 1
         * 2. Health ratio shall decrease
         * 3. User shall have less collateral
         * 4. User shall have increased underlying balance
         */
        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
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
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        borrowAmount = bound(
            borrowAmount,
            10 ** borrowParams.token.decimals() / 100,
            borrowParams.token.balanceOf(address(this)) / 10
        );
        vm.assume(withdrawAmount < borrowAmount);

        /* Borrow */
        fixture_miniPoolBorrow(
            borrowAmount, collateralOffset, borrowOffset, collateralParams, borrowParams, user
        );

        /* Deposit - to have better health and be able to withdraw */
        withdrawAmount = bound(
            withdrawAmount,
            10 ** collateralParams.token.decimals() / 100,
            collateralParams.token.balanceOf(address(this)) / 10
        );
        fixture_MiniPoolDeposit(withdrawAmount, collateralOffset, user, collateralParams);
        (,,,,, uint256 healthFactorBefore) = IMiniPool(miniPool).getUserAccountData(user);
        uint256 collateralBalanceBefore = aErc6909Token.balanceOf(user, 1128 + collateralOffset);
        uint256 underlyingBalanceBefore = collateralParams.token.balanceOf(user);

        vm.startPrank(user);
        address oracle = miniPoolContracts.miniPoolAddressesProvider.getPriceOracle();
        console.log(
            "Price of token: ",
            IPriceOracleGetter(oracle).getAssetPrice(address(collateralParams.token))
        );
        console.log("Withdraw token");
        IMiniPool(miniPool).withdraw(address(collateralParams.token), withdrawAmount / 2, user);
        // console.log("Withdraw AToken");
        // IMiniPool(miniPool).withdraw(address(collateralParams.aToken), true, withdrawAmount/2, user);

        {
            (,,,,, uint256 healthFactorAfter) = IMiniPool(miniPool).getUserAccountData(user);
            console.log("healthFactor", healthFactorAfter);
            assertGt(healthFactorAfter, 10_000);
            assertGt(healthFactorBefore, healthFactorAfter);
        }
        {
            assertGt(
                collateralBalanceBefore, aErc6909Token.balanceOf(user, 1128 + collateralOffset)
            );
            assertEq(
                underlyingBalanceBefore + withdrawAmount / 2, collateralParams.token.balanceOf(user)
            );
        }

        vm.stopPrank();
    }

    // @issue11 Users are not able to withdraw all funds that they deposited after repaying
    function testMultipleUsersBorrowRepayAndWithdraw(
        uint256 amount1,
        uint256 amount2,
        uint256 skipDuration
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in LendingPool and MiniPool must be configured
         * 2. Mini Pool must be properly funded
         * 3. There is some liquidity deposited by provider to borrow certain asset from lending pool (WBTC)
         * Test Scenario:
         * 1. User adds token (USDC) as a collateral into the mini pool
         * 3. User borrows token (WBTC) in miniPool
         * 4. Provider borrows some USDC - User starts getting interest rates
         * 5. Some time elapse - aTokens and debtTokens appreciate in value
         * 6. User repays all debts (WBTC) - distribute some WBTC to pay accrued interests
         * 7. Provider repays all debts (USDC) - distribute some USDC to pay accrued interests
         * 8. User withdraws all the funds with accrued interests
         * 9. Provider withdraws all the funds with accrued interests
         * Invariants:
         * 1. All users shall be able to withdraw the greater or equal amount of funds that they deposited
         * 2.
         *
         */
        uint8 WBTC_OFFSET = 1;
        uint8 USDC_OFFSET = 0;

        /* Fuzz vectors */
        skipDuration = bound(skipDuration, 100, 300 days);

        TokenParams memory usdcParams = TokenParams(
            erc20Tokens[USDC_OFFSET],
            aTokensWrapper[USDC_OFFSET],
            oracle.getAssetPrice(address(erc20Tokens[USDC_OFFSET]))
        );
        TokenParams memory wbtcParams = TokenParams(
            erc20Tokens[WBTC_OFFSET],
            aTokensWrapper[WBTC_OFFSET],
            oracle.getAssetPrice(address(erc20Tokens[WBTC_OFFSET]))
        );
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        Users memory users;
        users.user1 = makeAddr("user1");
        users.user2 = makeAddr("user2");
        users.user3 = makeAddr("distributor");

        amount1 = 4000 * 10 ** usdcParams.token.decimals(); // 4 000 usdc
        amount2 = 2 * 10 ** (wbtcParams.token.decimals() - 1); // 0.2 wbtc

        console.log("----------------USER1 DEPOSIT---------------");
        fixture_depositTokensToMiniPool(
            amount1, 1128 + USDC_OFFSET, users.user1, usdcParams, aErc6909Token
        );
        console.log("----------------USER2 DEPOSIT---------------");
        fixture_depositTokensToMiniPool(
            amount2, 1128 + WBTC_OFFSET, users.user2, wbtcParams, aErc6909Token
        );

        console.log("----------------USER1 BORROW---------------");
        vm.startPrank(users.user1);
        IMiniPool(miniPool).borrow(address(wbtcParams.token), amount2 / 4, users.user1);
        assertEq(wbtcParams.token.balanceOf(users.user1), amount2 / 4);
        vm.stopPrank();

        console.log("----------------USER2 BORROW---------------");
        vm.startPrank(users.user2);
        IMiniPool(miniPool).borrow(address(usdcParams.token), amount1 / 4, users.user2);
        assertEq(usdcParams.token.balanceOf(users.user2), amount1 / 4);
        vm.stopPrank();

        skip(skipDuration);

        uint256 diff = aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET) - amount2 / 4;
        console.log("Accrued wbtc debt: ", diff);
        deal(address(wbtcParams.token), users.user1, wbtcParams.token.balanceOf(users.user1) + diff);
        diff = aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET) - amount1 / 4;
        console.log("Accrued usdc debt: ", diff);
        deal(address(usdcParams.token), users.user2, usdcParams.token.balanceOf(users.user2) + diff);

        vm.startPrank(users.user1);
        console.log("----------------USER1 REPAYS---------------");
        console.log(
            "Amount %s vs debt balance %s",
            amount1,
            aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET)
        );
        wbtcParams.token.approve(
            address(miniPool), aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET)
        );
        console.log("User1 Repaying...");
        /* Give lacking amount to user 1 */
        IMiniPool(miniPool).repay(
            address(wbtcParams.token),
            aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET),
            users.user1
        );
        vm.stopPrank();

        console.log("----------------USER2 REPAYS---------------");
        vm.startPrank(users.user2);
        console.log(
            "Amount %s vs debt balance %s",
            amount1,
            aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET)
        );
        usdcParams.token.approve(
            address(miniPool), aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET)
        );
        console.log("User2 Repaying...");
        IMiniPool(miniPool).repay(
            address(usdcParams.token),
            aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET),
            users.user2
        );
        vm.stopPrank();

        vm.startPrank(users.user1);
        console.log("Balance: ", aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET));
        uint256 availableLiquidity =
            IERC20(aTokensWrapper[USDC_OFFSET]).balanceOf(address(aErc6909Token));
        console.log("AvailableLiquidity: ", availableLiquidity);
        console.log("Withdrawing... %s", aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET));
        IMiniPool(miniPool).withdraw(
            address(usdcParams.token),
            aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET),
            users.user1
        );
        console.log("After Balance: ", aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET));
        availableLiquidity = IERC20(aTokensWrapper[USDC_OFFSET]).balanceOf(address(aErc6909Token));
        console.log("After availableLiquidity: ", availableLiquidity);
        vm.stopPrank();

        vm.startPrank(users.user2);
        console.log("----------------USER2 TRANSFER---------------");

        availableLiquidity = IERC20(aTokensWrapper[WBTC_OFFSET]).balanceOf(address(aErc6909Token));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user2, 1000 + WBTC_OFFSET));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user2, 1128 + WBTC_OFFSET));
        console.log("AvailableLiquidity: ", availableLiquidity);
        console.log("Withdrawing...");
        IMiniPool(miniPool).withdraw(
            address(wbtcParams.token),
            aErc6909Token.balanceOf(users.user2, 1128 + WBTC_OFFSET),
            users.user2
        );
        vm.stopPrank();

        assertGt(
            usdcParams.token.balanceOf(users.user1), amount1, "Balance is not greater for user1"
        );
        assertGt(
            wbtcParams.token.balanceOf(users.user2), amount2, "Balance is not greater for user2"
        );
    }

    function testBorrowRepayAndWithdrawWithFlow(
        uint256 amount1,
        uint256 amount2,
        uint256 skipDuration
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in LendingPool and MiniPool must be configured
         * 2. Mini Pool must be properly funded
         * 3. There is some liquidity deposited by provider to borrow certain asset from lending pool (WBTC)
         * Test Scenario:
         * 1. User adds token (USDC) as collateral into the lending pool
         * 2. User adds aToken (aUSDC) as a collateral into the mini pool
         * 3. User borrows token (aWBTC) in miniPool - lending from mini pool happens
         * 4. Provider borrows some aUSDC - User starts getting interest rates
         * 5. Some time elapse - aTokens and debtTokens appreciate in value
         * 6. User repays all debts (aWBTC) - distribute some aWBTC to pay accrued interests
         * 7. Provider repays all debts (aUSDC) - distribute some aUSDC to pay accrued interests
         * 8. User withdraws all the funds with accrued interests
         * Invariants:
         * 1. User shall be able to withdraw all user's balance with accrued interests (always greater than deposit)
         *
         */
        /* Constants */
        uint8 WBTC_OFFSET = 1;
        uint8 USDC_OFFSET = 0;

        /* Fuzz vectors */
        skipDuration = 300 days; //bound(skipDuration, 0, 300 days);

        TokenParams memory usdcParams = TokenParams(
            erc20Tokens[USDC_OFFSET],
            aTokensWrapper[USDC_OFFSET],
            oracle.getAssetPrice(address(erc20Tokens[USDC_OFFSET]))
        );
        TokenParams memory wbtcParams = TokenParams(
            erc20Tokens[WBTC_OFFSET],
            aTokensWrapper[WBTC_OFFSET],
            oracle.getAssetPrice(address(erc20Tokens[WBTC_OFFSET]))
        );
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        Users memory users;
        users.user1 = makeAddr("user1");
        users.user2 = makeAddr("provider");
        users.user3 = makeAddr("distributor");

        amount1 = 2000 * 10 ** usdcParams.token.decimals(); // 2 000 usdc
        amount2 = 10 ** (wbtcParams.token.decimals() - 1); // 0.1 wbtc

        // Set flow limiter
        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider));
        miniPoolContracts.flowLimiter.setFlowLimit(address(wbtcParams.token), miniPool, amount2 * 2);

        console.log("----------------PROVIDER DEPOSITs LIQUIDITY (WBTC)---------------");
        fixture_depositTokensToMainPool(amount2, users.user2, wbtcParams);
        console.log(
            "----------------PROVIDER DEPOSITs LIQUIDITY (aWBTC) TO MINI POOL---------------"
        );
        /* User deposits lending pool's aTokens to the mini pool and 
        gets mini pool's aTokens */
        fixture_depositATokensToMiniPool(
            amount2, 1000 + WBTC_OFFSET, users.user2, wbtcParams, aErc6909Token
        );

        console.log("----------------USER DEPOSITs LIQUIDITY (USDC) TO LENDING POOL---------------");
        /* User deposits tokens to the main lending pool and gets lending pool's aTokens*/
        fixture_depositTokensToMainPool(amount1, users.user1, usdcParams);
        console.log("----------------USER DEPOSITs LIQUIDITY (aUSDC) TO MINI POOL---------------");
        /* User deposits lending pool's aTokens to the mini pool and 
        gets mini pool's aTokens */
        fixture_depositATokensToMiniPool(
            amount1, 1000 + USDC_OFFSET, users.user1, usdcParams, aErc6909Token
        );

        console.log("----------------USER1 BORROWs---------------");
        vm.startPrank(users.user1);
        IMiniPool(miniPool).borrow(address(wbtcParams.aToken), amount2 / 4, users.user1);
        vm.stopPrank();

        console.log("----------------PROVIDER BORROWs---------------");
        vm.prank(users.user2);
        IMiniPool(miniPool).borrow(address(usdcParams.aToken), amount1 / 10, users.user2);

        console.log("0. Balance aToken: ", aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET));
        console.log(
            "0. AvailableLiquidity: ",
            IERC20(aTokens[USDC_OFFSET]).balanceOf(address(aErc6909Token))
        );
        console.log("----------------TIME TRAVEL---------------");
        skip(skipDuration);

        vm.startPrank(users.user1);
        console.log("----------------USER REPAYS---------------");
        console.log(
            "Amount %s vs debt balance %s",
            amount1,
            aErc6909Token.balanceOf(users.user1, 2000 + WBTC_OFFSET)
        );
        {
            uint256 diff = aErc6909Token.balanceOf(users.user1, 2000 + WBTC_OFFSET) - amount2 / 4;
            console.log("Distributing borrowed asset to pay interests %s", diff);
            console.log("----------------USER3---------------");
            fixture_depositTokensToMainPool(amount2, users.user3, wbtcParams);
            vm.startPrank(users.user3);
            wbtcParams.aToken.transfer(users.user1, diff);
            vm.stopPrank();
        }
        vm.startPrank(users.user1);
        console.log(
            "To pay back: %s vs available balance: %s",
            aErc6909Token.balanceOf(users.user1, 2000 + WBTC_OFFSET),
            wbtcParams.aToken.balanceOf(users.user1)
        );
        wbtcParams.aToken.approve(
            address(miniPool), aErc6909Token.balanceOf(users.user1, 2000 + WBTC_OFFSET)
        );
        console.log("1. Balance aToken: ", aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET));
        console.log(
            "1. AvailableLiquidity: ",
            IERC20(aTokens[USDC_OFFSET]).balanceOf(address(aErc6909Token))
        );
        console.log("User1 Repaying...");
        IMiniPool(miniPool).repay(
            address(wbtcParams.aToken),
            aErc6909Token.balanceOf(users.user1, 2000 + WBTC_OFFSET),
            users.user1
        );
        vm.stopPrank();
        console.log("----------------PROVIDER REPAYS---------------");

        console.log(
            "Amount %s vs debt balance %s",
            amount1,
            aErc6909Token.balanceOf(users.user2, 2000 + USDC_OFFSET)
        );
        {
            uint256 diff = aErc6909Token.balanceOf(users.user2, 2000 + USDC_OFFSET) - amount1 / 10;
            console.log("Distributing borrowed asset to pay interests %s", diff);
            console.log("----------------USER3---------------");
            // vm.startPrank(users.user3);
            // {
            //     uint256 initialTokenBalance = usdcParams.token.balanceOf(users.user3);
            //     uint256 initialATokenBalance = usdcParams.aToken.balanceOf(users.user3);
            //     usdcParams.token.approve(address(deployedContracts.lendingPool), amount1);
            //     deployedContracts.lendingPool.deposit(
            //         address(usdcParams.token), true, amount1, users.user3
            //     );
            //     console.log("User token balance shall be {initialTokenBalance - amount}");
            //     assertEq(usdcParams.token.balanceOf(users.user3), initialTokenBalance - amount1);
            //     console.log("User grain token balance shall be {initialATokenBalance + amount}");
            //     assertEq(usdcParams.aToken.balanceOf(users.user3), initialATokenBalance + amount1);
            // }
            fixture_depositTokensToMainPool(amount1, users.user3, usdcParams);
            vm.startPrank(users.user3);
            usdcParams.aToken.transfer(users.user2, diff);
            vm.stopPrank();
        }
        vm.startPrank(users.user2);
        console.log(
            "To pay back: %s vs available balance: %s",
            aErc6909Token.balanceOf(users.user2, 2000 + USDC_OFFSET),
            usdcParams.aToken.balanceOf(users.user2)
        );
        usdcParams.aToken.approve(
            address(miniPool), aErc6909Token.balanceOf(users.user2, 2000 + USDC_OFFSET)
        );
        console.log(
            "2. Normalized income USDC: ",
            ILendingPool(deployedContracts.lendingPool).getReserveNormalizedIncome(
                address(usdcParams.token), true
            )
        );
        console.log(
            "2. Normalized income aUSDC: ",
            IMiniPool(miniPool).getReserveNormalizedIncome(address(usdcParams.aToken))
        );
        console.log(
            "2. Normalized income WBTC: ",
            ILendingPool(deployedContracts.lendingPool).getReserveNormalizedIncome(
                address(wbtcParams.token), true
            )
        );
        console.log(
            "2. Normalized income aWBTC: ",
            IMiniPool(miniPool).getReserveNormalizedIncome(address(wbtcParams.aToken))
        );
        uint256 availableLiquidity = IERC20(aTokens[USDC_OFFSET]).balanceOf(address(aErc6909Token));
        console.log("2. AvailableLiquidity: ", availableLiquidity);
        console.log("Provider repaying...");
        /* Give lacking amount to user */
        IMiniPool(miniPool).repay(
            address(usdcParams.aToken),
            aErc6909Token.balanceOf(users.user2, 2000 + USDC_OFFSET),
            users.user2
        );
        vm.stopPrank();

        console.log("Users2 debt: ", aErc6909Token.balanceOf(users.user2, 2000 + USDC_OFFSET));

        console.log("----------------USER WITHDRAW---------------");
        vm.startPrank(users.user1);
        uint256 balanceAToken = aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET);
        console.log("3. Balance aToken: ", balanceAToken);
        availableLiquidity = IERC20(aTokens[USDC_OFFSET]).balanceOf(address(aErc6909Token));
        // IERC20(reserve).balanceOf(aToken)
        console.log("3. AvailableLiquidity: ", availableLiquidity);
        console.log(
            "3. Normalized income USDC: ",
            ILendingPool(deployedContracts.lendingPool).getReserveNormalizedIncome(
                address(usdcParams.token), true
            )
        );
        console.log(
            "3. Normalized income aUSDC: ",
            IMiniPool(miniPool).getReserveNormalizedIncome(address(usdcParams.aToken))
        );
        console.log(
            "3. Normalized income WBTC: ",
            ILendingPool(deployedContracts.lendingPool).getReserveNormalizedIncome(
                address(wbtcParams.token), true
            )
        );
        console.log(
            "3. Normalized income aWBTC: ",
            IMiniPool(miniPool).getReserveNormalizedIncome(address(wbtcParams.aToken))
        );

        console.log("Withdrawing... %s", aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET));
        IMiniPool(miniPool).withdraw(
            address(usdcParams.aToken),
            aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET),
            users.user1
        );
        console.log("After Balance: ", aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET));
        availableLiquidity = IERC20(aTokensWrapper[USDC_OFFSET]).balanceOf(address(aErc6909Token));
        console.log("After availableLiquidity: ", availableLiquidity);
        assertEq(
            aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET),
            0,
            "User's token balance in a protocol is not 0 after withdrawal"
        );
        assertGe(
            usdcParams.aToken.balanceOf(users.user1),
            amount1,
            "User doesn't have greater amount than he deposited"
        );
        vm.stopPrank();
    }

    function testMiniPoolDepositAndWithdrawAfterSomeTime() public {
        /**
         * Preconditions:
         * 1. Reserves in LendingPool and MiniPool must be configured
         * 2. Lending Pool must be properly funded
         * Test Scenario:
         * 1. User adds token (USDC) as collateral into the lending pool
         * 2. User2 adds token (WBTC) as a collateral into the lending pool
         * 3. User2 borrows token (USDC) in lending pool
         * 4. User deposits aToken (aUSDC) as a collaterall into the mini pool
         * 5. Some time elapse - aTokens and debtTokens appreciate in value
         * 6. User withdraw all his aTokens (aUSDC)
         * Invariants:
         * 1. User shall be able to withdraw all user's balance
         * 2. After user's withdrawal, aTokens balance for AERC6909 tokens (in minipool) shall be 0 (because the user was the only one who ever deposited)
         */
        address user = makeAddr("user");
        address user2 = makeAddr("user2");

        TokenParams memory tokenParamsUsdc = TokenParams(erc20Tokens[0], aTokensWrapper[0], 0);
        TokenParams memory tokenParamsWbtc = TokenParams(erc20Tokens[1], aTokensWrapper[1], 0);

        uint256 amountUsdc = 1000 * (10 ** tokenParamsUsdc.token.decimals());
        uint256 amountwBtc = 1 * (10 ** tokenParamsWbtc.token.decimals());

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        uint256 USDC_OFFSET = 0;

        /* Deposit tests */
        fixture_depositTokensToMainPool(amountUsdc, user, tokenParamsUsdc);

        fixture_depositTokensToMainPool(amountwBtc, user2, tokenParamsWbtc);

        vm.startPrank(user2);
        deployedContracts.lendingPool.borrow(
            address(tokenParamsUsdc.token), true, amountUsdc, user2
        );
        assertEq(amountUsdc, tokenParamsUsdc.token.balanceOf(address(user2)));

        assertEq(0, tokenParamsUsdc.token.balanceOf(address(user)));
        vm.stopPrank();

        uint256 amtAUsdc = tokenParamsUsdc.aToken.balanceOf(address(user)) / 2;
        fixture_depositATokensToMiniPool(
            amtAUsdc, 1000 + USDC_OFFSET, user, tokenParamsUsdc, aErc6909Token
        );

        skip(10 days);

        assertLt(amtAUsdc, aTokens[0].balanceOf(address(aErc6909Token)));
        console.log("Balance before: ", tokenParamsUsdc.aToken.balanceOf(address(aErc6909Token)));
        console.log("Balance to withdraw: ", aErc6909Token.balanceOf(user, 1000 + USDC_OFFSET));
        vm.startPrank(user);
        IMiniPool(miniPool).withdraw(
            address(tokenParamsUsdc.aToken), aErc6909Token.balanceOf(user, 1000 + USDC_OFFSET), user
        );
        console.log("Balance after: ", tokenParamsUsdc.aToken.balanceOf(address(aErc6909Token)));

        assertEq(
            0,
            tokenParamsUsdc.aToken.balanceOf(address(aErc6909Token)),
            "Balance is not 0 after withdrawal"
        );
        vm.stopPrank();
    }

    // Zigtur H7
    function testMinipoolIRStrategyOverflow() public {
        address user = makeAddr("user");
        address user2 = makeAddr("user2");

        TokenParams memory tokenParamsUsdc = TokenParams(erc20Tokens[0], aTokensWrapper[0], 0);
        TokenParams memory tokenParamsWbtc = TokenParams(erc20Tokens[1], aTokensWrapper[1], 0);

        uint256 amountUsdc = 100000 * (10 ** tokenParamsUsdc.token.decimals());
        uint256 amountwBtc = 1 * (10 ** tokenParamsWbtc.token.decimals());

        miniPoolContracts.miniPoolAddressesProvider.setFlowLimit(address(tokenParamsUsdc.token), miniPool, 10000e6);

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        uint256 USDC_OFFSET = 0;
        uint256 WBTC_OFFSET = 1;

        /* Deposit tests */
        fixture_depositTokensToMainPool(amountUsdc, user, tokenParamsUsdc);

        fixture_depositTokensToMainPool(amountwBtc, user2, tokenParamsWbtc);
        fixture_depositTokensToMainPool(amountUsdc, user2, tokenParamsUsdc);


        fixture_depositATokensToMiniPool(
            10_000e6, 1000 + USDC_OFFSET, user, tokenParamsUsdc, aErc6909Token
        );

        // USDC price = 1,00000000
        // WBTC price =  670000,0000000

        fixture_depositATokensToMiniPool(
            1e8, 1000 + WBTC_OFFSET, user2, tokenParamsWbtc, aErc6909Token
        );

        vm.prank(user2);
        IMiniPool(miniPool).borrow(address(tokenParamsUsdc.aToken), 19_999e6, user2);

        skip(100 days);

        vm.startPrank(user2);
        uint256 balanceUsdcOwed = aErc6909Token.balanceOf(user2, 2000 + USDC_OFFSET);
        tokenParamsUsdc.aToken.approve(address(miniPool), balanceUsdcOwed);
        IMiniPool(miniPool).repay(
            address(tokenParamsUsdc.aToken), 1, user2
        );
        vm.stopPrank();
    }
}
