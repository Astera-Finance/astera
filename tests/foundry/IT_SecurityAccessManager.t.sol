// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SecurityAccessManager} from "contracts/protocol/core/SecurityAccessManager.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";
import {MintableERC20} from "contracts/mocks/tokens/MintableERC20.sol";
import {IERC20Detailed} from "contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import "./LendingPoolFixtures.t.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title SecurityAccessManagerTest
 * @notice Comprehensive test suite for SecurityAccessManager.sol
 * @dev Tests cover tier assignment, cooldowns, deposits, and access control
 */
contract SecurityAccessManagerTest is LendingPoolFixtures {
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    // ============ State Variables ============
    ERC20[] erc20Tokens;
    SecurityAccessManager public securityAccessManager;

    // Test addresses
    address public pointsManager = address(0x2);
    address public user1 = address(0x100);
    address public user2 = address(0x200);
    address public unauthorizedUser = address(0x999);

    // Test assets
    address[] assets;

    // Tier configuration
    uint32[] public cooldownTimes;
    uint208[] public maxDeposits;
    uint16[] public trustThresholds;

    // ============ Setup ============

    function setUp() public override {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.asteraDataProvider),
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
        // aTokens = fixture_getATokens(tokens, deployedContracts.asteraDataProvider);
        // variableDebtTokens = fixture_getVarDebtTokens(tokens, deployedContracts.asteraDataProvider);
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));

        address[] memory aTokensAddr = new address[](commonContracts.aTokens.length);
        for (uint256 i = 0; i < commonContracts.aTokens.length; i++) {
            aTokensAddr[i] = address(commonContracts.aTokens[i]);
        }

        address[] memory managers = new address[](1);
        managers[0] = pointsManager;
        securityAccessManager = new SecurityAccessManager(admin, managers, aTokensAddr);
        deployedContracts.lendingPoolAddressesProvider
                .setSecurityAccessManager(address(securityAccessManager));

        // Configure default tiers
        cooldownTimes = new uint32[](3);
        maxDeposits = new uint208[](3);
        trustThresholds = new uint16[](3);

        cooldownTimes[0] = 2 days;
        cooldownTimes[1] = 1 days;
        cooldownTimes[2] = 12 hours;

        maxDeposits[0] = 1000e8; // $1k
        maxDeposits[1] = 5000e8; // $5k
        maxDeposits[2] = 10000e8; // $10k

        trustThresholds[0] = 0;
        trustThresholds[1] = 100;
        trustThresholds[2] = 500;

        vm.startPrank(admin);
        for (uint256 i = 0; i < aTokensAddr.length; i++) {
            maxDeposits[0] = uint208(
                (erc20Tokens[i].balanceOf(address(this)) * 10 ** 8)
                    / (10 ** erc20Tokens[i].decimals() * 4)
            );
            maxDeposits[1] = uint208(
                (erc20Tokens[i].balanceOf(address(this)) * 10 ** 8)
                    / (10 ** erc20Tokens[i].decimals() * 2)
            );
            maxDeposits[2] = uint208(
                (erc20Tokens[i].balanceOf(address(this)) * 10 ** 8) / 10
                    ** erc20Tokens[i].decimals()
            );
            securityAccessManager.setLevelParams(
                cooldownTimes, maxDeposits, trustThresholds, aTokensAddr[i]
            );
        }
        vm.stopPrank();
    }

    function test_depositAndBorrowWithCooldown(
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 cooldownTime
    ) public {
        collateralOffset = bound(collateralOffset, 0, erc20Tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, erc20Tokens.length - 1);
        cooldownTime = bound(cooldownTime, cooldownTimes[0], 2 * cooldownTimes[0]);
        TokenTypes memory borrowToken = TokenTypes({
            token: erc20Tokens[borrowOffset],
            aToken: commonContracts.aTokens[borrowOffset],
            debtToken: commonContracts.variableDebtTokens[borrowOffset]
        });
        uint256 amount = securityAccessManager.getMaxDepositInOriginDecimals(
            0, address(commonContracts.aTokens[collateralOffset])
        );
        console2.log("Amount: ", amount);
        fixture_deposit(
            erc20Tokens[collateralOffset],
            commonContracts.aTokens[collateralOffset],
            address(this),
            address(this),
            amount
        );
        uint256 maxBorrowTokenToBorrowInCollateralUnit =
            fixture_getMaxValueToBorrow(erc20Tokens[collateralOffset], borrowToken.token, amount);
        deal(address(borrowToken.token), user1, 2 * maxBorrowTokenToBorrowInCollateralUnit);

        vm.prank(pointsManager);
        securityAccessManager.increaseTrustPoints(user1, trustThresholds[2] + 1);

        vm.warp(block.timestamp + cooldownTime);
        fixture_deposit(
            borrowToken.token,
            borrowToken.aToken,
            user1,
            user1,
            maxBorrowTokenToBorrowInCollateralUnit * 15 / 10
        );
        deployedContracts.lendingPool
            .borrow(
                address(borrowToken.token),
                true,
                maxBorrowTokenToBorrowInCollateralUnit * 99 / 100,
                address(this)
            );
    }

    function test_depositAndBorrowWithoutProperCooldown(
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 cooldownTime
    ) public {
        collateralOffset = bound(collateralOffset, 0, erc20Tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, erc20Tokens.length - 1);
        cooldownTime = bound(cooldownTime, 0, cooldownTimes[0]);
        TokenTypes memory borrowToken = TokenTypes({
            token: erc20Tokens[borrowOffset],
            aToken: commonContracts.aTokens[borrowOffset],
            debtToken: commonContracts.variableDebtTokens[borrowOffset]
        });
        uint256 amount = securityAccessManager.getMaxDepositInOriginDecimals(
            0, address(commonContracts.aTokens[collateralOffset])
        );
        console2.log("Amount: ", amount);
        fixture_deposit(
            erc20Tokens[collateralOffset],
            commonContracts.aTokens[collateralOffset],
            address(this),
            address(this),
            amount
        );
        uint256 maxBorrowTokenToBorrowInCollateralUnit =
            fixture_getMaxValueToBorrow(erc20Tokens[collateralOffset], borrowToken.token, amount);
        deal(address(borrowToken.token), user1, 2 * maxBorrowTokenToBorrowInCollateralUnit);

        vm.prank(pointsManager);
        securityAccessManager.increaseTrustPoints(user1, trustThresholds[2] + 1);

        vm.warp(block.timestamp + cooldownTime);
        fixture_deposit(
            borrowToken.token,
            borrowToken.aToken,
            user1,
            user1,
            maxBorrowTokenToBorrowInCollateralUnit * 15 / 10
        );
        deployedContracts.lendingPool
            .borrow(
                address(borrowToken.token),
                true,
                maxBorrowTokenToBorrowInCollateralUnit * 99 / 100,
                address(this)
            );
    }

    struct UserDataAccountData {
        uint256 totalCollateralETH;
        uint256 totalDebtETH;
        uint256 availableBorrowsETH;
        uint256 ltv;
        uint256 healthFactor;
        uint256 liquidFunds;
    }

    function userAccountDataChanges(
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 cooldownTime,
        uint256 amount
    ) public {
        TokenTypes memory borrowToken = TokenTypes({
            token: erc20Tokens[borrowOffset],
            aToken: commonContracts.aTokens[borrowOffset],
            debtToken: commonContracts.variableDebtTokens[borrowOffset]
        });

        console2.log("Amount: ", amount);
        fixture_deposit(
            erc20Tokens[collateralOffset],
            commonContracts.aTokens[collateralOffset],
            address(this),
            address(this),
            amount
        );
        UserDataAccountData memory userDataAccountData;
        (
            userDataAccountData.totalCollateralETH,,
            userDataAccountData.availableBorrowsETH,,
            userDataAccountData.ltv,
            userDataAccountData.healthFactor,
            userDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(address(this));
        assertEq(
            userDataAccountData.healthFactor, type(uint256).max, "Health factors should be max"
        );
        assertEq(userDataAccountData.liquidFunds, 0, "Liquid funds should be zero");
        assertGt(
            userDataAccountData.totalCollateralETH,
            0,
            "Total collateral should be greater than zero"
        );
        assertEq(userDataAccountData.availableBorrowsETH, 0, "Available borrows should be zero");

        vm.warp(block.timestamp + cooldownTime);

        (
            userDataAccountData.totalCollateralETH,,
            userDataAccountData.availableBorrowsETH,,
            userDataAccountData.ltv,
            userDataAccountData.healthFactor,
            userDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(address(this));
        assertEq(
            userDataAccountData.healthFactor, type(uint256).max, "Health factors should be max"
        );
        assertEq(
            userDataAccountData.liquidFunds,
            userDataAccountData.totalCollateralETH,
            "Liquid funds should be the same as total collateral"
        );
        assertGt(
            userDataAccountData.totalCollateralETH,
            0,
            "Total collateral should be greater than zero"
        );

        uint256 maxBorrowTokenToBorrowInCollateralUnit =
            fixture_getMaxValueToBorrow(erc20Tokens[collateralOffset], borrowToken.token, amount);
        assertGt(
            userDataAccountData.availableBorrowsETH, 0, "Available borrows should be greater than 0"
        );
        deal(address(borrowToken.token), user1, 2 * maxBorrowTokenToBorrowInCollateralUnit);

        vm.prank(pointsManager);
        securityAccessManager.increaseTrustPoints(user1, trustThresholds[2] + 1);

        fixture_deposit(
            borrowToken.token,
            borrowToken.aToken,
            user1,
            user1,
            maxBorrowTokenToBorrowInCollateralUnit * 15 / 10
        );
        deployedContracts.lendingPool
            .borrow(
                address(borrowToken.token),
                true,
                maxBorrowTokenToBorrowInCollateralUnit * 99 / 100,
                address(this)
            );

        (
            userDataAccountData.totalCollateralETH,,
            userDataAccountData.availableBorrowsETH,,
            userDataAccountData.ltv,
            userDataAccountData.healthFactor,
            userDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(address(this));
        console2.log("HealthFactor: ", userDataAccountData.healthFactor);
        console2.log("availableBorrowsETH: ", userDataAccountData.availableBorrowsETH);

        console2.log("ltv: ", userDataAccountData.ltv);
        console2.log("liquidFunds: ", userDataAccountData.liquidFunds);
        assertLt(
            userDataAccountData.healthFactor,
            type(uint256).max,
            "Health factors should be less than max"
        );
        assertEq(
            userDataAccountData.liquidFunds,
            userDataAccountData.totalCollateralETH,
            "Liquid funds should be the same as total collateral"
        );
        assertGt(
            userDataAccountData.totalCollateralETH,
            0,
            "Total collateral should be greater than zero"
        );
    }

    function test_userAccountDataChanges(
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 cooldownTime
    ) public {
        collateralOffset = bound(collateralOffset, 0, erc20Tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, erc20Tokens.length - 1);
        cooldownTime = bound(cooldownTime, cooldownTimes[0], 2 * cooldownTimes[0]);
        uint256 amount = securityAccessManager.getMaxDepositInOriginDecimals(
            0, address(commonContracts.aTokens[collateralOffset])
        );
        userAccountDataChanges(collateralOffset, borrowOffset, cooldownTime, amount);
    }

    function test_withdrawalDecreaseLiquidFundsAndCanBeDoneJustAfterDeployment(
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 cooldownTime
    ) public {
        collateralOffset = bound(collateralOffset, 0, erc20Tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, erc20Tokens.length - 1);
        cooldownTime = bound(cooldownTime, cooldownTimes[0], 2 * cooldownTimes[0]);
        TokenTypes memory borrowToken = TokenTypes({
            token: erc20Tokens[borrowOffset],
            aToken: commonContracts.aTokens[borrowOffset],
            debtToken: commonContracts.variableDebtTokens[borrowOffset]
        });
        uint256 amount = securityAccessManager.getMaxDepositInOriginDecimals(
            0, address(commonContracts.aTokens[collateralOffset])
        );
        console2.log("Amount: ", amount);
        fixture_deposit(
            erc20Tokens[collateralOffset],
            commonContracts.aTokens[collateralOffset],
            address(this),
            address(this),
            amount
        );
        UserDataAccountData memory userDataAccountData;
        (
            userDataAccountData.totalCollateralETH,,
            userDataAccountData.availableBorrowsETH,,
            userDataAccountData.ltv,
            userDataAccountData.healthFactor,
            userDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(address(this));
        assertEq(
            userDataAccountData.healthFactor, type(uint256).max, "Health factors should be max"
        );
        assertEq(userDataAccountData.liquidFunds, 0, "Liquid funds should be zero");
        assertGt(
            userDataAccountData.totalCollateralETH,
            0,
            "Total collateral should be greater than zero"
        );
        assertEq(userDataAccountData.availableBorrowsETH, 0, "Available borrows should be zero");

        console2.log("1 collateral amount: ", userDataAccountData.totalCollateralETH);
        console2.log("1 healthFactor: ", userDataAccountData.healthFactor);
        console2.log("1 availableBorrowsETH: ", userDataAccountData.availableBorrowsETH);
        console2.log("1 ltv: ", userDataAccountData.ltv);
        console2.log("1 liquidFunds: ", userDataAccountData.liquidFunds);

        console2.log(
            "All funds: ",
            securityAccessManager.getAllFunds(
                address(this), address(commonContracts.aTokens[collateralOffset])
            )
        );

        /* Withdrawal can be done just after deposit - cooldown shouldn;t block it */
        deployedContracts.lendingPool
            .withdraw(address(erc20Tokens[collateralOffset]), true, amount, address(this));

        (
            userDataAccountData.totalCollateralETH,,
            userDataAccountData.availableBorrowsETH,,
            userDataAccountData.ltv,
            userDataAccountData.healthFactor,
            userDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(address(this));
        // assertEq(
        //     userDataAccountData.healthFactor, type(uint256).max, "Health factors should be max"
        // );
        // assertEq(
        //     userDataAccountData.liquidFunds,
        //     userDataAccountData.totalCollateralETH,
        //     "Liquid funds should be the same as total collateral"
        // );
        // assertGt(
        //     userDataAccountData.totalCollateralETH,
        //     0,
        //     "Total collateral should be greater than zero"
        // );

        console2.log("2 collateral amount: ", userDataAccountData.totalCollateralETH);
        console2.log("2 healthFactor: ", userDataAccountData.healthFactor);
        console2.log("2 availableBorrowsETH: ", userDataAccountData.availableBorrowsETH);
        console2.log("2 ltv: ", userDataAccountData.ltv);
        console2.log("2 liquidFunds: ", userDataAccountData.liquidFunds);
        // assertLt(
        //     userDataAccountData.healthFactor,
        //     type(uint256).max,
        //     "Health factors should be less than max"
        // );
        // assertEq(
        //     userDataAccountData.liquidFunds,
        //     userDataAccountData.totalCollateralETH,
        //     "Liquid funds should be the same as total collateral"
        // );
        // assertGt(
        //     userDataAccountData.totalCollateralETH,
        //     0,
        //     "Total collateral should be greater than zero"
        // );
    }

    function test_aTokenTransfersChangesLiquidFunds(
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 cooldownTime
    ) public {
        collateralOffset = bound(collateralOffset, 0, erc20Tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, erc20Tokens.length - 1);
        cooldownTime = bound(cooldownTime, cooldownTimes[0], 2 * cooldownTimes[0]);
        TokenTypes memory borrowToken = TokenTypes({
            token: erc20Tokens[borrowOffset],
            aToken: commonContracts.aTokens[borrowOffset],
            debtToken: commonContracts.variableDebtTokens[borrowOffset]
        });
        uint256 amount = securityAccessManager.getMaxDepositInOriginDecimals(
            0, address(commonContracts.aTokens[collateralOffset])
        );
        console2.log("Amount: ", amount);
        fixture_deposit(
            erc20Tokens[collateralOffset],
            commonContracts.aTokens[collateralOffset],
            address(this),
            address(this),
            amount
        );
        UserDataAccountData memory previousUserDataAccountData;
        (
            previousUserDataAccountData.totalCollateralETH,,
            previousUserDataAccountData.availableBorrowsETH,,
            previousUserDataAccountData.ltv,
            previousUserDataAccountData.healthFactor,
            previousUserDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(address(this));
        assertEq(
            previousUserDataAccountData.healthFactor,
            type(uint256).max,
            "Health factors should be max"
        );
        assertEq(previousUserDataAccountData.liquidFunds, 0, "Liquid funds should be zero");
        assertGt(
            previousUserDataAccountData.totalCollateralETH,
            0,
            "Total collateral should be greater than zero"
        );
        assertEq(
            previousUserDataAccountData.availableBorrowsETH, 0, "Available borrows should be zero"
        );

        // Wait cooldown time
        vm.warp(block.timestamp + cooldownTime);

        (
            previousUserDataAccountData.totalCollateralETH,,
            previousUserDataAccountData.availableBorrowsETH,,
            previousUserDataAccountData.ltv,
            previousUserDataAccountData.healthFactor,
            previousUserDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(address(this));

        // uint256 maxBorrowTokenToBorrowInCollateralUnit =
        //     fixture_getMaxValueToBorrow(erc20Tokens[collateralOffset], borrowToken.token, amount);
        assertGt(
            previousUserDataAccountData.availableBorrowsETH,
            0,
            "Available borrows should be greater than 0"
        );
        // deal(address(borrowToken.token), user1, 2 * maxBorrowTokenToBorrowInCollateralUnit);

        // vm.prank(pointsManager);
        // securityAccessManager.increaseTrustPoints(user1, trustThresholds[2] + 1);
        commonContracts.aTokens[collateralOffset].transfer(user1, amount / 2);

        UserDataAccountData memory userDataAccountData;
        (
            userDataAccountData.totalCollateralETH,,
            userDataAccountData.availableBorrowsETH,,
            userDataAccountData.ltv,
            userDataAccountData.healthFactor,
            userDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(address(this));
        console2.log("HealthFactor: ", userDataAccountData.healthFactor);
        console2.log("availableBorrowsETH: ", userDataAccountData.availableBorrowsETH);
        console2.log("liquidFunds: ", userDataAccountData.liquidFunds);
        console2.log(
            "previousUserDataAccountData.liquidFunds: ", previousUserDataAccountData.liquidFunds
        );
        uint256 amountInETH =
            (commonContracts.oracle.getAssetPrice(address(erc20Tokens[collateralOffset]))
                    * (amount / 2)) / (10 ** erc20Tokens[collateralOffset].decimals());

        console2.log("amountInETH: ", amountInETH);
        console2.log(
            "previousUserDataAccountData.liquidFunds - amountInETH",
            previousUserDataAccountData.liquidFunds - amountInETH
        );

        assertLt(
            userDataAccountData.availableBorrowsETH,
            previousUserDataAccountData.availableBorrowsETH,
            "Available to borrow in ETH is not less after transfer"
        );
        assertEq(
            userDataAccountData.liquidFunds,
            previousUserDataAccountData.liquidFunds - amountInETH,
            "Liquid funds should be less by {amountInETH}"
        );
        assertEq(
            userDataAccountData.totalCollateralETH,
            previousUserDataAccountData.totalCollateralETH - amountInETH,
            "Total collateral should be less by {amountInETH}"
        );
        (
            userDataAccountData.totalCollateralETH,,
            userDataAccountData.availableBorrowsETH,,
            userDataAccountData.ltv,
            userDataAccountData.healthFactor,
            userDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(user1);
        console2.log("User's healthFactor: ", userDataAccountData.healthFactor);
        console2.log("User's availableBorrowsETH: ", userDataAccountData.availableBorrowsETH);
        console2.log("User's liquidFunds: ", userDataAccountData.liquidFunds);
        console2.log("User's total collateral: ", userDataAccountData.totalCollateralETH);

        assertGt(
            userDataAccountData.totalCollateralETH,
            0,
            "User's Total collateral should be greater than zero"
        );
        assertEq(userDataAccountData.liquidFunds, 0, "User's liquidFunds collateral should be zero");
        assertEq(
            userDataAccountData.availableBorrowsETH, 0, "User's availableBorrowsETH should be zero"
        );

        // Wait cooldown time
        vm.warp(block.timestamp + cooldownTime);

        (
            userDataAccountData.totalCollateralETH,,
            userDataAccountData.availableBorrowsETH,,
            userDataAccountData.ltv,
            userDataAccountData.healthFactor,
            userDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(user1);
        console2.log("User's availableBorrowsETH: ", userDataAccountData.availableBorrowsETH);
        console2.log("User's liquidFunds: ", userDataAccountData.liquidFunds);
        assertGt(
            userDataAccountData.liquidFunds, 0, "User's liquidFunds should be greater than zero"
        );
        assertGt(
            userDataAccountData.availableBorrowsETH,
            0,
            "User's availableBorrowsETH should be greater than zero"
        );
    }

    function test_liquidFundsIncreasesTogertherWithLiquidityIndex(
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 cooldownTime
    ) public {
        collateralOffset = bound(collateralOffset, 0, erc20Tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, erc20Tokens.length - 1);
        cooldownTime = bound(cooldownTime, cooldownTimes[0], 2 * cooldownTimes[0]);
        uint256 amount = securityAccessManager.getMaxDepositInOriginDecimals(
            0, address(commonContracts.aTokens[collateralOffset])
        );
        userAccountDataChanges(collateralOffset, borrowOffset, cooldownTime, amount);

        // Wait cooldown time
        vm.warp(block.timestamp + cooldownTime);

        UserDataAccountData memory previousUserDataAccount;
        (
            previousUserDataAccount.totalCollateralETH,,
            previousUserDataAccount.availableBorrowsETH,,
            previousUserDataAccount.ltv,
            previousUserDataAccount.healthFactor,
            previousUserDataAccount.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(user1);

        // Wait cooldown time
        vm.warp(block.timestamp + 7 days);

        // Withdraw in order to sync index
        deployedContracts.lendingPool
            .withdraw(address(erc20Tokens[collateralOffset]), true, 100, address(this));

        UserDataAccountData memory userDataAccountData;
        (
            userDataAccountData.totalCollateralETH,,
            userDataAccountData.availableBorrowsETH,,
            userDataAccountData.ltv,
            userDataAccountData.healthFactor,
            userDataAccountData.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(user1);

        console2.log(
            "userDataAccountData.totalCollateralETH: ", userDataAccountData.totalCollateralETH
        );
        console2.log(
            "previousUserDataAccount.totalCollateralETH: ",
            previousUserDataAccount.totalCollateralETH
        );

        console2.log(
            "userDataAccountData.availableBorrowsETH: ", userDataAccountData.availableBorrowsETH
        );
        console2.log(
            "previousUserDataAccount.availableBorrowsETH: ",
            previousUserDataAccount.availableBorrowsETH
        );

        console2.log("userDataAccountData.liquidFunds: ", userDataAccountData.liquidFunds);

        console2.log("previousUserDataAccount.liquidFunds: ", previousUserDataAccount.liquidFunds);

        assertGt(
            userDataAccountData.availableBorrowsETH,
            previousUserDataAccount.availableBorrowsETH,
            "User's availableBorrowsETH should be greater than previous as user1 accrued interests"
        );
        assertGt(
            userDataAccountData.liquidFunds,
            previousUserDataAccount.liquidFunds,
            "User's liquidFunds should be greater than previous as user1 accrued interests"
        );
        // assertGt(
        //     userDataAccountData.availableBorrowsETH,
        //     previousUserDataAccount.availableBorrowsETH,
        //     "User's availableBorrowsETH should be greater than previous as user1 accrued interests"
        // );
    }

    function test_multipleDepositsBorrows(
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 cooldownTime
    ) public {
        collateralOffset = bound(collateralOffset, 0, erc20Tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, erc20Tokens.length - 1);
        cooldownTime = bound(cooldownTime, cooldownTimes[0], 2 * cooldownTimes[0]);
        uint256 collateralAmount = securityAccessManager.getMaxDepositInOriginDecimals(
            0, address(commonContracts.aTokens[collateralOffset])
        );
        uint256 borrowAmount = securityAccessManager.getMaxDepositInOriginDecimals(
            0, address(commonContracts.aTokens[borrowOffset])
        );
        userAccountDataChanges(collateralOffset, borrowOffset, cooldownTime, collateralAmount / 3);

        // Wait cooldown time
        vm.warp(block.timestamp + cooldownTime);

        console2.log("Deposit borrow token by user2");
        deal(address(erc20Tokens[borrowOffset]), user2, borrowAmount);
        vm.startPrank(user2);
        erc20Tokens[borrowOffset].approve(address(deployedContracts.lendingPool), type(uint256).max);
        deployedContracts.lendingPool
            .deposit(address(erc20Tokens[borrowOffset]), true, borrowAmount, user2);
        vm.stopPrank();

        vm.startPrank(address(this));
        erc20Tokens[collateralOffset].approve(
            address(deployedContracts.lendingPool), type(uint256).max
        );
        erc20Tokens[borrowOffset].approve(address(deployedContracts.lendingPool), type(uint256).max);

        UserDataAccountData memory previousUserDataAccount;
        (
            previousUserDataAccount.totalCollateralETH,,
            previousUserDataAccount.availableBorrowsETH,,,
            previousUserDataAccount.healthFactor,
            previousUserDataAccount.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(address(this));

        console2.log("Loop");

        for (uint256 idx = 0; idx < 100; idx++) {
            console2.log("->>>>> IDX: ", idx);
            deployedContracts.lendingPool
                .deposit(
                    address(erc20Tokens[collateralOffset]),
                    true,
                    collateralAmount / 100,
                    address(this)
                );
            deployedContracts.lendingPool
                .borrow(address(erc20Tokens[borrowOffset]), true, borrowAmount / 200, address(this));
            deployedContracts.lendingPool
                .repay(address(erc20Tokens[borrowOffset]), true, borrowAmount / 200, address(this));
            deployedContracts.lendingPool
                .withdraw(
                    address(erc20Tokens[collateralOffset]),
                    true,
                    collateralAmount / 100,
                    address(this)
                );
            vm.warp(block.timestamp + cooldownTime / 100);
        }
        vm.stopPrank();

        UserDataAccountData memory userDataAccount;
        (
            userDataAccount.totalCollateralETH,,
            userDataAccount.availableBorrowsETH,,,
            userDataAccount.healthFactor,
            userDataAccount.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(address(this));

        console2.log(
            "TotalCollateral before: %s after: %s",
            previousUserDataAccount.totalCollateralETH,
            userDataAccount.totalCollateralETH
        );
        console2.log(
            "AvailableBorrowsETH before: %s after: %s",
            previousUserDataAccount.availableBorrowsETH,
            userDataAccount.availableBorrowsETH
        );
        console2.log(
            "healthFactor before: %s after: %s",
            previousUserDataAccount.healthFactor,
            userDataAccount.healthFactor
        );
        console2.log(
            "liquidFunds before: %s after: %s",
            previousUserDataAccount.liquidFunds,
            userDataAccount.liquidFunds
        );

        assertEq(
            userDataAccount.totalCollateralETH,
            userDataAccount.liquidFunds,
            "Liquid funds are not equal with total collateral"
        );
        assertApproxEqRel(
            previousUserDataAccount.liquidFunds,
            userDataAccount.liquidFunds,
            1e16,
            "liquid funds shall be almost the same after txs (1% deviation allowed)"
        );
    }

    function test_multipleTransfers(
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 cooldownTime
    ) public {
        collateralOffset = bound(collateralOffset, 0, erc20Tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, erc20Tokens.length - 1);
        cooldownTime = bound(cooldownTime, cooldownTimes[0], 2 * cooldownTimes[0]);
        uint256 collateralAmount = securityAccessManager.getMaxDepositInOriginDecimals(
            0, address(commonContracts.aTokens[collateralOffset])
        );

        deal(address(erc20Tokens[collateralOffset]), user1, collateralAmount);
        console2.log("User deposits... ");
        fixture_deposit(
            erc20Tokens[collateralOffset],
            commonContracts.aTokens[collateralOffset],
            user1,
            user1,
            collateralAmount
        );

        // Wait cooldown time
        vm.warp(block.timestamp + cooldownTime);

        UserDataAccountData memory previousUserDataAccount;
        (
            previousUserDataAccount.totalCollateralETH,,
            previousUserDataAccount.availableBorrowsETH,,,
            previousUserDataAccount.healthFactor,
            previousUserDataAccount.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(user1);

        console2.log(
            "User1 deposit checkpoints length: ",
            securityAccessManager.getUserDepositCheckpoints(
                user1, address(commonContracts.aTokens[collateralOffset])
            )
            .length
        );

        vm.startPrank(user1);

        console2.log("Loop");
        for (uint256 idx = 0; idx < 100; idx++) {
            console2.log("->>>>> IDX: ", idx);
            commonContracts.aTokens[collateralOffset].transfer(user2, 1);
            vm.warp(block.timestamp + cooldownTime / 100);
        }

        // commonContracts.aTokens[collateralOffset].transfer(user2, 1);
        vm.stopPrank();

        UserDataAccountData memory userDataAccount;
        (
            userDataAccount.totalCollateralETH,,
            userDataAccount.availableBorrowsETH,,,
            userDataAccount.healthFactor,
            userDataAccount.liquidFunds
        ) = deployedContracts.lendingPool.getUserAccountData(user1);

        console2.log(
            "TotalCollateral before: %s after: %s",
            previousUserDataAccount.totalCollateralETH,
            userDataAccount.totalCollateralETH
        );
        console2.log(
            "AvailableBorrowsETH before: %s after: %s",
            previousUserDataAccount.availableBorrowsETH,
            userDataAccount.availableBorrowsETH
        );
        console2.log(
            "healthFactor before: %s after: %s",
            previousUserDataAccount.healthFactor,
            userDataAccount.healthFactor
        );
        console2.log(
            "liquidFunds before: %s after: %s",
            previousUserDataAccount.liquidFunds,
            userDataAccount.liquidFunds
        );

        assertEq(
            userDataAccount.totalCollateralETH,
            userDataAccount.liquidFunds,
            "Liquid funds are not equal with total collateral"
        );
        uint256 amountInETH =
            (commonContracts.oracle.getAssetPrice(address(erc20Tokens[collateralOffset])) * 100)
                / (10 ** erc20Tokens[collateralOffset].decimals());

        console2.log("Amount in ETH: ", amountInETH);

        assertApproxEqAbs(
            previousUserDataAccount.liquidFunds,
            userDataAccount.liquidFunds + amountInETH,
            1,
            "liquid funds shall be less by {amountInETH}"
        );
    }
}
