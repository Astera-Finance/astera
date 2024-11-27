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
        console.log("_aTokenBalanceBefore: ", _aTokenBalanceBefore);
        console.log("_aTokenBalanceAfter: ", erc20Token.balanceOf(address(aToken)));
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
        uint256 borrowTokenPrice = oracle.getAssetPrice(address(borrowToken));
        uint256 collateralPrice = oracle.getAssetPrice(address(collateral));
        uint256 collateralDepositValue = amount * collateralPrice / (10 ** PRICE_FEED_DECIMALS);
        StaticData memory staticData = deployedContracts
            .cod3xLendDataProvider
            .getLpReserveStaticData(address(collateral), true);
        uint256 maxBorrowTokenToBorrowInCollateralUnit;
        {
            uint256 collateralMaxBorrowValue = staticData.ltv * collateralDepositValue / 10_000;

            uint256 wbtcMaxBorrowAmountRay = collateralMaxBorrowValue.rayDiv(borrowTokenPrice);
            maxBorrowTokenToBorrowInCollateralUnit = fixture_preciseConvertWithDecimals(
                wbtcMaxBorrowAmountRay, collateral.decimals(), borrowToken.decimals()
            );
            // (usdcMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
        }
        return maxBorrowTokenToBorrowInCollateralUnit;
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

        uint256 borrowTokenDepositAmount = maxBorrowTokenToBorrowInCollateralUnit * 15 / 10;

        require(
            borrowToken.token.balanceOf(provider) > borrowTokenDepositAmount, "Too less borrowToken"
        );

        console.log("borrowTokenDepositAmount: ", borrowTokenDepositAmount);
        /* Provider deposits wbtc thanks to that there is enough funds to borrow */
        fixture_deposit(
            borrowToken.token, borrowToken.aToken, provider, provider, borrowTokenDepositAmount
        );

        uint256 borrowTokenBalanceBeforeBorrow = borrowToken.token.balanceOf(borrower);
        uint256 debtBalanceBefore = borrowToken.debtToken.balanceOf(borrower);

        (, uint256 totalDebt,,,,,) = deployedContracts.cod3xLendDataProvider.getLpReserveDynamicData(
            address(borrowToken.token), true
        );

        StaticData memory staticData = deployedContracts
            .cod3xLendDataProvider
            .getLpReserveStaticData(address(borrowToken.token), true);
        (, uint256 expectedBorrowRate) = deployedContracts.volatileStrategy.calculateInterestRates(
            address(borrowToken.token),
            address(borrowToken.aToken),
            0,
            maxBorrowTokenToBorrowInCollateralUnit,
            totalDebt + maxBorrowTokenToBorrowInCollateralUnit,
            staticData.cod3xReserveFactor
        );
        console.log("1. AToken balance: ", borrowToken.token.balanceOf(address(borrowToken.aToken)));
        /* Borrower borrows maxPossible amount of borrowToken */
        vm.startPrank(borrower);
        vm.expectEmit(true, true, true, true);
        emit Borrow(
            address(borrowToken.token),
            borrower,
            borrower,
            maxBorrowTokenToBorrowInCollateralUnit,
            expectedBorrowRate
        );
        deployedContracts.lendingPool.borrow(
            address(borrowToken.token), true, maxBorrowTokenToBorrowInCollateralUnit, borrower
        );
        vm.stopPrank();
        console.log("2. AToken balance: ", borrowToken.token.balanceOf(address(borrowToken.aToken)));
        /* Main user's balance should be: initial amount + borrowed amount */
        assertEq(
            borrowTokenBalanceBeforeBorrow + maxBorrowTokenToBorrowInCollateralUnit,
            borrowToken.token.balanceOf(borrower),
            "Borrower hasn't more borrowToken than before"
        );
        assertEq(
            debtBalanceBefore + maxBorrowTokenToBorrowInCollateralUnit,
            borrowToken.debtToken.balanceOf(borrower),
            "Borrower hasn't more borrowToken than before"
        );
        return (maxBorrowTokenToBorrowInCollateralUnit);
    }
}
