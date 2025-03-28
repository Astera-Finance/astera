// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./LendingPoolFixtures.t.sol";
import "../../contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "../../contracts/protocol/libraries/math/WadRayMath.sol";
import {MathUtils} from "../../contracts/protocol/libraries/math/MathUtils.sol";
import "../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract LendingPoolTest is LendingPoolFixtures {
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    ERC20[] erc20Tokens;

    function setUp() public override {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.cod3xLendDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(commonContracts.aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        // aTokens = fixture_getATokens(tokens, deployedContracts.cod3xLendDataProvider);
        // variableDebtTokens = fixture_getVarDebtTokens(tokens, deployedContracts.cod3xLendDataProvider);
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function testDepositsAndWithdrawals(uint256 amount) public {
        address user = makeAddr("user");

        for (uint32 idx = 0; idx < commonContracts.aTokens.length; idx++) {
            amount = bound(amount, 10_000, erc20Tokens[idx].balanceOf(address(this)));

            /* Deposit on behalf of user */
            uint256 _aTokenBalanceBefore =
                erc20Tokens[idx].balanceOf(address(commonContracts.aTokens[idx]));
            fixture_deposit(
                erc20Tokens[idx], commonContracts.aTokens[idx], address(this), user, amount
            );
            assertEq(
                _aTokenBalanceBefore + amount,
                erc20Tokens[idx].balanceOf(address(commonContracts.aTokens[idx])),
                "AToken's token balance is not greater by {amount} after deposit"
            );

            /* User shall be able to withdraw underlying tokens */
            _aTokenBalanceBefore = erc20Tokens[idx].balanceOf(address(commonContracts.aTokens[idx]));
            fixture_withdraw(erc20Tokens[idx], user, user, amount);
            assertEq(
                _aTokenBalanceBefore,
                erc20Tokens[idx].balanceOf(address(commonContracts.aTokens[idx])) + amount,
                "AToken's token balance is not lower by {amount} after withdrawal"
            );
        }
    }

    function testBorrowRepay_() public {
        address user = makeAddr("user");

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

        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        deal(address(usdcTypes.token), address(this), 2 * usdcDepositAmount);
        uint256 maxValToBorrow =
            fixture_getMaxValueToBorrow(usdcTypes.token, wbtcTypes.token, usdcDepositAmount);
        deal(address(wbtcTypes.token), user, 2 * maxValToBorrow);

        (uint256 maxBorrowTokenToBorrowInCollateralUnit) =
            fixture_depositAndBorrow(usdcTypes, wbtcTypes, user, address(this), usdcDepositAmount);

        /* Main user repays his debt */
        uint256 wbtcBalanceBeforeRepay = wbtcTypes.token.balanceOf(address(this));
        uint256 wbtcDebtBeforeRepay = wbtcTypes.debtToken.balanceOf(address(this));
        wbtcTypes.token.approve(
            address(deployedContracts.lendingPool), maxBorrowTokenToBorrowInCollateralUnit
        );
        vm.expectEmit(true, true, true, true);
        emit Repay(
            address(wbtcTypes.token),
            address(this),
            address(this),
            maxBorrowTokenToBorrowInCollateralUnit
        );
        deployedContracts.lendingPool.repay(
            address(wbtcTypes.token), true, maxBorrowTokenToBorrowInCollateralUnit, address(this)
        );
        /* Main user's balance should be the same as before borrowing */
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
    }

    function testBorrowTooBigForUsersCollateral() public {
        address user = makeAddr("user");

        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = commonContracts.oracle.getAssetPrice(address(wbtc));
        uint256 usdcPrice = commonContracts.oracle.getAssetPrice(address(usdc));
        uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        console2.log(
            "usdcDepositValue %s vs \nusdcDepositAmount %s", usdcDepositValue, usdcDepositAmount
        );
        StaticData memory staticData =
            deployedContracts.cod3xLendDataProvider.getLpReserveStaticData(address(usdc), true);
        uint256 usdcMaxBorrowValue = staticData.ltv * usdcDepositValue / 10_000;
        uint256 wbtcMaxBorrowAmountWithUsdcCollateral;
        {
            uint256 wbtcMaxBorrowAmountRay = usdcMaxBorrowValue.rayDiv(wbtcPrice);
            console2.log("wbtcMaxBorrowAmountRay:", wbtcMaxBorrowAmountRay);
            wbtcMaxBorrowAmountWithUsdcCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxBorrowAmountRay, usdc.decimals(), wbtc.decimals()
            );
            console2.log(
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
        /**
         * Preconditions:
         * 1. Reserves in LendingPool must be configured
         * 2. Lending Pool must be properly funded
         * Test Scenario:
         * 1. User1 adds certain amount of x token as collateral into the lending pool
         * 2. User2 adds certain amount of y other token as collateral into the lending pool
         * 3. User1 try to borrow greater amount of y tokens than deposited by user2
         * Invariants:
         * 1. Test shall revert with proper error
         */
        address user = makeAddr("user");

        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = commonContracts.oracle.getAssetPrice(address(wbtc));
        uint256 usdcPrice = commonContracts.oracle.getAssetPrice(address(usdc));
        uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        StaticData memory staticData =
            deployedContracts.cod3xLendDataProvider.getLpReserveStaticData(address(usdc), true);
        uint256 usdcMaxBorrowValue = staticData.ltv * usdcDepositValue / 10_000;
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
            console2.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
        }
        uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral - 1;

        /* Main user deposits usdc and wants to borrow */
        usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
        deployedContracts.lendingPool.deposit(address(usdc), true, usdcDepositAmount, address(this));

        /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
        deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);

        /* Main user borrows maxPossible amount of wbtc */
        vm.expectRevert(bytes(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW));
        deployedContracts.lendingPool.borrow(
            address(wbtc), true, wbtcMaxBorrowAmountWithUsdcCollateral, address(this)
        );
    }

    function testUseReserveAsCollateral(uint256 tokenDepositAmount) public {
        // add for loop for all tokens
        IERC20 token = erc20Tokens[0];
        uint8 idx = 1;
        token = erc20Tokens[idx];

        tokenDepositAmount = bound(tokenDepositAmount, 3, 2_000_000);
        // uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        StaticData memory staticData =
            deployedContracts.cod3xLendDataProvider.getLpReserveStaticData(address(token), true);

        uint256 tokenMaxBorrowAmount = staticData.ltv * tokenDepositAmount / 10_000;

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
            address(token), true, tokenMaxBorrowAmount - 1, address(this)
        );

        staticData =
            deployedContracts.cod3xLendDataProvider.getLpReserveStaticData(address(token), true);
        (, uint256 expectedBorrowRate) = deployedContracts.volatileStrategy.calculateInterestRates(
            address(token),
            address(commonContracts.aTokens[idx]),
            0,
            tokenMaxBorrowAmount - 1,
            tokenMaxBorrowAmount - 1,
            staticData.cod3xReserveFactor
        );
        /* Main user is using now his liquidity as a collateral - borrow shall succeed */
        deployedContracts.lendingPool.setUserUseReserveAsCollateral(address(token), true, true);

        /* Main user borrows maxPossible amount of usdc */
        vm.expectEmit(true, true, true, true);
        emit Borrow(
            address(token),
            address(this),
            address(this),
            tokenMaxBorrowAmount - 1,
            expectedBorrowRate
        );
        deployedContracts.lendingPool.borrow(
            address(token), true, tokenMaxBorrowAmount - 1, address(this)
        );

        /* Main user's balance should have: initial amount + borrowed amount */
        assertEq(usdcBalanceBeforeBorrow + tokenMaxBorrowAmount - 1, token.balanceOf(address(this)));
        assertEq(
            commonContracts.variableDebtTokens[idx].balanceOf(address(this)),
            tokenMaxBorrowAmount - 1
        );
    }

    function testNormalWithdrawDuringBorrow(uint256 offset) public {
        offset = 1;
        TokenTypes memory borrowToken = TokenTypes({
            token: erc20Tokens[offset],
            aToken: commonContracts.aTokens[offset],
            debtToken: commonContracts.variableDebtTokens[offset]
        });
        uint256 usdcAmount = 100000 * 10 ** erc20Tokens[USDC_OFFSET].decimals();
        uint256 borrowAmount = 10 ** borrowToken.token.decimals();

        address provider = makeAddr("provider");
        deal(address(borrowToken.token), provider, 2 * borrowAmount);

        fixture_deposit(
            erc20Tokens[USDC_OFFSET],
            commonContracts.aTokens[USDC_OFFSET],
            address(this),
            address(this),
            usdcAmount
        );
        fixture_borrow(borrowToken, provider, address(this), borrowAmount);

        vm.expectRevert(bytes(Errors.VL_TRANSFER_NOT_ALLOWED));
        deployedContracts.lendingPool.withdraw(
            address(erc20Tokens[USDC_OFFSET]), true, usdcAmount, address(this)
        );
    }
}
