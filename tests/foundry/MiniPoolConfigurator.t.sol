// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolDepositBorrow.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";

contract MiniPoolConfiguratorTest is MiniPoolDepositBorrowTest {
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 constant MAX_VALID_RESERVE_FACTOR = 5000;
    uint256 constant MAX_VALID_DEPOSIT_CAP = type(uint72).max;
    uint256 constant MAX_VALID_VOLATILITY_TIER = 4;
    uint256 constant MAX_VALID_LTV = 65535;

    event BorrowingDisabledOnReserve(address indexed asset);

    event ReserveActivated(address indexed asset);
    event ReserveDeactivated(address indexed asset);
    event ReserveFrozen(address indexed asset);
    event ReserveUnfrozen(address indexed asset);
    event ReserveFactorChanged(address indexed asset, uint256 factor);
    event Cod3xReserveFactorChanged(address indexed asset, uint256 factor);
    event MinipoolOwnerReserveFactorChanged(address indexed asset, uint256 factor);

    event ReserveDepositCapChanged(address indexed asset, uint256 depositCap);
    event ReserveVolatilityTierChanged(address indexed asset, uint256 tier);

    event ReserveLowVolatilityLtvChanged(address indexed asset, uint256 ltv);
    event ReserveMediumVolatilityLtvChanged(address indexed asset, uint256 ltv);
    event ReserveHighVolatilityLtvChanged(address indexed asset, uint256 ltv);

    event EnableFlashloan(address indexed asset);
    event DisableFlashloan(address indexed asset);

    function testMiniPoolConfiguratorAccessControl(uint256 randomNumber) public {
        address tokenAddress = makeAddr("tokenAddress");
        address randomAddress = makeAddr("randomAddress");
        randomNumber = bound(randomNumber, 0, 100);

        address miniPoolImpl = address(new MiniPool());
        address aTokenImpl = address(new ATokenERC6909());
        uint256 miniPoolId = miniPoolContracts.miniPoolAddressesProvider.deployMiniPool(
            miniPoolImpl, aTokenImpl, poolOwner
        );
        address newMiniPool = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(miniPoolId);

        IMiniPoolConfigurator.InitReserveInput[] memory input;

        address prankAddress = miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(miniPoolId)
            != miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin()
            ? miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(miniPoolId)
            : randomAddress;

        vm.startPrank(prankAddress);
        /* only main pool */
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.batchInitReserve(input, IMiniPool(newMiniPool));

        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.setRewarderForReserve(
            tokenAddress, randomAddress, IMiniPool(newMiniPool)
        );
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.updateFlashloanPremiumTotal(
            uint128(randomNumber), IMiniPool(newMiniPool)
        );
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.setCod3xTreasury(randomAddress);
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.setFlowLimit(tokenAddress, newMiniPool, randomNumber);
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.setReserveInterestRateStrategyAddress(
            tokenAddress, randomAddress, IMiniPool(miniPool)
        );
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.setCod3xReserveFactor(
            tokenAddress, randomNumber, IMiniPool(miniPool)
        );
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.setDepositCap(
            tokenAddress, randomNumber, IMiniPool(miniPool)
        );

        /* only emergency admin */
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_EMERGENCY_ADMIN));
        miniPoolContracts.miniPoolConfigurator.setPoolPause(true, IMiniPool(newMiniPool));
        vm.stopPrank();

        prankAddress = miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(miniPoolId)
            != miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin()
            ? miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin()
            : randomAddress;
        vm.startPrank(prankAddress);
        /* only pool admin */
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.enableBorrowingOnReserve(
            tokenAddress, IMiniPool(newMiniPool)
        );
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.disableBorrowingOnReserve(
            tokenAddress, IMiniPool(newMiniPool)
        );
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.configureReserveAsCollateral(
            tokenAddress, randomNumber, randomNumber, randomNumber, IMiniPool(newMiniPool)
        );
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.activateReserve(tokenAddress, IMiniPool(newMiniPool));
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.deactivateReserve(
            tokenAddress, IMiniPool(newMiniPool)
        );
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.freezeReserve(tokenAddress, IMiniPool(newMiniPool));
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.unfreezeReserve(tokenAddress, IMiniPool(newMiniPool));

        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.enableFlashloan(tokenAddress, IMiniPool(newMiniPool));
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.disableFlashloan(
            tokenAddress, IMiniPool(newMiniPool)
        );
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.setPoolAdmin(randomAddress, IMiniPool(newMiniPool));
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerTreasuryToMiniPool(
            randomAddress, IMiniPool(newMiniPool)
        );
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerReserveFactor(
            tokenAddress, randomNumber, IMiniPool(newMiniPool)
        );
        vm.stopPrank();
    }

    function testMiniPoolDisableBorrowingOnReserve() public {
        address random = makeAddr("random");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
            vm.expectEmit(true, false, false, true);
            emit BorrowingDisabledOnReserve(address(erc20Tokens[idx]));
            miniPoolContracts.miniPoolConfigurator.disableBorrowingOnReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
            vm.stopPrank();

            vm.startPrank(random);
            vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
            miniPoolContracts.miniPoolConfigurator.disableBorrowingOnReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
            vm.stopPrank();
        }
    }

    function testMiniPoolActivateReserve() public {
        address random = makeAddr("random");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
            vm.expectEmit(true, false, false, true);
            emit ReserveActivated(address(erc20Tokens[idx]));
            miniPoolContracts.miniPoolConfigurator.activateReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
            vm.stopPrank();

            vm.startPrank(random);
            vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
            miniPoolContracts.miniPoolConfigurator.activateReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
            vm.stopPrank();
        }
    }

    function testMiniPoolDeactivateReserve() public {
        address random = makeAddr("random");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
            vm.expectEmit(true, false, false, true);
            emit ReserveDeactivated(address(erc20Tokens[idx]));
            miniPoolContracts.miniPoolConfigurator.deactivateReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
            vm.stopPrank();

            vm.startPrank(random);
            vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
            miniPoolContracts.miniPoolConfigurator.activateReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
            vm.stopPrank();
        }
    }

    function testMiniPoolFreezeReserve() public {
        address random = makeAddr("random");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
            vm.expectEmit(true, false, false, true);
            emit ReserveFrozen(address(erc20Tokens[idx]));
            miniPoolContracts.miniPoolConfigurator.freezeReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
            vm.stopPrank();

            vm.startPrank(random);
            vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
            miniPoolContracts.miniPoolConfigurator.activateReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
            vm.stopPrank();
        }
    }

    function testMiniPoolUnfreezeReserve() public {
        address random = makeAddr("random");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
            vm.expectEmit(true, false, false, true);
            emit ReserveUnfrozen(address(erc20Tokens[idx]));
            miniPoolContracts.miniPoolConfigurator.unfreezeReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
            vm.stopPrank();
            vm.startPrank(random);
            vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
            miniPoolContracts.miniPoolConfigurator.activateReserve(
                address(erc20Tokens[idx]), IMiniPool(miniPool)
            );
            vm.stopPrank();
        }
    }

    function testMiniPoolSetCod3xReserveFactor_Positive(uint256 validReserveFactor) public {
        validReserveFactor = bound(validReserveFactor, 0, MAX_VALID_RESERVE_FACTOR);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            DataTypes.ReserveConfigurationMap memory configuration =
                IMiniPool(miniPool).getConfiguration(address(erc20Tokens[idx]));
            console.log("config data: ", configuration.data);
            uint256 reserveFactor = (
                configuration.data & ~ReserveConfiguration.COD3X_RESERVE_FACTOR_MASK
            ) >> ReserveConfiguration.COD3X_RESERVE_FACTOR_START_BIT_POSITION;
            assertEq(reserveFactor, 0, "reserveFactor is not 0");
            vm.expectEmit(true, false, false, false);
            emit Cod3xReserveFactorChanged(address(erc20Tokens[idx]), validReserveFactor);
            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
            miniPoolContracts.miniPoolConfigurator.setCod3xReserveFactor(
                address(erc20Tokens[idx]), validReserveFactor, IMiniPool(miniPool)
            );
            vm.stopPrank();
            configuration = IMiniPool(miniPool).getConfiguration(address(erc20Tokens[idx]));
            reserveFactor = (configuration.data & ~ReserveConfiguration.COD3X_RESERVE_FACTOR_MASK)
                >> ReserveConfiguration.COD3X_RESERVE_FACTOR_START_BIT_POSITION;
            assertEq(reserveFactor, validReserveFactor, "reserveFactor is wrong");
        }
    }

    function testSetMiniPoolOwnerReserveFactor_Positive(uint256 validReserveFactor) public {
        validReserveFactor = bound(validReserveFactor, 0, MAX_VALID_RESERVE_FACTOR);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
            vm.expectEmit(true, false, false, false);
            emit MinipoolOwnerReserveFactorChanged(address(erc20Tokens[idx]), validReserveFactor);
            miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerReserveFactor(
                address(erc20Tokens[idx]), validReserveFactor, IMiniPool(miniPool)
            );
            vm.stopPrank();
        }
    }

    function testMiniPoolSetCod3xReserveFactor_Negative(uint256 invalidReserveFactor) public {
        invalidReserveFactor =
            bound(invalidReserveFactor, MAX_VALID_RESERVE_FACTOR + 1, type(uint256).max);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
            vm.expectRevert(bytes(Errors.RC_INVALID_RESERVE_FACTOR));
            miniPoolContracts.miniPoolConfigurator.setCod3xReserveFactor(
                address(erc20Tokens[idx]), invalidReserveFactor, IMiniPool(miniPool)
            );
            vm.stopPrank();
        }
    }

    function testMiniPoolSetUserUseReserveAsCollateral(
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
            commonContracts.aTokensWrapper[collateralOffset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[collateralOffset]))
        );
        TokenParams memory borrowTokenParams = TokenParams(
            erc20Tokens[borrowOffset],
            commonContracts.aTokensWrapper[borrowOffset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[borrowOffset]))
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
            IMiniPool(miniPool).borrow(address(borrowTokenParams.token), false, amount, user);

            vm.stopPrank();
        }
    }

    function testMiniPoolReserveFactorPositiveInNormalBorrow(
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
         */

        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
        validReserveFactor = 1e3; //bound(validReserveFactor, 0, 1e4); //@issue3: max allowed reserve factor is to PercentageMath.PERCENTAGE_FACTOR (1e4) not MAX_VALID_RESERVE_FACTOR. It is cause because of PercentageMath.PERCENTAGE_FACTOR - reserveFactor in getLiquidityRate

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        address treasury = makeAddr("treasury");
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setCod3xTreasury(treasury);

        /* Test vars */
        address user = makeAddr("user");
        TokenParams memory collateralTokenParams = TokenParams(
            erc20Tokens[collateralOffset],
            commonContracts.aTokensWrapper[collateralOffset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[collateralOffset]))
        );
        TokenParams memory borrowTokenParams = TokenParams(
            erc20Tokens[borrowOffset],
            commonContracts.aTokensWrapper[borrowOffset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[borrowOffset]))
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
        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setCod3xReserveFactor(
            address(borrowTokenParams.token), validReserveFactor, IMiniPool(miniPool)
        );
        vm.stopPrank();

        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerReserveFactor(
            address(borrowTokenParams.token), validReserveFactor, IMiniPool(miniPool)
        );
        vm.stopPrank();

        vm.startPrank(user);
        uint256 tokenBalanceBefore = aErc6909Token.balanceOf(address(treasury), 1128 + borrowOffset);
        console.log("BORROW 1 token: %s", address(borrowTokenParams.token));
        IMiniPool(miniPool).borrow(address(borrowTokenParams.token), false, amount / 3, user);
        skip(100 days);
        console.log("BORROW 2");
        IMiniPool(miniPool).borrow(address(borrowTokenParams.token), false, amount / 3, user);
        // console.log("Part of borrow aToken balance shall be transfered to the treasury");
        // assertGt(aErc6909Token.balanceOf(address(deployedContracts.treasury), 1000 + borrowOffset), atokenBalanceBefore);
        console.log("Part of borrow token balance shall be transfered to the treasury");

        assertGt(
            aErc6909Token.balanceOf(address(treasury), 1128 + borrowOffset), tokenBalanceBefore
        );

        vm.stopPrank();
    }

    function testMiniPoolSetDepositCap_Positive(uint256 validDepositCap) public {
        validDepositCap = bound(validDepositCap, 0, MAX_VALID_DEPOSIT_CAP - 1);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, false);
            emit ReserveDepositCapChanged(address(erc20Tokens[idx]), validDepositCap);
            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
            miniPoolContracts.miniPoolConfigurator.setDepositCap(
                address(erc20Tokens[idx]), validDepositCap, IMiniPool(miniPool)
            );
            vm.stopPrank();
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getCod3xReserveFactor(), validReserveFactor);
        }
    }

    function testMiniPoolSetDepositCap_Negative(uint256 invalidDepositCap) public {
        invalidDepositCap = bound(invalidDepositCap, MAX_VALID_DEPOSIT_CAP + 1, type(uint256).max);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
            vm.expectRevert(bytes(Errors.RC_INVALID_DEPOSIT_CAP));
            miniPoolContracts.miniPoolConfigurator.setDepositCap(
                address(erc20Tokens[idx]), invalidDepositCap, IMiniPool(miniPool)
            );
            vm.stopPrank();
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

    function testMiniPoolFlowLimiter() public {
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
        vars.grainUSDC = commonContracts.aTokensWrapper[0];
        vars.debtUSDC = commonContracts.variableDebtTokens[0];
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
        IMiniPool(vars.mp).deposit(address(vars.dai), false, vars.amount * 1e14, vars.user);
        vm.stopPrank();

        vars.flowLimiter = address(miniPoolContracts.flowLimiter);

        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider));
        miniPoolContracts.flowLimiter.setFlowLimit(address(vars.usdc), vars.mp, vars.amount * 100); // 50000 USDC

        vm.startPrank(vars.user);
        IMiniPool(vars.mp).borrow(address(vars.grainUSDC), false, vars.amount * 94, vars.user); // 47000 USDC
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
            IMiniPool(vars.mp).getReserveData(address(commonContracts.aTokensWrapper[0]));
        uint128 mpCurrentLiquidityRate = mpReserveData.currentLiquidityRate;
        uint128 mpCurrentVariableBorrowRate = mpReserveData.currentVariableBorrowRate;

        assertGe(mpCurrentVariableBorrowRate, delta);

        console.log("Balance of grain USDC", IERC20(vars.grainUSDC).balanceOf(vars.user));

        IERC20(vars.grainUSDC).approve(address(vars.mp), vars.amount * 94);
        console.log("Before repay: ");
        IMiniPool(vars.mp).repay(address(vars.grainUSDC), false, vars.amount * 94, vars.user); // 47000 USDC
        console.log("After repay: ");

        assertEq(vars.debtUSDC.balanceOf(vars.mp), 0);
    }

    function testMiniPoolConfigureWithoutLiquidationThreshold() public {
        address mp = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.configureReserveAsCollateral(
            USDC, 0, 0, 0, IMiniPool(mp)
        );
        miniPoolContracts.miniPoolConfigurator.configureReserveAsCollateral(
            WBTC, 0, 0, 0, IMiniPool(mp)
        );
        miniPoolContracts.miniPoolConfigurator.configureReserveAsCollateral(
            WETH, 0, 0, 0, IMiniPool(mp)
        );
        DataTypes.ReserveConfigurationMap memory currentConfig =
            IMiniPool(mp).getConfiguration(WETH);
        (uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus,,,,) =
            currentConfig.getParamsMemory();

        assertEq(ltv, 0, "Wrong Ltv");
        assertEq(liquidationThreshold, 0, "Wrong liquidation threashold");
        assertEq(liquidationBonus, 0, "Wrong liquidation bonus");

        vm.stopPrank();
    }

    /* Needed to test flashloan */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        return true;
    }

    function testMiniPoolEnableDisableFlashloans() public {
        address[] memory tokenAddresses = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);
        uint256[] memory balanceBefore = new uint256[](1);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
        address mp = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
        {
            uint256 amountToDeposit = IERC20(tokens[USDC_OFFSET]).balanceOf(address(this));
            erc20Tokens[USDC_OFFSET].approve(mp, 10 * amountToDeposit);
            IMiniPool(mp).deposit(
                address(erc20Tokens[USDC_OFFSET]), false, amountToDeposit, address(this)
            );
            reserveTypes[0] = true;
            tokenAddresses[0] = address(erc20Tokens[USDC_OFFSET]);
            amounts[0] = erc20Tokens[USDC_OFFSET].balanceOf(address(this)) / 2;
            modes[0] = 0;
            balanceBefore[0] = erc20Tokens[USDC_OFFSET].balanceOf(address(this));
        }

        IMiniPool.FlashLoanParams memory flashloanParams =
            IMiniPool.FlashLoanParams(address(this), tokenAddresses, address(this));

        bytes memory params = abi.encode(balanceBefore, address(this));

        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        vm.expectEmit(true, true, true, true);
        emit DisableFlashloan(USDC);
        miniPoolContracts.miniPoolConfigurator.disableFlashloan(USDC, IMiniPool(mp));

        vm.expectEmit(true, true, true, true);
        emit DisableFlashloan(WETH);
        miniPoolContracts.miniPoolConfigurator.disableFlashloan(WETH, IMiniPool(mp));
        vm.stopPrank();

        vm.expectRevert(bytes(Errors.VL_FLASHLOAN_DISABLED));
        IMiniPool(mp).flashLoan(flashloanParams, amounts, modes, params);

        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        vm.expectEmit(true, true, true, true);
        emit EnableFlashloan(USDC);
        miniPoolContracts.miniPoolConfigurator.enableFlashloan(USDC, IMiniPool(mp));

        vm.expectEmit(true, true, true, true);
        emit EnableFlashloan(WETH);
        miniPoolContracts.miniPoolConfigurator.enableFlashloan(WETH, IMiniPool(mp));
        vm.stopPrank();

        IMiniPool(mp).flashLoan(flashloanParams, amounts, modes, params);
    }

    function testSetReserveInterestRateStrategyAddress(uint256 offset, address stratAddress)
        public
    {
        // vm.assume(previousStratAddress != stratAddress);
        offset = bound(offset, 0, 3);
        address asset = tokens[offset];
        DataTypes.MiniPoolReserveData memory reserveData = IMiniPool(miniPool).getReserveData(asset);
        address previousStratAddress = reserveData.interestRateStrategyAddress;
        console.log("previousStratAddress: ", previousStratAddress);

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setReserveInterestRateStrategyAddress(
            asset, stratAddress, IMiniPool(miniPool)
        );

        reserveData = IMiniPool(miniPool).getReserveData(asset);
        console.log("currentStratAddress: ", reserveData.interestRateStrategyAddress);
        assertEq(reserveData.interestRateStrategyAddress, stratAddress);
    }

    function testUpdateFlashloanPremiumTotal(uint256 flashloanPremiumTotalToSet) public {
        flashloanPremiumTotalToSet = bound(flashloanPremiumTotalToSet, 0, 10_000);
        uint256 flashloanPremium = IMiniPool(miniPool).FLASHLOAN_PREMIUM_TOTAL();
        console.log("flashloanPremium: ", flashloanPremium);

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.updateFlashloanPremiumTotal(
            uint128(flashloanPremiumTotalToSet), IMiniPool(miniPool)
        );

        flashloanPremium = IMiniPool(miniPool).FLASHLOAN_PREMIUM_TOTAL();
        console.log("flashloanPremium: ", flashloanPremium);
        assertEq(flashloanPremium, flashloanPremiumTotalToSet);
    }

    function testSetMiniPoolAdmin(address newAdmin) public {
        vm.assume(
            newAdmin != address(0) && newAdmin != address(miniPoolContracts.miniPoolConfigurator)
        );
        address poolAdmin = miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0);
        console.log("poolAdmin: ", poolAdmin);

        vm.startPrank(newAdmin);
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        miniPoolContracts.miniPoolConfigurator.activateReserve(tokens[0], IMiniPool(miniPool));
        vm.stopPrank();

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.setPoolAdmin(newAdmin, IMiniPool(miniPool));

        poolAdmin = miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0);
        console.log("poolAdmin: ", poolAdmin);
        assertEq(poolAdmin, newAdmin);

        vm.startPrank(newAdmin);
        miniPoolContracts.miniPoolConfigurator.activateReserve(tokens[0], IMiniPool(miniPool));
    }
}
