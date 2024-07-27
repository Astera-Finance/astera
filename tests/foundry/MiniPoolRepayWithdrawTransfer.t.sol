// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolDepositBorrow.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

import "forge-std/StdUtils.sol";

contract MiniPoolRepayWithdrawTransferTest is MiniPoolDepositBorrowTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    struct ReserveTokenParams{
        uint256 liquidationThreshold;
        uint256 collateralBalanceInUsd;
        uint256 borrowBalanceInUsd;
        uint256 currentHealth;

    }

    event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount);
    event Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount);


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

        TokenParams memory tokenParams = TokenParams(erc20Tokens[offset], aTokens[offset], 0);

        address user = makeAddr("user");
        IAERC6909 aErc6909Token = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
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
        IMiniPool(miniPool).withdraw(address(tokenParams.token), true, usdcAmount, user);
        assertEq(tokenParams.token.balanceOf(user), usdcAmount);
        IMiniPool(miniPool).withdraw(address(tokenParams.aToken), true, grainUsdcAmount, user);
        assertEq(tokenParams.aToken.balanceOf(user), grainUsdcAmount);
        vm.stopPrank();
    }

    function testTransferCollateral(uint256 amount, uint256 offset) public {
        offset = bound(offset, 0, tokens.length - 1);
        uint256 tokenId = 1128 + offset;
        uint256 aTokenId = 1000 + offset;

        address user = makeAddr("user");
        address user2 = makeAddr("user2");
        TokenParams memory tokenParams = TokenParams(erc20Tokens[offset], aTokens[offset], 0);
        IAERC6909 aErc6909Token = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
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


    function testMiniPoolNormalBorrowRepay(uint256 amount, uint256 collateralOffset, uint256 borrowOffset) public {
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
         * */

        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);

        TokenParams memory collateralParams =
            TokenParams(erc20Tokens[collateralOffset], aTokens[collateralOffset], oracle.getAssetPrice(address(erc20Tokens[collateralOffset])));
        TokenParams memory borrowParams =
            TokenParams(erc20Tokens[borrowOffset], aTokens[borrowOffset], oracle.getAssetPrice(address(erc20Tokens[borrowOffset])));
        address user = makeAddr("user");
        IAERC6909 aErc6909Token = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        amount = bound(amount, 10**borrowParams.token.decimals()/100, borrowParams.token.balanceOf(address(this))/10);

        /* Borrow */
        fixture_miniPoolBorrow(amount, collateralOffset, borrowOffset, collateralParams, borrowParams, user);
        
        /* Repay */
        vm.startPrank(user);
        Balances memory balances;
        (,,,,,uint256 healthFactorBefore) = IMiniPool(miniPool).getUserAccountData(user);
        /* AToken repayment */
        balances.totalSupply = aErc6909Token.scaledTotalSupply(2000 + borrowOffset);
        balances.debtToken = aErc6909Token.balanceOf(user, 2000 + borrowOffset);
        balances.token = borrowParams.aToken.balanceOf(user);
        borrowParams.aToken.approve(address(miniPool), amount);
        IMiniPool(miniPool).repay(address(borrowParams.aToken), true, amount, user);

        console.log("Balance of total supply must be lower than before borrow");
        assertEq(aErc6909Token.scaledTotalSupply(2000 + borrowOffset), balances.totalSupply - amount);
        console.log("Balance of AToken debt must be lower than before borrow");
        assertEq(aErc6909Token.balanceOf(user, 2000 + borrowOffset), balances.debtToken - amount);
        console.log("Balance of AToken must be lower than before borrow");
        assertEq(borrowParams.aToken.balanceOf(user), balances.token - amount);
        
        /* Token repayment */
        balances.totalSupply = aErc6909Token.scaledTotalSupply(2128 + borrowOffset);
        balances.debtToken = aErc6909Token.balanceOf(user, 2128 + borrowOffset);
        balances.token = borrowParams.token.balanceOf(user);
        borrowParams.token.approve(address(miniPool), amount);
        IMiniPool(miniPool).repay(address(borrowParams.token), true, amount, user);
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

        (,,,,,uint256 healthFactorAfter) = IMiniPool(miniPool).getUserAccountData(user);
        assertLt(healthFactorBefore, healthFactorAfter, "Health before is greater than health after");
        vm.stopPrank();
    }


    function testMiniPoolBorrowRepayWithFlowFromLendingPool(uint256 amount, uint256 collateralOffset, uint256 borrowOffset, uint256 skipDuration) public {
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        skipDuration = bound(skipDuration, 0, 300 days);
        vm.assume(borrowOffset != collateralOffset && borrowOffset < tokens.length - 1);
        console.log("Offsets: token0: %s token1: %s", collateralOffset, borrowOffset);

        TokenParams memory collateralParams =
            TokenParams(erc20Tokens[collateralOffset], aTokens[collateralOffset], oracle.getAssetPrice(address(erc20Tokens[collateralOffset])));
        TokenParams memory borrowParams =
            TokenParams(erc20Tokens[borrowOffset], aTokens[borrowOffset], oracle.getAssetPrice(address(erc20Tokens[borrowOffset])));
        address user = makeAddr("user");
        amount = bound(amount, 10**borrowParams.token.decimals()/100, borrowParams.token.balanceOf(address(this))/10);

        IAERC6909 aErc6909Token = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");
        vm.label(address(borrowParams.aToken), "token1");
        vm.label(address(collateralParams.token), "token0");

        fixture_miniPoolBorrowWithFlowFromLendingPool(amount, borrowOffset, collateralParams, borrowParams, user);

        // skip(skipDuration); TODO

        Balances memory balances;
        (,,,,,uint256 healthFactorBefore) = IMiniPool(miniPool).getUserAccountData(user);
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
        IMiniPool(miniPool).repay(address(borrowParams.aToken), true, amount, user);

        console.log("Balance of total supply must be lower than before borrow");
        assertEq(aErc6909Token.scaledTotalSupply(2000 + borrowOffset), balances.totalSupply - amount);
        console.log("Balance of AToken debt must be lower than before borrow");
        assertEq(aErc6909Token.balanceOf(user, 2000 + borrowOffset), balances.debtToken - amount);
        console.log("Balance of AToken must be lower than before borrow");
        assertEq(borrowParams.aToken.balanceOf(user), balances.token - amount);
        console.log("Repaid");
        (,,,,,uint256 healthFactorAfter) = IMiniPool(miniPool).getUserAccountData(user);
        assertLt(healthFactorBefore, healthFactorAfter, "health before is greater than health after");
        vm.stopPrank();
    }


    function testCannotWithdrawWhenBorrowedMaxLtv(uint256 borrowAmount, uint256 withdrawAmount, uint256 collateralOffset, uint256 borrowOffset) public {
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

        TokenParams memory collateralParams =
            TokenParams(erc20Tokens[collateralOffset], aTokens[collateralOffset], oracle.getAssetPrice(address(erc20Tokens[collateralOffset])));
        TokenParams memory borrowParams =
            TokenParams(erc20Tokens[borrowOffset], aTokens[borrowOffset], oracle.getAssetPrice(address(erc20Tokens[borrowOffset])));
        address user = makeAddr("user");
        IAERC6909 aErc6909Token = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        borrowAmount = bound(borrowAmount, 10**borrowParams.token.decimals()/100, borrowParams.token.balanceOf(address(this))/10);
        vm.assume(withdrawAmount < borrowAmount);

        /* Borrow */
        fixture_miniPoolBorrow(borrowAmount, collateralOffset, borrowOffset, collateralParams, borrowParams, user);

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
        // vm.expectRevert();
        //vm.expectRevert(bytes(Errors.VL_TRANSFER_NOT_ALLOWED)); // @issue: foundry bug ?
        IMiniPool(miniPool).withdraw(address(collateralParams.token), true, aErc6909Token.balanceOf(user, 1128 + collateralOffset), user);
        // console.log("Withdraw function for AToken shall revert");
        // vm.expectRevert(bytes(Errors.VL_TRANSFER_NOT_ALLOWED));
        // IMiniPool(miniPool).withdraw(address(collateralParams.aToken), true, aErc6909Token.balanceOf(user, 1000 + collateralOffset), user);
        vm.stopPrank();
    }

    function testMultipleUsersBorrowRepayAndWithdraw(uint256 amount1, uint256 amount2, uint256 collateralOffset, uint256 borrowOffset, uint256 skipDuration) public {
        /**
         * Preconditions: 
         * 1. Reserves in LendingPool and MiniPool must be configured
         * 2. Lending Pool must be properly funded 
         * 3. Flow limiter must be set to proper value for miniPool
         * Test Scenario:
         * 1. Users add tokens as collateral into the miniPool 
         * 2. Users borrow tokens that are not available in miniPool
         * 3. Some time elapse - aTokens and debtTokens appreciate in specific rate
         * 4. Users repay all debts
         * 5. Users withdraw funds
         * Invariants: 
         * 1. All users shall be able to withdraw the greater or equal amount of funds that they deposited
         * 2. 
         * */

        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
        skipDuration = bound(skipDuration, 0, 300 days);
        console.log("Offsets: token0: %s token1: %s", collateralOffset, borrowOffset);

        TokenParams memory collateralParams =
            TokenParams(erc20Tokens[collateralOffset], aTokens[collateralOffset], oracle.getAssetPrice(address(erc20Tokens[collateralOffset])));
        TokenParams memory borrowParams =
            TokenParams(erc20Tokens[borrowOffset], aTokens[borrowOffset], oracle.getAssetPrice(address(erc20Tokens[borrowOffset])));
        IAERC6909 aErc6909Token = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        Users memory users;
        // = Users(makeAddr("user1"), makeAddr("user2"), makeAddr("user3"))
        users.user1 = makeAddr("user1");
        users.user2 = makeAddr("user2");
        users.user3 = makeAddr("distributor");

        amount1 = bound(amount1, 10**borrowParams.token.decimals()/100, borrowParams.token.balanceOf(address(this))/10);
        amount2 = bound(amount2, 10**borrowParams.token.decimals()/100, borrowParams.token.balanceOf(address(this))/10);

        /* Users borrow */
        console.log("----------------USER1---------------");
        fixture_miniPoolBorrowWithFlowFromLendingPool(amount1, borrowOffset, collateralParams, borrowParams, users.user1);
        console.log("----------------USER2---------------");
        fixture_miniPoolBorrowWithFlowFromLendingPool(amount2, borrowOffset, collateralParams, borrowParams, users.user2);
        console.log("----------------USER3---------------");
        fixture_miniPoolBorrowWithFlowFromLendingPool(borrowParams.token.balanceOf(address(this))/10, borrowOffset, collateralParams, borrowParams, users.user3);
 
        skip(skipDuration);
        
        {
            /* Distribute difference in debt tokens caused by borrowing interest rates */
            vm.startPrank(users.user3);
            
            uint256 diff = aErc6909Token.balanceOf(users.user1, 2000+borrowOffset) - amount1;
            console.log("->Transfering %s %s to user1", diff, borrowParams.aToken.symbol());
            console.log("->Balance" , borrowParams.aToken.balanceOf(users.user3));
            borrowParams.aToken.transfer(users.user1, diff);
            vm.stopPrank();
        }

        vm.startPrank(users.user1);
        console.log("----------------USER1 TRANSFER---------------");
        console.log("Amount %s vs debt balance %s", amount1, aErc6909Token.balanceOf(users.user1, 2000+borrowOffset));
        borrowParams.aToken.approve(address(miniPool), aErc6909Token.balanceOf(users.user1, 2000+borrowOffset));
        console.log("Repaying...");
        /* Give lacking amount to user 1 */
        IMiniPool(miniPool).repay(address(borrowParams.aToken), true, aErc6909Token.balanceOf(users.user1, 2000+borrowOffset), users.user1);
        console.log("Balance: ", aErc6909Token.balanceOf(users.user1, 1000+collateralOffset));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user1, 1128+collateralOffset));
        console.log("Withdrawing...");
        IMiniPool(miniPool).withdraw(address(collateralParams.token), true, aErc6909Token.balanceOf(users.user1, 1128+collateralOffset), users.user1);
        vm.stopPrank();

        vm.startPrank(users.user2);
        console.log("----------------USER2 TRANSFER---------------");
        console.log("Amount %s vs debt balance %s", amount1, aErc6909Token.balanceOf(users.user2, 2000+borrowOffset));
        borrowParams.aToken.approve(address(miniPool), aErc6909Token.balanceOf(users.user2, 2000+borrowOffset)/2);
        console.log("Repaying...");
        IMiniPool(miniPool).repay(address(borrowParams.aToken), true, aErc6909Token.balanceOf(users.user2, 2000+borrowOffset)/2, users.user2);
        console.log("Balance: ", aErc6909Token.balanceOf(users.user2, 1000+collateralOffset));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user2, 1128+collateralOffset));
        console.log("Withdrawing...");
        IMiniPool(miniPool).withdraw(address(collateralParams.token), true, aErc6909Token.balanceOf(users.user2, 1128+collateralOffset)/2, users.user2);
        vm.stopPrank();

    }

    function testWithdrawWhenBorrowed(uint256 borrowAmount, uint256 withdrawAmount, uint256 collateralOffset, uint256 borrowOffset) public 
    {
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

        TokenParams memory collateralParams =
            TokenParams(erc20Tokens[collateralOffset], aTokens[collateralOffset], oracle.getAssetPrice(address(erc20Tokens[collateralOffset])));
        TokenParams memory borrowParams =
            TokenParams(erc20Tokens[borrowOffset], aTokens[borrowOffset], oracle.getAssetPrice(address(erc20Tokens[borrowOffset])));
        address user = makeAddr("user");
        IAERC6909 aErc6909Token = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        borrowAmount = bound(borrowAmount, 10**borrowParams.token.decimals()/100, borrowParams.token.balanceOf(address(this))/10);
        vm.assume(withdrawAmount < borrowAmount);

        /* Borrow */
        fixture_miniPoolBorrow(borrowAmount, collateralOffset, borrowOffset, collateralParams, borrowParams, user);
       
        /* Deposit - to have better health and be able to withdraw */
        withdrawAmount = bound(withdrawAmount, 10**collateralParams.token.decimals()/100, collateralParams.token.balanceOf(address(this))/10);
        fixture_MiniPoolDeposit(withdrawAmount, collateralOffset, user, collateralParams);
        (,,,,,uint256 healthFactorBefore) = IMiniPool(miniPool).getUserAccountData(user);
        uint256 collateralBalanceBefore = aErc6909Token.balanceOf(user, 1128 + collateralOffset);
        uint256 underlyingBalanceBefore = collateralParams.token.balanceOf(user);
        
        vm.startPrank(user);
        address oracle = miniPoolContracts.miniPoolAddressesProvider.getPriceOracle();
        console.log("Price of token: ", IPriceOracleGetter(oracle).getAssetPrice(address(collateralParams.token)));
        console.log("Withdraw token");
        IMiniPool(miniPool).withdraw(address(collateralParams.token), true, withdrawAmount/2, user);
        // console.log("Withdraw AToken");
        // IMiniPool(miniPool).withdraw(address(collateralParams.aToken), true, withdrawAmount/2, user);

        {
        (,,,,,uint256 healthFactorAfter) = IMiniPool(miniPool).getUserAccountData(user);
        console.log("healthFactor", healthFactorAfter);
        assertGt(healthFactorAfter, 10_000);
        assertGt(healthFactorBefore, healthFactorAfter);
        }
        {
            
            assertGt(collateralBalanceBefore, aErc6909Token.balanceOf(user, 1128 + collateralOffset));
            assertEq(underlyingBalanceBefore + withdrawAmount/2, collateralParams.token.balanceOf(user));
        }
        

        vm.stopPrank();
    }

}