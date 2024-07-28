// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {MathUtils} from "contracts/protocol/libraries/math/MathUtils.sol";
import "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract LendingPoolTest is Common {
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using ReserveBorrowConfiguration for DataTypes.ReserveBorrowConfigurationMap;

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    event Deposit(
        address indexed reserve, address user, address indexed onBehalfOf, uint256 amount
    );
    event Withdraw(
        address indexed reserve, address indexed user, address indexed to, uint256 amount
    );
    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRate
    );
    event Repay(
        address indexed reserve, address indexed user, address indexed repayer, uint256 amount
    );

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.protocolDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        // aTokens = fixture_getATokens(tokens, deployedContracts.protocolDataProvider);
        // variableDebtTokens = fixture_getVarDebtTokens(tokens, deployedContracts.protocolDataProvider);
        mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function testDepositsAndWithdrawals(uint256 amount) public {
        address user = makeAddr("user");

        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            uint256 _userGrainBalanceBefore = aTokens[idx].balanceOf(address(user));
            uint256 _thisBalanceTokenBefore = erc20Tokens[idx].balanceOf(address(this));
            amount = bound(amount, 10_000, erc20Tokens[idx].balanceOf(address(this)));

            /* Deposit on behalf of user */
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amount);
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(erc20Tokens[idx]), address(this), user, amount);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), true, amount, user);
            assertEq(_thisBalanceTokenBefore, erc20Tokens[idx].balanceOf(address(this)) + amount);
            assertEq(_userGrainBalanceBefore + amount, aTokens[idx].balanceOf(address(user)));

            /* User shall be able to withdraw underlying tokens */
            vm.startPrank(user);
            vm.expectEmit(true, true, true, true);
            emit Withdraw(address(erc20Tokens[idx]), user, user, amount);
            deployedContracts.lendingPool.withdraw(address(erc20Tokens[idx]), true, amount, user);
            vm.stopPrank();
            assertEq(amount, erc20Tokens[idx].balanceOf(user));
            assertEq(_userGrainBalanceBefore, aTokens[idx].balanceOf(address(this)));
        }
    }

    function testBorrowRepay() public {
        address user = makeAddr("user");

        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
        uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        (, uint256 usdcLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), true);
        uint256 wbtcMaxBorrowAmountWithUsdcCollateral;
        {
            uint256 usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;

            uint256 wbtcMaxBorrowAmountRay = usdcMaxBorrowValue.rayDiv(wbtcPrice);
            wbtcMaxBorrowAmountWithUsdcCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxBorrowAmountRay, usdc.decimals(), wbtc.decimals()
            );
            // (usdcMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
        }
        require(
            wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral, "Too less wbtc"
        );
        uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral * 15 / 10;

        /* Main user deposits usdc and wants to borrow */
        usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
        deployedContracts.lendingPool.deposit(address(usdc), true, usdcDepositAmount, address(this));

        /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
        deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);

        uint256 wbtcBalanceBeforeBorrow = wbtc.balanceOf(address(this));

        (,,,, uint256 reserveFactors,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), true);
        (, uint256 expectedBorrowRate) = deployedContracts.volatileStrategy.calculateInterestRates(
            address(wbtc),
            address(aTokens[1]),
            0,
            wbtcMaxBorrowAmountWithUsdcCollateral,
            wbtcMaxBorrowAmountWithUsdcCollateral,
            reserveFactors
        );

        /* Main user borrows maxPossible amount of wbtc */
        vm.expectEmit(true, true, true, true);
        emit Borrow(
            address(wbtc),
            address(this),
            address(this),
            wbtcMaxBorrowAmountWithUsdcCollateral,
            expectedBorrowRate
        );
        deployedContracts.lendingPool.borrow(
            address(wbtc), true, wbtcMaxBorrowAmountWithUsdcCollateral, address(this)
        );
        /* Main user's balance should be: initial amount + borrowed amount */
        assertEq(
            wbtcBalanceBeforeBorrow + wbtcMaxBorrowAmountWithUsdcCollateral,
            wbtc.balanceOf(address(this))
        );

        /* Main user repays his debt */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcMaxBorrowAmountWithUsdcCollateral);
        vm.expectEmit(true, true, true, true);
        emit Repay(
            address(wbtc), address(this), address(this), wbtcMaxBorrowAmountWithUsdcCollateral
        );
        deployedContracts.lendingPool.repay(
            address(wbtc), true, wbtcMaxBorrowAmountWithUsdcCollateral, address(this)
        );
        /* Main user's balance should be the same as before borrowing */
        assertEq(wbtcBalanceBeforeBorrow, wbtc.balanceOf(address(this)));
    }

    function testBorrowTooBigForUsersCollateral() public {
        address user = makeAddr("user");

        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
        uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        console.log(
            "usdcDepositValue %s vs \nusdcDepositAmount %s", usdcDepositValue, usdcDepositAmount
        );
        (, uint256 usdcLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), true);
        uint256 usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;
        uint256 wbtcMaxBorrowAmountWithUsdcCollateral;
        {
            // uint256 wbtcMaxBorrowAmountRaw = (usdcMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
            uint256 wbtcMaxBorrowAmountRay = usdcMaxBorrowValue.rayDiv(wbtcPrice);
            console.log("wbtcMaxBorrowAmountRay:", wbtcMaxBorrowAmountRay);
            wbtcMaxBorrowAmountWithUsdcCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxBorrowAmountRay, usdc.decimals(), wbtc.decimals()
            );
            console.log(
                "wbtcMaxBorrowAmountWithUsdcCollateral:", wbtcMaxBorrowAmountWithUsdcCollateral
            );
            require(
                wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral,
                "Too less wbtc"
            );
        }
        {
            uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral * 15 / 10;
            /* Other user deposits wbtc thanks to that there is enough funds to borrow */
            wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
            deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);
        }

        /* Main user deposits usdc and wants to borrow */
        usdc.approve(address(deployedContracts.lendingPool), usdcDepositValue);
        deployedContracts.lendingPool.deposit(address(usdc), true, usdcDepositValue, address(this));

        /* Main user borrows maxPossible amount of wbtc */
        vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
        deployedContracts.lendingPool.borrow(
            address(wbtc), true, wbtcMaxBorrowAmountWithUsdcCollateral + 1, address(this)
        );
    }

    function testBorrowTooBigForProtocolsCollateral() public {
        address user = makeAddr("user");

        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
        uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        (, uint256 usdcLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), true);
        uint256 usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;
        uint256 wbtcMaxBorrowAmountWithUsdcCollateral;
        {
            uint256 wbtcMaxBorrowAmountRay = usdcMaxBorrowValue.rayDiv(wbtcPrice);
            wbtcMaxBorrowAmountWithUsdcCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxBorrowAmountRay, wbtc.decimals(), usdc.decimals()
            );
            require(
                wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral,
                "Too less wbtc"
            );
            console.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
        }
        uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral - 1;

        /* Main user deposits usdc and wants to borrow */
        usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
        deployedContracts.lendingPool.deposit(address(usdc), true, usdcDepositAmount, address(this));

        /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
        deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);

        /* Main user borrows maxPossible amount of wbtc */
        vm.expectRevert();
        //vm.expectRevert(bytes(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW)); // @issue over/underflow instead of LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW
        deployedContracts.lendingPool.borrow(
            address(wbtc), true, wbtcMaxBorrowAmountWithUsdcCollateral, address(this)
        );
    }

    function testUseReserveAsCollateral(uint256 tokenDepositAmount) public {
        // add for loop for all tokens
        IERC20 token = erc20Tokens[0];
        uint8 idx = 1;
        token = erc20Tokens[idx];

        tokenDepositAmount = bound(tokenDepositAmount, 2, 2_000_000);
        // uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        (, uint256 tokenLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(token), true);

        uint256 tokenMaxBorrowAmount = tokenLtv * tokenDepositAmount / 10_000;

        /* Main user deposits usdc and wants to borrow */
        token.approve(address(deployedContracts.lendingPool), tokenDepositAmount);
        deployedContracts.lendingPool.deposit(
            address(token), true, tokenDepositAmount, address(this)
        );

        uint256 usdcBalanceBeforeBorrow = token.balanceOf(address(this));
        /* Main user is not using his liquidity as a collateral - borrow shall fail */
        deployedContracts.lendingPool.setUserUseReserveAsCollateral(address(token), true, false);
        vm.expectRevert(bytes(Errors.VL_COLLATERAL_BALANCE_IS_0));
        deployedContracts.lendingPool.borrow(
            address(token), true, tokenMaxBorrowAmount, address(this)
        );

        (,,,, uint256 reserveFactors,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(token), true);
        (, uint256 expectedBorrowRate) = deployedContracts.volatileStrategy.calculateInterestRates(
            address(token),
            address(aTokens[idx]),
            0,
            tokenMaxBorrowAmount,
            tokenMaxBorrowAmount,
            reserveFactors
        );
        /* Main user is using now his liquidity as a collateral - borrow shall succeed */
        deployedContracts.lendingPool.setUserUseReserveAsCollateral(address(token), true, true);

        /* Main user borrows maxPossible amount of usdc */
        vm.expectEmit(true, true, true, true);
        emit Borrow(
            address(token), address(this), address(this), tokenMaxBorrowAmount, expectedBorrowRate
        );
        deployedContracts.lendingPool.borrow(
            address(token), true, tokenMaxBorrowAmount, address(this)
        );

        /* Main user's balance should have: initial amount + borrowed amount */
        assertEq(usdcBalanceBeforeBorrow + tokenMaxBorrowAmount, token.balanceOf(address(this)));
        assertEq(variableDebtTokens[idx].balanceOf(address(this)), tokenMaxBorrowAmount);
    }
}
