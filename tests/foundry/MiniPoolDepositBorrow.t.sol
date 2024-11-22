// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolFixtures.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";

import "forge-std/StdUtils.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract MiniPoolDepositBorrowTest is MiniPoolFixtures {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;

    function setUp() public override {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configLpAddresses = ConfigAddresses(
            address(deployedContracts.cod3xLendDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(aToken),
            configLpAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        mockedVaults = fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));
        (miniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            address(0)
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] = address(aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        configLpAddresses.cod3xLendDataProvider =
            address(miniPoolContracts.miniPoolAddressesProvider);
        configLpAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configLpAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configLpAddresses, miniPoolContracts, 0);
        vm.label(miniPool, "MiniPool");
    }

    function testMiniPoolDeposits(uint256 amount, uint256 offset) public {
        /* Fuzz vector creation */
        address user = makeAddr("user");
        offset = bound(offset, 0, tokens.length - 1);
        TokenParams memory tokenParams = TokenParams(erc20Tokens[offset], aTokensWrapper[offset], 0);

        /* Assumptions */
        vm.assume(amount <= tokenParams.token.balanceOf(address(this)) / 2);
        vm.assume(amount > 10 ** tokenParams.token.decimals() / 100);

        /* Deposit tests */
        fixture_MiniPoolDeposit(amount, offset, user, tokenParams);
    }

    function testMiniPoolNormalBorrow(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * Test Scenario:
         * 1. User adds token as collateral into the miniPool
         * 2. User borrows token
         * Invariants:
         * 1. Balance of debtToken for user in IERC6909 standard increased
         * 2. Total supply of debtToken shall increase
         * 3. Health of user's position shall decrease
         * 4. User shall have borrowed assets
         *
         */

        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
        console.log("[collateral]Offset: ", collateralOffset);
        console.log("[borrow]Offset: ", borrowOffset);

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
            10 ** (borrowTokenParams.token.decimals() - 2),
            borrowTokenParams.token.balanceOf(address(this)) / 10
        );
        deal(
            address(collateralTokenParams.token),
            user,
            collateralTokenParams.token.balanceOf(address(this))
        );
        fixture_miniPoolBorrow(
            amount, collateralOffset, borrowOffset, collateralTokenParams, borrowTokenParams, user
        );
    }

    function testMiniPoolReserveFactors(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 validReserveFactor
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * Test Scenario:
         * 1. User adds token as collateral into the miniPool
         * 2. User borrows token
         * 3. Cod3x and pool owner treasuries are set
         * 4. Reserve factors are established to non-zero values
         * Invariants:
         * 1. Balance of debtToken for user in IERC6909 standard increased
         * 2. Total supply of debtToken shall increase
         * 3. Health of user's position shall decrease
         * 4. User shall have borrowed assets
         * 5. Cod3x treasury shall have some funds taken according to cod3x reserve factor
         * 6. Owner treasury shall have some funds taken according to owner reserve factor
         */

        /* Fuzz vectors */
        validReserveFactor = bound(validReserveFactor, 100, 1_500);
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
        console.log("[collateral]Offset: ", collateralOffset);
        console.log("[borrow]Offset: ", borrowOffset);

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
            10 ** (borrowTokenParams.token.decimals() - 2),
            borrowTokenParams.token.balanceOf(address(this)) / 10
        );
        deal(
            address(collateralTokenParams.token),
            user,
            collateralTokenParams.token.balanceOf(address(this))
        );

        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerTreasuryToMiniPool(
            makeAddr("ownerTreasury"), IMiniPool(miniPool)
        );
        vm.stopPrank();

        address treasury = address(deployedContracts.treasury);
        console.log("Treasury 1: ", treasury);
        console.log(
            "Treasury 2: ", miniPoolContracts.miniPoolAddressesProvider.getMiniPoolCod3xTreasury(0)
        );
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setCod3xTreasuryToMiniPool(
            treasury, IMiniPool(miniPool)
        );
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        console.log("\n>> First borrowing <<\n");
        fixture_miniPoolBorrow(
            amount, collateralOffset, borrowOffset, collateralTokenParams, borrowTokenParams, user
        );
        (,,,,, uint256 previousVariableBorrowIndex,) = deployedContracts
            .cod3xLendDataProvider
            .getMpReserveDynamicData(address(borrowTokenParams.token), 0);
        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setCod3xReserveFactor(
            address(borrowTokenParams.token), validReserveFactor, IMiniPool(miniPool)
        );
        vm.stopPrank();

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerReserveFactor(
            address(borrowTokenParams.token), validReserveFactor - 100, IMiniPool(miniPool)
        );

        skip(1 days);

        deal(
            address(collateralTokenParams.token),
            user,
            collateralTokenParams.token.balanceOf(address(this))
        );

        console.log("1.Treasury balance: ", aErc6909Token.balanceOf(treasury, 1128 + borrowOffset));
        uint256 scaledVariableDebt = aErc6909Token.scaledTotalSupply(2128 + borrowOffset);

        console.log("\n>> Second borrowing MiniPoolBorrow with reserve factor <<\n");
        fixture_miniPoolBorrow(
            amount, collateralOffset, borrowOffset, collateralTokenParams, borrowTokenParams, user
        );
        (,,,,, uint256 variableBorrowIndex,) = deployedContracts
            .cod3xLendDataProvider
            .getMpReserveDynamicData(address(borrowTokenParams.token), 0);
        console.log("2.Treasury balance: ", aErc6909Token.balanceOf(treasury, 1128 + borrowOffset));
        console.log("Balance of token must be greater than before borrow");
        console.log("variableBorrowIndex: ", variableBorrowIndex);
        console.log("previousVariableBorrowIndex: ", previousVariableBorrowIndex);
        console.log("scaledVariableDebt: ", scaledVariableDebt);

        assertApproxEqAbs(
            aErc6909Token.balanceOf(treasury, 1128 + borrowOffset),
            (
                scaledVariableDebt.rayMul(variableBorrowIndex)
                    - scaledVariableDebt.rayMul(previousVariableBorrowIndex)
            ).percentMul(validReserveFactor),
            1
        );

        assertApproxEqAbs(
            aErc6909Token.balanceOf(makeAddr("ownerTreasury"), 1128 + borrowOffset),
            (
                scaledVariableDebt.rayMul(variableBorrowIndex)
                    - scaledVariableDebt.rayMul(previousVariableBorrowIndex)
            ).percentMul(validReserveFactor - 100),
            1
        );
    }

    struct TestParams {
        uint256 depositAmount;
        uint256 borrowAmount;
        uint256 collateralOffset;
        uint256 borrowOffset;
        uint256 cod3xReserveFactor;
        uint256 ownerReserveFactor;
        address cod3xTreasury;
        address ownerTreasury;
    }

    function testMiniPoolReserveFactorsFixedNumber() public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * Test Scenario:
         * 1. User adds token as collateral into the miniPool
         * 2. User borrows token
         * Invariants:
         * 1. Balance of debtToken for user in IERC6909 standard increased
         * 2. Total supply of debtToken shall increase
         * 3. Health of user's position shall decrease
         * 4. User shall have borrowed assets
         * 5. Treasury shall have some funds taken according to reserve factor
         *
         */

        /* Fixed values */
        TestParams memory testParams;
        testParams.depositAmount = 100_000e6; // 100 000 USDC
        testParams.borrowAmount = 1e8; // 1 BTC
        testParams.collateralOffset = 0; // USDC
        testParams.borrowOffset = 1; // BTC
        testParams.cod3xReserveFactor = 500; // 5%
        testParams.ownerReserveFactor = 200; //2%
        testParams.cod3xTreasury = address(deployedContracts.treasury);
        testParams.ownerTreasury = makeAddr("ownerTreasury");

        console.log("[collateral]Offset: ", testParams.collateralOffset);
        console.log("[borrow]Offset: ", testParams.borrowOffset);

        /* Test vars */
        address user = makeAddr("user");
        TokenParams memory collateralTokenParams = TokenParams(
            erc20Tokens[testParams.collateralOffset],
            aTokensWrapper[testParams.collateralOffset],
            oracle.getAssetPrice(address(erc20Tokens[testParams.collateralOffset]))
        );
        TokenParams memory borrowTokenParams = TokenParams(
            erc20Tokens[testParams.borrowOffset],
            aTokensWrapper[testParams.borrowOffset],
            oracle.getAssetPrice(address(erc20Tokens[testParams.borrowOffset]))
        );

        deal(address(collateralTokenParams.token), user, 2 * testParams.depositAmount);

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setCod3xTreasuryToMiniPool(
            testParams.cod3xTreasury, IMiniPool(miniPool)
        );
        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerTreasuryToMiniPool(
            testParams.ownerTreasury, IMiniPool(miniPool)
        );
        vm.stopPrank();

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        console.log("\n>> First borrowing <<\n");
        fixture_depositTokensToMiniPool(
            2 * testParams.borrowAmount,
            1128 + testParams.borrowOffset,
            makeAddr("LP"),
            borrowTokenParams,
            aErc6909Token
        );
        fixture_depositTokensToMiniPool(
            testParams.depositAmount,
            1128 + testParams.collateralOffset,
            user,
            collateralTokenParams,
            aErc6909Token
        );
        vm.startPrank(user);
        IMiniPool(miniPool).borrow(address(borrowTokenParams.token), testParams.borrowAmount, user);
        vm.stopPrank();

        (,,,,, uint256 previousVariableBorrowIndex,) = deployedContracts
            .cod3xLendDataProvider
            .getMpReserveDynamicData(address(borrowTokenParams.token), 0);
        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setCod3xReserveFactor(
            address(borrowTokenParams.token), testParams.cod3xReserveFactor, IMiniPool(miniPool)
        );
        vm.stopPrank();

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerReserveFactor(
            address(borrowTokenParams.token), testParams.ownerReserveFactor, IMiniPool(miniPool)
        );

        skip(10 days);

        deal(
            address(collateralTokenParams.token),
            user,
            collateralTokenParams.token.balanceOf(address(this))
        );

        console.log(
            "1.Treasury balance: ",
            aErc6909Token.balanceOf(testParams.cod3xTreasury, 1128 + testParams.borrowOffset)
        );
        uint256 scaledVariableDebt = aErc6909Token.scaledTotalSupply(2128 + testParams.borrowOffset);
        uint256 scaledTotalSupply = aErc6909Token.scaledTotalSupply(1128 + testParams.borrowOffset);

        console.log("\n>> Second borrowing MiniPoolBorrow with reserve factor <<\n");
        fixture_depositTokensToMiniPool(
            2 * testParams.borrowAmount,
            1128 + testParams.borrowOffset,
            makeAddr("LP"),
            borrowTokenParams,
            aErc6909Token
        );
        fixture_depositTokensToMiniPool(
            testParams.depositAmount,
            1128 + testParams.collateralOffset,
            user,
            collateralTokenParams,
            aErc6909Token
        );
        vm.startPrank(user);
        IMiniPool(miniPool).borrow(address(borrowTokenParams.token), testParams.borrowAmount, user);
        vm.stopPrank();

        (,,,,, uint256 variableBorrowIndex,) = deployedContracts
            .cod3xLendDataProvider
            .getMpReserveDynamicData(address(borrowTokenParams.token), 0);
        console.log(
            "2.Treasury balance: ",
            aErc6909Token.balanceOf(testParams.cod3xTreasury, 1128 + testParams.borrowOffset)
        );
        console.log("Balance of token must be greater than before borrow");
        console.log(
            "Cod3x treasury balance: ",
            aErc6909Token.balanceOf(testParams.cod3xTreasury, 1128 + testParams.borrowOffset)
        );
        console.log(
            "OwnerTreasury balance: ",
            aErc6909Token.balanceOf(testParams.ownerTreasury, 1128 + testParams.borrowOffset)
        );

        uint256 cod3xTreasuryAmountToMint = (
            scaledVariableDebt.rayMul(variableBorrowIndex)
                - scaledVariableDebt.rayMul(previousVariableBorrowIndex)
        ).percentMul(testParams.cod3xReserveFactor);

        uint256 ownerTreasuryAmountToMint = (
            scaledVariableDebt.rayMul(variableBorrowIndex)
                - scaledVariableDebt.rayMul(previousVariableBorrowIndex)
        ).percentMul(testParams.ownerReserveFactor);

        assertApproxEqAbs(
            aErc6909Token.balanceOf(testParams.cod3xTreasury, 1128 + testParams.borrowOffset),
            cod3xTreasuryAmountToMint,
            1
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(testParams.ownerTreasury, 1128 + testParams.borrowOffset),
            ownerTreasuryAmountToMint,
            1
        );
        // @issue -> failing
        assertApproxEqAbs(
            scaledTotalSupply + (2 * testParams.borrowAmount).rayDiv(variableBorrowIndex)
                + cod3xTreasuryAmountToMint + ownerTreasuryAmountToMint,
            aErc6909Token.scaledTotalSupply(1128 + testParams.borrowOffset),
            1
        );
    }
}
