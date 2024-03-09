// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract ATokenTest is Common {
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    event Deposit(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount);
    event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount);
    event Borrow(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount, uint256 borrowRate);
    event Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount);

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider,
            deployedContracts.protocolDataProvider
        );
        (grainTokens, variableDebtTokens) =
            fixture_getGrainTokensAndDebts(tokens, deployedContracts.protocolDataProvider);
        mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, tokensWhales, address(this));
    }

    function testDepositsAndWithdrawals(uint256 amount) public {
        address user = makeAddr("user");

        for (uint32 idx = 0; idx < grainTokens.length; idx++) {
            uint256 _userGrainBalanceBefore = grainTokens[idx].balanceOf(address(user));
            // uint256 _userBalanceNextTokenBefore = erc20Tokens[nextTokenIndex].balanceOf(user);
            uint256 _thisBalanceTokenBefore = erc20Tokens[idx].balanceOf(address(this));
            // uint256 _thisBalanceNextTokenBefore = erc20Tokens[nextTokenIndex].balanceOf(address(this));
            amount = bound(amount, 10_000, erc20Tokens[idx].balanceOf(address(this)));

            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amount);
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(erc20Tokens[idx]), address(this), user, amount);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), false, amount, user);
            console.log("_thisBalanceTokenBefore: ", _thisBalanceTokenBefore);
            console.log("grainTokens[idx].balanceOf(address(this)): ", grainTokens[idx].balanceOf(address(this)));
            assertEq(_thisBalanceTokenBefore, erc20Tokens[idx].balanceOf(address(this)) + amount);
            assertEq(_userGrainBalanceBefore + amount, grainTokens[idx].balanceOf(address(user)));

            vm.startPrank(user);
            vm.expectEmit(true, true, true, true);
            emit Withdraw(address(erc20Tokens[idx]), user, address(this), amount);
            deployedContracts.lendingPool.withdraw(address(erc20Tokens[idx]), false, amount, address(this));
            vm.stopPrank();
            console.log("_thisBalanceTokenBefore: ", _thisBalanceTokenBefore);
            console.log("grainTokens[idx].balanceOf(address(this)): ", grainTokens[idx].balanceOf(user));
            assertEq(_thisBalanceTokenBefore, erc20Tokens[idx].balanceOf(address(this)));
            assertEq(_userGrainBalanceBefore, grainTokens[idx].balanceOf(address(this)));
        }
    }

    function testBorrowRepay() public {
        address user = makeAddr("user");

        IERC20 usdc = erc20Tokens[0];
        IERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc)); // 6e12 / 1e6; /* $60k / $1 */ // TODO - price feeds
        uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
        uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        (, uint256 usdcLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), false);
        // (, uint256 wbtcLtv,,,,,,,) =
        //     deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), false);
        console.log("LTV: ", usdcLtv);
        uint256 usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;

        console.log("Price: ", wbtcPrice);
        uint256 wbtcMaxBorrowAmountWithUsdcCollateral = (usdcMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
        require(wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral, "Too less wbtc");
        console.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
        uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral * 15 / 10;

        /* Main user deposits usdc and wants to borrow */
        usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
        deployedContracts.lendingPool.deposit(address(usdc), false, usdcDepositAmount, address(this));

        /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
        deployedContracts.lendingPool.deposit(address(wbtc), false, wbtcDepositAmount, user);

        uint256 wbtcBalanceBeforeBorrow = wbtc.balanceOf(address(this));
        console.log("Wbtc balance before: ", wbtcBalanceBeforeBorrow);

        /* Main user borrows maxPossible amount of wbtc */
        // vm.expectEmit(true, true, true, true);
        // emit Borrow(
        //     address(wbtc),
        //     address(this),
        //     address(this),
        //     wbtcMaxBorrowAmountWithUsdcCollateral,
        //     1251838485129347319607618207 // TODO
        // );
        deployedContracts.lendingPool.borrow(address(wbtc), false, wbtcMaxBorrowAmountWithUsdcCollateral, address(this));
        /* Main user's balance should be: initial amount + borrowed amount */
        assertEq(wbtcBalanceBeforeBorrow + wbtcMaxBorrowAmountWithUsdcCollateral, wbtc.balanceOf(address(this)));
        console.log("Wbtc balance after: ", wbtc.balanceOf(address(this)));
        /* Main user repays his debt */

        wbtc.approve(address(deployedContracts.lendingPool), wbtcMaxBorrowAmountWithUsdcCollateral);
        vm.expectEmit(true, true, true, true);
        emit Repay(address(wbtc), address(this), address(this), wbtcMaxBorrowAmountWithUsdcCollateral);
        deployedContracts.lendingPool.repay(address(wbtc), false, wbtcMaxBorrowAmountWithUsdcCollateral, address(this));
        /* Main user's balance should be the same as before borrowing */
        assertEq(wbtcBalanceBeforeBorrow, wbtc.balanceOf(address(this)));
        console.log("Wbtc balance end: ", wbtc.balanceOf(address(this)));
    }

    function testBorrowTooBigForUsersCollateral() public {
        address user = makeAddr("user");

        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc)); // 6e12 / 1e6; /* $60k / $1 */ // TODO - price feeds
        uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
        uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        console.log("usdc value: ", usdcDepositValue);
        (, uint256 usdcLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), false);
        // (, uint256 wbtcLtv,,,,,,,) =
        //     deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), false);
        console.log("LTV: ", usdcLtv);
        uint256 usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;
        uint256 wbtcMaxBorrowAmountWithUsdcCollateral;
        console.log("Price: ", wbtcPrice);
        {
            uint256 wbtcMaxBorrowAmountRaw = (usdcMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
            wbtcMaxBorrowAmountWithUsdcCollateral = (wbtc.decimals() > usdc.decimals())
                ? wbtcMaxBorrowAmountRaw * (10 ** (wbtc.decimals() - usdc.decimals()))
                : wbtcMaxBorrowAmountRaw / (10 ** (usdc.decimals() - wbtc.decimals()));
            require(wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral, "Too less wbtc");
            console.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
        }
        {
            uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral * 15 / 10;
            /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
            wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
            deployedContracts.lendingPool.deposit(address(wbtc), false, wbtcDepositAmount, user);
        }

        /* Main user deposits usdc and wants to borrow */
        usdc.approve(address(deployedContracts.lendingPool), usdcDepositValue);
        deployedContracts.lendingPool.deposit(address(usdc), false, usdcDepositValue, address(this));

        /* Main user borrows maxPossible amount of wbtc */
        vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
        deployedContracts.lendingPool.borrow(
            address(wbtc), false, wbtcMaxBorrowAmountWithUsdcCollateral + 100, address(this)
        );
        // Issue: Why we not having error for +1 ?
    }

    function testBorrowTooBigForProtocolsCollateral() public {
        address user = makeAddr("user");

        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc)); // 6e12 / 1e6; /* $60k / $1 */ // TODO - price feeds
        uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
        uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        console.log("usdc value: ", usdcDepositValue);
        (, uint256 usdcLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), false);
        // (, uint256 wbtcLtv,,,,,,,) =
        //     deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), false);
        console.log("LTV: ", usdcLtv);
        uint256 usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;
        uint256 wbtcMaxBorrowAmountWithUsdcCollateral;
        console.log("Price: ", wbtcPrice);
        {
            wbtcMaxBorrowAmountWithUsdcCollateral = fixture_calcMaxAmountToBorrowBasedOnCollateral(
                usdcMaxBorrowValue, wbtcPrice, usdc.decimals(), wbtc.decimals()
            );
            require(wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral, "Too less wbtc");
            console.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
        }
        uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral - 1;

        /* Main user deposits usdc and wants to borrow */
        usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
        deployedContracts.lendingPool.deposit(address(usdc), false, usdcDepositAmount, address(this));

        /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
        deployedContracts.lendingPool.deposit(address(wbtc), false, wbtcDepositAmount, user);

        /* Main user borrows maxPossible amount of wbtc */
        vm.expectRevert();
        //vm.expectRevert(bytes(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW)); // Issue: over/underflow instead of LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW
        deployedContracts.lendingPool.borrow(address(wbtc), false, wbtcMaxBorrowAmountWithUsdcCollateral, address(this));
    }

    function testUseReserveAsCollateral() public {
        address user = makeAddr("user");

        // add for loop for all tokens
        IERC20 usdc = erc20Tokens[0];
        IERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here
        uint256 wbtcPriceInUsdc = oracle.getAssetPrice(address(wbtc)); // 6e12 / 1e6; /* $60k / $1 */ // TODO - price feeds
        (, uint256 usdcLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), false);
        // (, uint256 wbtcLtv,,,,,,,) =
        //     deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), false);
        console.log("LTV: ", usdcLtv);
        uint256 usdcMaxBorrowAmount = usdcLtv * usdcDepositAmount / 10_000;

        console.log("Price: ", wbtcPriceInUsdc);
        uint256 wbtcMaxBorrowAmountWithUsdcCollateral = usdcMaxBorrowAmount * 1e10 / wbtcPriceInUsdc;
        require(wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral, "Too less wbtc");
        console.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
        uint256 wbtcDepositAmount = wbtc.balanceOf(address(this));

        /* Main user deposits usdc and wants to borrow */
        usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
        deployedContracts.lendingPool.deposit(address(usdc), false, usdcDepositAmount, address(this));

        /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
        deployedContracts.lendingPool.deposit(address(wbtc), false, wbtcDepositAmount, user);

        uint256 usdcBalanceBeforeBorrow = usdc.balanceOf(address(this));
        console.log("Usdc balance before: ", usdcBalanceBeforeBorrow);

        deployedContracts.lendingPool.setUserUseReserveAsCollateral(address(usdc), false, false);
        vm.expectRevert(bytes(Errors.VL_COLLATERAL_BALANCE_IS_0));
        deployedContracts.lendingPool.borrow(address(usdc), false, usdcMaxBorrowAmount, address(this));

        deployedContracts.lendingPool.setUserUseReserveAsCollateral(address(usdc), false, true);
        /* Main user borrows maxPossible amount of wbtc */
        vm.expectEmit(true, true, true, true);
        emit Borrow(
            address(usdc),
            address(this),
            address(this),
            usdcMaxBorrowAmount,
            40000000000000000000000000 // TODO
        );
        deployedContracts.lendingPool.borrow(address(usdc), false, usdcMaxBorrowAmount, address(this));
        /* Main user's balance should be: initial amount + borrowed amount */
        assertEq(usdcBalanceBeforeBorrow + usdcMaxBorrowAmount, usdc.balanceOf(address(this)));
        console.log("Usdc balance after: ", usdc.balanceOf(address(this)));
    }
}
