// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./LendingPoolFixtures.t.sol";
import "../../contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "../../contracts/protocol/libraries/math/WadRayMath.sol";
import {MathUtils} from "../../contracts/protocol/libraries/math/MathUtils.sol";
import "../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract LendingPoolLendingPoolFixRateStrategyTest is LendingPoolFixtures {
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    ERC20[] erc20Tokens;

    function setUp() public override {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.asteraDataProvider),
            address(deployedContracts.fixStrategy),
            address(deployedContracts.fixStrategy),
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
        // aTokens = fixture_getATokens(tokens, deployedContracts.asteraDataProvider);
        // variableDebtTokens = fixture_getVarDebtTokens(tokens, deployedContracts.asteraDataProvider);
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function testLendingPoolFixRateStrategy() public {
        address user = makeAddr("user");
        address user2 = makeAddr("user2");
        uint256 amount = 33500e6; // 33.5k USDC
        fixture_deposit(erc20Tokens[0], commonContracts.aTokens[0], address(this), user, amount);
        fixture_deposit(erc20Tokens[1], commonContracts.aTokens[1], address(this), user2, 1e8);
        assertEq(erc20Tokens[0].balanceOf(address(commonContracts.aTokens[0])), amount);

        // borrow WBTC
        vm.prank(user);
        deployedContracts.lendingPool.borrow(
            address(erc20Tokens[1]),
            true,
            0.25e8,
            user // borrow 0.25 WBTC == 33500 / 2 USDC
        );

        console2.log("user2 aTokenUSDC balance: ", commonContracts.aTokens[0].balanceOf(user));
        console2.log(
            "user2 debtTokenWBTC balance: ", commonContracts.variableDebtTokens[1].balanceOf(user)
        );
        console2.log("user2 aTokenWBTC balance: ", commonContracts.aTokens[1].balanceOf(user2));

        skip(365 days);

        fixture_deposit(erc20Tokens[0], commonContracts.aTokens[0], address(this), user2, 10);

        console2.log("user2 aTokenUSDC balance: ", commonContracts.aTokens[0].balanceOf(user));
        console2.log(
            "user2 debtTokenWBTC balance: ", commonContracts.variableDebtTokens[1].balanceOf(user)
        );
        console2.log("user2 aTokenWBTC balance: ", commonContracts.aTokens[1].balanceOf(user2));

        // After 1 year at 10% APY, debt should be 10% higher than initial 0.25 WBTC
        assertApproxEqRel(
            commonContracts.variableDebtTokens[1].balanceOf(user),
            0.276e8, // 0.25e8 * 1.1 (composed interest)
            0.01e18 // Allow 1% deviation
        );

        assertApproxEqRel(
            commonContracts.aTokens[1].balanceOf(user2),
            1.0208e8, // borrow rate 10% distruted  0.076 - 20% reserve factor
            0.01e18 // Allow 1% deviation
        );
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
            deployedContracts.asteraDataProvider.getLpReserveStaticData(address(usdc), true);
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
            deployedContracts.asteraDataProvider.getLpReserveStaticData(address(usdc), true);
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
}
