// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";

abstract contract LendingPoolFixtures is Common {
    using WadRayMath for uint256;

    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    function setUp() public virtual {}

    function fixture_deposit(
        ERC20 erc20Token,
        AToken aToken,
        address sender,
        address receiver,
        uint256 amount
    ) internal {
        uint256 _receiverATokenBalanceBefore = aToken.balanceOf(address(receiver));
        uint256 _senderTokenBalanceTokenBefore = erc20Token.balanceOf(sender);
        uint256 _aTokenBalanceBefore = erc20Token.balanceOf(address(aToken));
        vm.startPrank(sender);
        erc20Token.approve(address(deployedContracts.lendingPool), amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(erc20Token), sender, receiver, amount);
        deployedContracts.lendingPool.deposit(address(erc20Token), true, amount, receiver);
        vm.stopPrank();
        console2.log("_aTokenBalanceBefore: ", _aTokenBalanceBefore);
        console2.log("_aTokenBalanceAfter: ", erc20Token.balanceOf(address(aToken)));
        assertEq(
            _senderTokenBalanceTokenBefore,
            erc20Token.balanceOf(sender) + amount,
            "Sender's token balance is not lower by {amount} after deposit"
        );

        assertEq(
            _receiverATokenBalanceBefore + amount,
            aToken.balanceOf(receiver),
            "Receiver aToken balance is not greater by {amount} after deposit"
        );
    }

    function fixture_withdraw(ERC20 erc20Token, address sender, address receiver, uint256 amount)
        public
    {
        uint256 _receiverTokenBalanceBefore = erc20Token.balanceOf(address(receiver));

        vm.startPrank(sender);
        // vm.expectEmit(true, true, true, true);
        // emit Withdraw(address(erc20Token), sender, receiver, amount);
        deployedContracts.lendingPool.withdraw(address(erc20Token), true, amount, receiver);
        vm.stopPrank();
        assertEq(
            _receiverTokenBalanceBefore + amount,
            erc20Token.balanceOf(receiver),
            "Receiver's token balance is not greater by {amount} after withdrawal"
        );
    }

    function fixture_getMaxValueToBorrow(ERC20 collateral, ERC20 borrowToken, uint256 amount)
        internal
        view
        returns (uint256)
    {
        uint256 borrowTokenPrice = commonContracts.oracle.getAssetPrice(address(borrowToken));
        uint256 collateralPrice = commonContracts.oracle.getAssetPrice(address(collateral));
        uint256 collateralDepositValue = amount * collateralPrice / (10 ** PRICE_FEED_DECIMALS);
        StaticData memory staticData =
            deployedContracts.asteraDataProvider.getLpReserveStaticData(address(collateral), true);
        uint256 maxBorrowTokenToBorrowInCollateralUnit;
        {
            uint256 collateralMaxBorrowValue = staticData.ltv * collateralDepositValue / 10_000;

            uint256 borrowTokenMaxBorrowAmountRay =
                collateralMaxBorrowValue.rayDiv(borrowTokenPrice);
            maxBorrowTokenToBorrowInCollateralUnit = fixture_preciseConvertWithDecimals(
                borrowTokenMaxBorrowAmountRay, collateral.decimals(), borrowToken.decimals()
            );
            // (usdcMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
        }
        return maxBorrowTokenToBorrowInCollateralUnit;
    }

    function fixture_borrow(
        TokenTypes memory borrowToken,
        address provider,
        address borrower,
        uint256 amountToBorrow
    ) public {
        uint256 borrowTokenDepositAmount = amountToBorrow * 15 / 10;

        require(
            borrowToken.token.balanceOf(provider) > borrowTokenDepositAmount, "Too less borrowToken"
        );

        console2.log("borrowTokenDepositAmount: ", borrowTokenDepositAmount);
        /* Provider deposits wbtc thanks to that there is enough funds to borrow */
        fixture_deposit(
            borrowToken.token, borrowToken.aToken, provider, provider, borrowTokenDepositAmount
        );

        uint256 borrowTokenBalanceBeforeBorrow = borrowToken.token.balanceOf(borrower);
        uint256 debtBalanceBefore = borrowToken.debtToken.balanceOf(borrower);

        DynamicData memory dynamicData = deployedContracts
            .asteraDataProvider
            .getLpReserveDynamicData(address(borrowToken.token), true);

        StaticData memory staticData = deployedContracts.asteraDataProvider.getLpReserveStaticData(
            address(borrowToken.token), true
        );
        (, uint256 expectedBorrowRate) = deployedContracts.volatileStrategy.calculateInterestRates(
            address(borrowToken.token),
            address(borrowToken.aToken),
            0,
            amountToBorrow,
            dynamicData.totalVariableDebt + amountToBorrow,
            staticData.asteraReserveFactor
        );
        console2.log(
            "1. AToken balance: ", borrowToken.token.balanceOf(address(borrowToken.aToken))
        );
        /* Borrower borrows maxPossible amount of borrowToken */
        vm.startPrank(borrower);
        vm.expectEmit(true, true, true, true);
        emit Borrow(
            address(borrowToken.token), borrower, borrower, amountToBorrow, expectedBorrowRate
        );
        deployedContracts.lendingPool.borrow(
            address(borrowToken.token), true, amountToBorrow, borrower
        );
        vm.stopPrank();
        console2.log(
            "2. AToken balance: ", borrowToken.token.balanceOf(address(borrowToken.aToken))
        );
        /* Main user's balance should be: initial amount + borrowed amount */
        assertEq(
            borrowTokenBalanceBeforeBorrow + amountToBorrow,
            borrowToken.token.balanceOf(borrower),
            "Borrower hasn't more borrowToken than before"
        );
        assertEq(
            debtBalanceBefore + amountToBorrow,
            borrowToken.debtToken.balanceOf(borrower),
            "Borrower hasn't more borrowToken than before"
        );
    }

    function fixture_depositAndBorrow(
        TokenTypes memory collateral,
        TokenTypes memory borrowToken,
        address provider,
        address borrower,
        uint256 amount
    ) public returns (uint256) {
        /* Borrower deposits collateral and wants to borrow */
        fixture_deposit(collateral.token, collateral.aToken, borrower, borrower, amount);
        uint256 maxBorrowTokenToBorrowInCollateralUnit =
            fixture_getMaxValueToBorrow(collateral.token, borrowToken.token, amount);

        fixture_borrow(borrowToken, provider, borrower, maxBorrowTokenToBorrowInCollateralUnit);

        return (maxBorrowTokenToBorrowInCollateralUnit);
    }

    function fixture_repay(
        TokenTypes memory borrowToken,
        uint256 maxBorrowTokenToBorrowInCollateralUnit,
        address user
    ) public {
        vm.startPrank(user);
        uint256 wbtcBalanceBeforeRepay = borrowToken.token.balanceOf(address(this));
        uint256 wbtcDebtBeforeRepay = borrowToken.debtToken.balanceOf(address(this));
        borrowToken.token.approve(
            address(deployedContracts.lendingPool), maxBorrowTokenToBorrowInCollateralUnit
        );
        deployedContracts.lendingPool.repay(
            address(borrowToken.token), true, maxBorrowTokenToBorrowInCollateralUnit, address(this)
        );
        /* Main user's balance should be the same as before borrowing */
        assertEq(
            wbtcBalanceBeforeRepay,
            borrowToken.token.balanceOf(address(this)) + maxBorrowTokenToBorrowInCollateralUnit,
            "User after repayment has less borrowed tokens"
        );
        assertEq(
            wbtcDebtBeforeRepay,
            borrowToken.debtToken.balanceOf(address(this)) + maxBorrowTokenToBorrowInCollateralUnit,
            "User after repayment has less debt"
        );
        vm.stopPrank();
    }

    function fixture_performAllActions(
        TokenTypes memory collateral,
        TokenTypes memory borrowToken,
        address provider,
        address borrower,
        uint256 amount
    ) public {
        uint256 maxBorrowTokenToBorrowInCollateralUnit;
        maxBorrowTokenToBorrowInCollateralUnit =
            fixture_depositAndBorrow(collateral, borrowToken, provider, borrower, amount);
        fixture_repay(borrowToken, maxBorrowTokenToBorrowInCollateralUnit, borrower);
        fixture_withdraw(collateral.token, borrower, borrower, amount);
    }
}
