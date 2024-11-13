// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolDepositBorrow.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

contract MiniPoolConfiguratorTest is MiniPoolDepositBorrowTest {
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 constant MAX_VALID_RESERVE_FACTOR = 65535;
    uint256 constant MAX_VALID_DEPOSIT_CAP = 256;
    uint256 constant MAX_VALID_VOLATILITY_TIER = 4;
    uint256 constant MAX_VALID_LTV = 65535;

    event BorrowingDisabledOnReserve(address indexed asset);

    event ReserveActivated(address indexed asset);
    event ReserveDeactivated(address indexed asset);
    event ReserveFrozen(address indexed asset);
    event ReserveUnfrozen(address indexed asset);
    event ReserveFactorChanged(address indexed asset, uint256 factor);

    event ReserveDepositCapChanged(address indexed asset, uint256 depositCap);
    event ReserveVolatilityTierChanged(address indexed asset, uint256 tier);

    event ReserveLowVolatilityLtvChanged(address indexed asset, uint256 ltv);
    event ReserveMediumVolatilityLtvChanged(address indexed asset, uint256 ltv);
    event ReserveHighVolatilityLtvChanged(address indexed asset, uint256 ltv);

    function testMiniPoolConfiguratorAccessControl(uint256 randomNumber) public {
        address tokenAddress = makeAddr("tokenAddress");
        address randomAddress = makeAddr("randomAddress");
        randomNumber = bound(randomNumber, 0, 100);

        vm.expectRevert(bytes("76"));
        miniPoolContracts.miniPoolConfigurator.setPoolPause(true, IMiniPool(randomAddress));

        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.activateReserve(
            tokenAddress, IMiniPool(randomAddress)
        );
        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.deactivateReserve(
            tokenAddress, IMiniPool(randomAddress)
        );
        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.freezeReserve(tokenAddress, IMiniPool(randomAddress));
        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.unfreezeReserve(
            tokenAddress, IMiniPool(randomAddress)
        );

        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.enableFlashloan(
            tokenAddress, IMiniPool(randomAddress)
        );
        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.disableFlashloan(
            tokenAddress, IMiniPool(randomAddress)
        );

        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.setReserveFactor(
            tokenAddress, randomNumber, IMiniPool(randomAddress)
        );
        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.setDepositCap(
            tokenAddress, randomNumber, IMiniPool(randomAddress)
        );

        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.setReserveInterestRateStrategyAddress(
            tokenAddress, randomAddress, IMiniPool(randomAddress)
        );

        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.setRewarderForReserve(
            tokenAddress, randomAddress, IMiniPool(randomAddress)
        );
        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.updateFlashloanPremiumTotal(
            uint128(randomNumber), IMiniPool(randomAddress)
        );
        vm.expectRevert(bytes("33"));
        miniPoolContracts.miniPoolConfigurator.setRewarderForReserve(
            tokenAddress, randomAddress, IMiniPool(randomAddress)
        );
    }

    function testDisableBorrowingOnReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit BorrowingDisabledOnReserve(address(erc20Tokens[idx]));
            vm.prank(admin);
            miniPoolContracts.miniPoolConfigurator.disableBorrowingOnReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
        }
    }

    function testActivateReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveActivated(address(erc20Tokens[idx]));
            vm.prank(admin);
            miniPoolContracts.miniPoolConfigurator.activateReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
        }
    }

    function testDeactivateReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveDeactivated(address(erc20Tokens[idx]));
            vm.prank(admin);
            miniPoolContracts.miniPoolConfigurator.deactivateReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
        }
    }

    function testFreezeReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveFrozen(address(erc20Tokens[idx]));
            vm.prank(admin);
            miniPoolContracts.miniPoolConfigurator.freezeReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
        }
    }

    function testUnfreezeReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveUnfrozen(address(erc20Tokens[idx]));
            vm.prank(admin);
            miniPoolContracts.miniPoolConfigurator.unfreezeReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
        }
    }

    function testSetReserveFactor_Positive(uint256 validReserveFactor) public {
        validReserveFactor = bound(validReserveFactor, 0, MAX_VALID_RESERVE_FACTOR);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, false);
            emit ReserveFactorChanged(address(erc20Tokens[idx]), validReserveFactor);
            vm.prank(admin);
            miniPoolContracts.miniPoolConfigurator.setReserveFactor(
                address(erc20Tokens[idx]), validReserveFactor, IMiniPool(miniPool)
            );
        }
    }

    function testSetReserveFactor_Negative(uint256 invalidReserveFactor) public {
        invalidReserveFactor =
            bound(invalidReserveFactor, MAX_VALID_RESERVE_FACTOR + 1, type(uint256).max);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectRevert(bytes(Errors.RC_INVALID_RESERVE_FACTOR));
            vm.prank(admin);
            miniPoolContracts.miniPoolConfigurator.setReserveFactor(
                address(erc20Tokens[idx]), invalidReserveFactor, IMiniPool(miniPool)
            );
        }
    }

    function testSetUserUseReserveAsCollateral(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset
    ) public {
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        TokenParams memory collateralTokenParams = TokenParams(
            erc20Tokens[collateralOffset],
            aTokensWrapper[collateralOffset],
            oracle.getAssetPrice(address(erc20Tokens[collateralOffset]))
        );
        TokenParams memory borrowTokenParams = TokenParams(
            erc20Tokens[borrowOffset],
            aTokensWrapper[borrowOffset],
            oracle.getAssetPrice(address(erc20Tokens[borrowOffset]))
        );
        address user = makeAddr("user");
        vm.label(address(aErc6909Token), "aErc6909Token");
        vm.label(address(collateralTokenParams.aToken), "aToken");
        vm.label(address(collateralTokenParams.token), "token");

        amount = bound(
            amount,
            10 ** (borrowTokenParams.token.decimals() - 2),
            borrowTokenParams.token.balanceOf(address(this)) / 10
        );

        /* Test depositing */
        uint256 minNrOfTokens;
        {
            StaticData memory staticData = deployedContracts
                .cod3xLendDataProvider
                .getLpReserveStaticData(address(collateralTokenParams.token), true);
            console.log("collateralTokenLtv: ", staticData.ltv);
            uint256 borrowTokenInUsd = (amount * borrowTokenParams.price * 10_000)
                / ((10 ** PRICE_FEED_DECIMALS) * staticData.ltv);
            uint256 borrowTokenRay = borrowTokenInUsd.rayDiv(collateralTokenParams.price);
            uint256 borrowTokenInCollateralToken = fixture_preciseConvertWithDecimals(
                borrowTokenRay,
                borrowTokenParams.token.decimals(),
                collateralTokenParams.token.decimals()
            );
            minNrOfTokens = (
                borrowTokenInCollateralToken
                    > collateralTokenParams.token.balanceOf(address(this)) / 4
            )
                ? (collateralTokenParams.token.balanceOf(address(this)) / 4)
                : borrowTokenInCollateralToken;
        }
        {
            /* Users deposit */
            console.log("User deposit");
            fixture_MiniPoolDeposit(minNrOfTokens, collateralOffset, user, collateralTokenParams);
            console.log("Other user deposit");
            address otherUser = makeAddr("otherUser");
            fixture_MiniPoolDeposit(amount, borrowOffset, otherUser, borrowTokenParams);

            vm.startPrank(user);
            console.log("Set collateral for token");
            console.log("Amount: %s and minNrOf: %s", amount, minNrOfTokens);
            vm.expectEmit();
            emit ReserveUsedAsCollateralDisabled(address(collateralTokenParams.token), user);
            IMiniPool(miniPool).setUserUseReserveAsCollateral(
                address(collateralTokenParams.token), false
            );
            vm.expectEmit();
            emit ReserveUsedAsCollateralDisabled(address(collateralTokenParams.aToken), user);
            IMiniPool(miniPool).setUserUseReserveAsCollateral(
                address(collateralTokenParams.aToken), false
            );

            vm.expectRevert(bytes(Errors.VL_COLLATERAL_BALANCE_IS_0));
            IMiniPool(miniPool).borrow(address(borrowTokenParams.token), amount, user);

            vm.stopPrank();
        }
    }

    function testReserveFactorPositiveInNormalBorrow(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 validReserveFactor
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * Test Scenario:
         * 1. Reserve factor is set
         * 2. User adds token as collateral into the miniPool
         * 3. Reserve factor is configured by admin to mint to treasury
         * 4. User borrows token
         * Invariants:
         * 1. Some tokens are minted to the treasury
         *
         */

        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
        validReserveFactor = 1e3; //bound(validReserveFactor, 0, 1e4); //@issue3: max allowed reserve factor is to PercentageMath.PERCENTAGE_FACTOR (1e4) not MAX_VALID_RESERVE_FACTOR. It is cause because of PercentageMath.PERCENTAGE_FACTOR - reserveFactor in getLiquidityRate

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        address treasury = makeAddr("treasury");
        miniPoolContracts.miniPoolAddressesProvider.setMiniPoolToTreasury(0, treasury);

        /* Test vars */
        address user = makeAddr("user");
        TokenParams memory collateralTokenParams = TokenParams(
            erc20Tokens[collateralOffset],
            aTokensWrapper[collateralOffset],
            oracle.getAssetPrice(address(erc20Tokens[collateralOffset]))
        );
        TokenParams memory borrowTokenParams = TokenParams(
            erc20Tokens[borrowOffset],
            aTokensWrapper[borrowOffset],
            oracle.getAssetPrice(address(erc20Tokens[borrowOffset]))
        );
        /* Assumptions */
        amount = bound(
            amount,
            10 ** (borrowTokenParams.token.decimals() - 1),
            borrowTokenParams.token.balanceOf(address(this)) / 10
        ); // 0.1 - available balance / 10
        console.log("Amount bounded: ", amount);

        uint256 minNrOfTokens;
        {
            StaticData memory staticData = deployedContracts
                .cod3xLendDataProvider
                .getLpReserveStaticData(address(collateralTokenParams.token), true);
            uint256 borrowTokenInUsd = (amount * borrowTokenParams.price * 10_000)
                / ((10 ** PRICE_FEED_DECIMALS) * staticData.ltv);
            console.log("borrow in USD: ", borrowTokenInUsd);
            uint256 borrowTokenRay = borrowTokenInUsd.rayDiv(collateralTokenParams.price);
            uint256 borrowTokenInCollateralToken = fixture_preciseConvertWithDecimals(
                borrowTokenRay,
                borrowTokenParams.token.decimals(),
                collateralTokenParams.token.decimals()
            );
            console.log(
                "collateral in USD: ",
                (borrowTokenInCollateralToken * collateralTokenParams.price * 10_000)
                    / (10 ** PRICE_FEED_DECIMALS)
            );
            minNrOfTokens = (
                borrowTokenInCollateralToken
                    > collateralTokenParams.token.balanceOf(address(this)) / 4
            )
                ? (collateralTokenParams.token.balanceOf(address(this)) / 4)
                : borrowTokenInCollateralToken;
        }

        {
            /* Sb deposits tokens that will be borrowed */
            address liquidityProvider = makeAddr("liquidityProvider");
            console.log(
                "Deposit borrowTokens: %s with balance: %s",
                2 * amount,
                borrowTokenParams.token.balanceOf(address(this))
            );
            fixture_MiniPoolDeposit(amount, borrowOffset, liquidityProvider, borrowTokenParams);
        }

        /* User deposits collateral */
        fixture_MiniPoolDeposit(minNrOfTokens, collateralOffset, user, collateralTokenParams);

        /* Setting reserve factor that allow minting to the treasury */
        vm.prank(admin);
        miniPoolContracts.miniPoolConfigurator.setReserveFactor(
            address(borrowTokenParams.token), validReserveFactor, IMiniPool(miniPool)
        );

        vm.startPrank(user);
        uint256 tokenBalanceBefore = aErc6909Token.balanceOf(address(treasury), 1128 + borrowOffset);
        console.log("BORROW 1 token: %s", address(borrowTokenParams.token));
        IMiniPool(miniPool).borrow(address(borrowTokenParams.token), amount / 3, user);
        skip(100 days);
        console.log("BORROW 2");
        IMiniPool(miniPool).borrow(address(borrowTokenParams.token), amount / 3, user);
        // console.log("Part of borrow aToken balance shall be transfered to the treasury");
        // assertGt(aErc6909Token.balanceOf(address(deployedContracts.treasury), 1000 + borrowOffset), atokenBalanceBefore);
        console.log("Part of borrow token balance shall be transfered to the treasury");

        assertGt(
            aErc6909Token.balanceOf(address(treasury), 1128 + borrowOffset), tokenBalanceBefore
        );

        vm.stopPrank();
    }

    function testSetDepositCap_Positive(uint256 validDepositCap) public {
        validDepositCap = bound(validDepositCap, 0, MAX_VALID_DEPOSIT_CAP - 1);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, false);
            emit ReserveDepositCapChanged(address(erc20Tokens[idx]), validDepositCap);
            vm.prank(admin);
            miniPoolContracts.miniPoolConfigurator.setDepositCap(
                address(erc20Tokens[idx]), validDepositCap, IMiniPool(miniPool)
            );
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testSetDepositCap_Negative(uint256 invalidDepositCap) public {
        invalidDepositCap = bound(invalidDepositCap, MAX_VALID_DEPOSIT_CAP, type(uint256).max);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectRevert(bytes(Errors.RC_INVALID_DEPOSIT_CAP));
            vm.prank(admin);
            miniPoolContracts.miniPoolConfigurator.setDepositCap(
                address(erc20Tokens[idx]), invalidDepositCap, IMiniPool(miniPool)
            );
        }
    }

    struct FlowLimiterTestLocalVars {
        IERC20 usdc;
        IERC20 grainUSDC;
        IERC20 debtUSDC;
        IERC20 dai;
        uint256 mpId;
        address mp;
        IAERC6909 aErc6909Token;
        address user;
        address whaleUser;
        address usdcWhale;
        address daiWhale;
        uint256 amount;
        address flowLimiter;
    }

    function testFlowLimiter() public {
        FlowLimiterTestLocalVars memory vars;
        vars.user = makeAddr("user");
        vars.mpId = 0;
        vars.mp = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(vars.mpId);
        vm.label(vars.mp, "MiniPool");
        vars.aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(vars.mp));
        vm.label(address(vars.aErc6909Token), "aErc6909Token");

        vars.whaleUser = makeAddr("whaleUser");

        vars.usdcWhale = 0xacD03D601e5bB1B275Bb94076fF46ED9D753435A;
        vm.label(vars.usdcWhale, "Whale");
        vars.daiWhale = 0xD28843E10C3795E51A6e574378f8698aFe803029;
        vm.label(vars.daiWhale, "DaiWhale");

        vars.usdc = erc20Tokens[0];
        vars.grainUSDC = aTokensWrapper[0];
        vars.debtUSDC = variableDebtTokens[0];
        vars.amount = 5e8; //bound(amount, 1E6, 1E13); /* $500 */ // consider fuzzing here
        uint256 usdcAID = 1000;
        // uint256 usdcDID = 2000;
        // uint256 daiAID = 1128;
        // uint256 daiDID = 2128;
        vars.dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);

        vm.prank(vars.usdcWhale);
        vars.usdc.transfer(vars.whaleUser, vars.amount * 1000);

        vm.prank(vars.daiWhale);
        vars.dai.transfer(vars.user, vars.amount * 1e14); // 50000 DAI

        vm.startPrank(vars.whaleUser);
        vars.usdc.approve(address(deployedContracts.lendingPool), vars.amount * 1000); //500000 USDC
        deployedContracts.lendingPool.deposit(
            address(vars.usdc), true, vars.amount * 1000, vars.whaleUser
        );
        vm.stopPrank();

        vm.startPrank(vars.user);
        vars.dai.approve(address(vars.mp), vars.amount * 1e14);
        console.log("User balance: ", vars.dai.balanceOf(vars.user) / (10 ** 18));
        console.log("User depositAmount: ", vars.amount * 1e14 / (10 ** 18));
        IMiniPool(vars.mp).deposit(address(vars.dai), vars.amount * 1e14, vars.user);
        vm.stopPrank();

        vars.flowLimiter = address(miniPoolContracts.flowLimiter);

        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider));
        miniPoolContracts.flowLimiter.setFlowLimit(address(vars.usdc), vars.mp, vars.amount * 100); // 50000 USDC

        vm.startPrank(vars.user);
        IMiniPool(vars.mp).borrow(address(vars.grainUSDC), vars.amount * 94, vars.user); // 47000 USDC
        assertEq(vars.debtUSDC.balanceOf(vars.mp), vars.amount * 94);
        assertEq(
            IVariableDebtToken(address(vars.debtUSDC)).scaledBalanceOf(vars.mp), vars.amount * 94
        );

        DataTypes.ReserveData memory reserveData =
            deployedContracts.lendingPool.getReserveData(address(vars.usdc), true);
        uint128 currentLiquidityRate = reserveData.currentLiquidityRate;
        uint128 currentVariableBorrowRate = reserveData.currentVariableBorrowRate;
        uint128 delta = currentVariableBorrowRate - currentLiquidityRate;
        console.log("CurrentLiquidityRate: ", currentLiquidityRate);
        console.log("CurrentVariableBorrowRate: ", currentVariableBorrowRate);
        console.log("Delta: ", delta);
        console.log("1 %s vs 2 %s", address(vars.debtUSDC), reserveData.variableDebtTokenAddress);
        console.log(
            "Balance of variable debt: ",
            IERC20(reserveData.variableDebtTokenAddress).balanceOf(vars.user)
        );
        DataTypes.MiniPoolReserveData memory mpReserveData =
            IMiniPool(vars.mp).getReserveData(address(aTokensWrapper[0]));
        uint128 mpCurrentLiquidityRate = mpReserveData.currentLiquidityRate;
        uint128 mpCurrentVariableBorrowRate = mpReserveData.currentVariableBorrowRate;

        assertGe(mpCurrentVariableBorrowRate, delta);

        console.log("Balance of grain USDC", IERC20(vars.grainUSDC).balanceOf(vars.user));

        IERC20(vars.grainUSDC).approve(address(vars.mp), vars.amount * 94);
        console.log("Before repay: ");
        IMiniPool(vars.mp).repay(address(vars.grainUSDC), vars.amount * 94, vars.user); // 47000 USDC
        console.log("After repay: ");

        assertEq(vars.debtUSDC.balanceOf(vars.mp), 0);
    }
}
