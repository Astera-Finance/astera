// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SecurityAccessManager} from "contracts/protocol/core/SecurityAccessManager.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";
import {MintableERC20} from "contracts/mocks/tokens/MintableERC20.sol";
import {IERC20Detailed} from "contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";

import {console2} from "forge-std/console2.sol";

/**
 * @title SecurityAccessManagerTest
 * @notice Comprehensive test suite for SecurityAccessManager.sol
 * @dev Tests cover tier assignment, cooldowns, deposits, and access control
 */
contract SecurityAccessManagerTest is Test {
    // ============ State Variables ============

    SecurityAccessManager public registry;

    // Test addresses
    address public admin = address(0x1);
    address public pointsManager = address(0x2);
    address public user1 = address(0x100);
    address public user2 = address(0x200);
    address public unauthorizedUser = address(0x999);

    // Test assets
    address public USDC;
    address public USDT;
    address[] assets;

    // Tier configuration
    uint32[] public cooldownTimes;
    uint208[] public maxDeposits;
    uint16[] public trustThresholds;

    // ============ Setup ============

    function setUp() public {
        // Deploy registry
        USDC = address(new MintableERC20("USD Coin", "USDC", 6));
        USDT = address(new MintableERC20("Tether USD", "USDT", 6));

        assets.push(USDC);
        assets.push(USDT);
        assets.push(address(new MintableERC20("Wrapped Bitcoin", "WBTC", 8)));
        assets.push(address(new MintableERC20("Wrapped ETH", "WETH", 18)));

        vm.label(USDC, "USDC");
        vm.label(USDT, "USDT");
        vm.label(assets[2], "WBTC");
        vm.label(assets[3], "WETH");

        address[] memory managers = new address[](1);
        managers[0] = pointsManager;
        registry = new SecurityAccessManager(admin, managers, assets);

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
    }

    // ============ CRITICAL BUG FIX TESTS ============

    /**
     * @notice TEST FIX #1: setLevelParams() must delete before pushing
     * @dev Verifies that calling setLevelParams() twice replaces params, not appends
     */
    function test_SetLevelParams_ReplacesNotAppends(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        // First call should create 3 tiers
        uint8 tierCount1 = 3;

        // Second call with different params
        uint32[] memory cooldownTimes2 = new uint32[](2);
        uint208[] memory maxDeposits2 = new uint208[](2);
        uint16[] memory trustThresholds2 = new uint16[](2);

        cooldownTimes2[0] = 3 days;
        cooldownTimes2[1] = 6 hours;

        maxDeposits2[0] = 2000e8;
        maxDeposits2[1] = 8000e8;

        trustThresholds2[0] = 0;
        trustThresholds2[1] = 200;

        vm.prank(admin);
        registry.setLevelParams(cooldownTimes2, maxDeposits2, trustThresholds2, asset);

        // Should have 2 tiers NOW, not 5
        // Verify by checking tier assignment
        vm.prank(pointsManager);
        registry.increaseTrustPoints(user1, 150);

        uint8 tier = registry.getUserLevel(user1, asset);
        // With thresholds [0, 200], 150 pts should be Tier 0
        // (150 >= 0 and 150 < 200)
        assertEq(tier, 0, "Should have only 2 tiers, not duplicates");
    }

    /**
     * @dev Verifies correct tier assignment with backward loop
     */
    function test_GetUserLevel_ReturnsHighestQualifyingTier(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        // Test case 1: User at boundary
        vm.prank(pointsManager);
        registry.increaseTrustPoints(user1, 150);

        uint8 tier = registry.getUserLevel(user1, asset);
        // With thresholds [0, 100, 500]
        // 150 >= 100 but 150 < 500 → Should be Tier 1
        assertEq(tier, 1, "User with 150 points should be Tier 1");

        // Test case 2: User at exact threshold
        vm.startPrank(pointsManager);
        registry.decreaseTrustPoints(user1, 150);
        registry.increaseTrustPoints(user1, 100);
        vm.stopPrank();

        tier = registry.getUserLevel(user1, asset);
        // 100 >= 100 and 100 < 500 → Should be Tier 1
        assertEq(tier, 1, "User with 100 points should be Tier 1");

        // Test case 3: User exceeds all thresholds
        vm.startPrank(pointsManager);
        registry.decreaseTrustPoints(user1, 100);
        registry.increaseTrustPoints(user1, 1000);
        vm.stopPrank();

        tier = registry.getUserLevel(user1, asset);
        // 1000 >= 500 → Should be Tier 2
        assertEq(tier, 2, "User with 1000 points should be Tier 2");

        // Test case 4: User below all thresholds
        vm.prank(pointsManager);
        registry.decreaseTrustPoints(user1, 1000);

        tier = registry.getUserLevel(user1, asset);
        // 0 >= 0 but 0 < 100 → Should be Tier 0
        assertEq(tier, 0, "User with 0 points should be Tier 0");
    }

    // ============ TIER ASSIGNMENT TESTS ============

    /**
     * @notice Test: Tier assignment at all boundary points
     */
    function test_TierAssignment_AllBoundaries(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        // Test all boundary cases
        uint16[] memory testPoints = new uint16[](6);
        uint8[] memory expectedTiers = new uint8[](6);

        testPoints[0] = 0; // At T0 threshold
        expectedTiers[0] = 0;
        testPoints[1] = 99; // Just below T1
        expectedTiers[1] = 0;
        testPoints[2] = 100; // At T1 threshold
        expectedTiers[2] = 1;
        testPoints[3] = 499; // Just below T2
        expectedTiers[3] = 1;
        testPoints[4] = 500; // At T2 threshold
        expectedTiers[4] = 2;
        testPoints[5] = 1000; // Well above T2
        expectedTiers[5] = 2;

        for (uint256 i = 0; i < testPoints.length; i++) {
            // Set user points
            vm.prank(pointsManager);
            registry.increaseTrustPoints(user1, testPoints[i]);

            uint8 tier = registry.getUserLevel(user1, asset);
            assertEq(
                tier,
                expectedTiers[i],
                string(abi.encodePacked("Tier mismatch for points: ", testPoints[i]))
            );

            // Reset for next test
            if (testPoints[i] > 0) {
                vm.prank(pointsManager);
                registry.decreaseTrustPoints(user1, testPoints[i]);
            }
        }
    }

    /**
     * @notice Test: Tier remains consistent
     */
    function test_TierAssignment_Consistency(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        vm.prank(pointsManager);
        registry.increaseTrustPoints(user1, 250);

        uint8 tier1 = registry.getUserLevel(user1, asset);
        uint8 tier2 = registry.getUserLevel(user1, asset);

        assertEq(tier1, tier2, "Tier should be consistent for same points");
        assertEq(tier1, 1, "User should be Tier 1");
    }

    // ============ COOLDOWN TESTS ============

    /**
     * @notice Test: Deposits are locked until cooldown expires
     */
    function test_Cooldown_LocksDepositUntilExpiry(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        // User deposits
        vm.startPrank(asset);
        registry.registerDeposit(uint208(1000 * 10 ** IERC20Detailed(asset).decimals()), user1);

        // Immediately after deposit, should be locked
        uint256 liquid = registry.getLiquidFunds(user1, asset);
        assertEq(liquid, 0, "Deposit should be locked immediately");

        // After 1 day (less than 2 day cooldown for Tier 0), still locked
        vm.warp(block.timestamp + 1 days);
        liquid = registry.getLiquidFunds(user1, asset);
        assertEq(liquid, 0, "Deposit should be locked after 1 day (Tier 0 = 2 days)");

        // After 2 days, should be unlocked
        vm.warp(block.timestamp + 1 days);
        liquid = registry.getLiquidFunds(user1, asset);
        assertEq(
            liquid,
            1000 * 10 ** IERC20Detailed(asset).decimals(),
            "Deposit should unlock after 2 days"
        );
        vm.stopPrank();
    }

    /**
     * @notice Test: Multiple deposits have independent cooldowns
     */
    function test_Cooldown_MultipleDeposits_Independent(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        // Deposit A at T+0
        vm.startPrank(asset);
        registry.registerDeposit(uint208(500 * 10 ** IERC20Detailed(asset).decimals()), user1);

        uint256 liquid = registry.getLiquidFunds(user1, asset);
        assertEq(liquid, 0, "Both deposits still locked");
        uint256 time1 = block.timestamp;

        // Deposit B at T+1 day
        vm.warp(block.timestamp + 1 days);
        registry.registerDeposit(uint208(500 * 10 ** IERC20Detailed(asset).decimals()), user1);

        // At T+1.5 days: First deposit (2 day cooldown) still locked
        // Second deposit (1.5 days passed) still locked
        vm.warp(block.timestamp + 12 hours);
        liquid = registry.getLiquidFunds(user1, asset);
        assertEq(liquid, 0, "Both deposits still locked");

        // At T+2 days: First deposit unlocks, second still locked
        vm.warp(time1 + 2 days + 1 seconds);
        liquid = registry.getLiquidFunds(user1, asset);
        assertEq(
            liquid, 500 * 10 ** IERC20Detailed(asset).decimals(), "Only first deposit should unlock"
        );

        // At T+3 days: Both deposits unlocked
        vm.warp(time1 + 3 days + 1 seconds);
        liquid = registry.getLiquidFunds(user1, asset);
        assertEq(
            liquid, 1000 * 10 ** IERC20Detailed(asset).decimals(), "Both deposits should be liquid"
        );
        vm.stopPrank();
    }

    /**
     * @notice Test: Tier promotion affects future cooldown
     */
    function test_Cooldown_AffectedByTierPromotion(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        // User starts at Tier 0 (2 day cooldown)
        vm.startPrank(asset);
        registry.registerDeposit(uint208(1000 * 10 ** IERC20Detailed(asset).decimals()), user1);
        vm.stopPrank();

        // After 1 day, promote to Tier 1 (1 day cooldown)
        vm.warp(block.timestamp + 1 days);
        vm.prank(pointsManager);
        registry.increaseTrustPoints(user1, 100);

        // After 1 day and promotion, should be liquid
        // // (OLD deposit time + NEW tier's 1-day cooldown)
        // vm.warp(block.timestamp + 1 days + 1 seconds);
        uint256 liquid = registry.getLiquidFunds(user1, asset);
        assertEq(
            liquid,
            1000 * 10 ** IERC20Detailed(asset).decimals(),
            "Should be liquid with Tier 1 cooldown applied"
        );
        vm.prank(pointsManager);
        registry.decreaseTrustPoints(user1, 20);
        liquid = registry.getLiquidFunds(user1, asset);
        assertEq(liquid, 0, "Should be illiquid after trust points deduction");
        vm.warp(block.timestamp + 1 days - 1);
        liquid = registry.getLiquidFunds(user1, asset);
        assertEq(liquid, 0, "Should be illiquid after not all day of waiting");
        vm.warp(block.timestamp + 1);
        liquid = registry.getLiquidFunds(user1, asset);
        assertEq(
            liquid,
            1000 * 10 ** IERC20Detailed(asset).decimals(),
            "Should be liquid after full day of waiting"
        );
    }

    // ============ DEPOSIT LIMIT TESTS ============

    /**
     * @notice Test: Cannot exceed tier-specific deposit limit
     */
    function test_DepositLimit_EnforcesTierMax(uint256 offset) public {
        offset = bound(offset, 0, 3);
        console2.log("assets length:", assets.length);
        address asset1 = assets[offset];
        address asset2 = assets[(offset + 1) % 4];
        vm.startPrank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset1);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset2);
        vm.stopPrank();

        // Tier 0: Max 1000e8
        vm.startPrank(asset1);
        registry.registerDeposit(uint208(1000 * 10 ** IERC20Detailed(asset1).decimals()), user1); // Should succeed

        console2.log("All funds 1:", registry.getAllFunds(user1, asset1));
        console2.log("Max funds 1:", registry.getMaxDepositInOriginDecimals(0, asset1));

        // Try to exceed limit
        uint208 depositAmount = uint208(1 * 10 ** IERC20Detailed(asset1).decimals());
        vm.expectRevert(bytes(Errors.SAM_EXCEEDED_MAX_DEPOSIT));
        registry.registerDeposit(depositAmount, user1);
        vm.stopPrank();

        // Promote to Tier 1: Max 5000e8
        vm.prank(pointsManager);
        registry.increaseTrustPoints(user1, 100);

        // Wait for cooldown
        vm.warp(block.timestamp + 2 days + 1 seconds);
        console2.log("All funds 2:", registry.getAllFunds(user1, asset2));
        console2.log("Max funds 2:", registry.getLevelParams(asset2)[1].maxDeposit);

        depositAmount = uint208(5000 * 10 ** IERC20Detailed(asset2).decimals());
        // Can now deposit more (new deposit, independent)
        vm.startPrank(asset2);
        registry.registerDeposit(uint208(depositAmount), user1); // Different asset
        depositAmount = uint208(4000 * 10 ** IERC20Detailed(asset1).decimals());
        vm.stopPrank();
        vm.startPrank(asset1);
        registry.registerDeposit(depositAmount, user1); // Different asset
        vm.stopPrank();

        console2.log("2222 All funds 1:", registry.getAllFunds(user1, asset2));
        console2.log("2222 Max funds 1:", registry.getMaxDepositInOriginDecimals(1, asset2));

        vm.startPrank(asset2);
        // But still can't exceed 5000e8 limit
        depositAmount = uint208(10 ** IERC20Detailed(asset2).decimals());
        vm.expectRevert(bytes(Errors.SAM_EXCEEDED_MAX_DEPOSIT));
        registry.registerDeposit(depositAmount, user1);
        vm.stopPrank();
    }

    /**
     * @notice Test: Multiple deposits each below limit (independent)
     */
    function test_DepositLimit_MultipleBelowLimit(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset1 = assets[offset];
        address asset2 = assets[(offset + 1) % 4];
        vm.startPrank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset1);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset2);
        vm.stopPrank();

        // Deposit 1
        vm.startPrank(asset1);
        registry.registerDeposit(uint208(1000 * 10 ** IERC20Detailed(asset1).decimals()), user1);
        vm.stopPrank();

        // Wait for cooldown
        vm.warp(block.timestamp + 2 days + 1 seconds);

        vm.startPrank(asset2);
        // Deposit 2 (each is separate, no cumulative limit)
        registry.registerDeposit(uint208(1000 * 10 ** IERC20Detailed(asset2).decimals()), user1);
        vm.stopPrank();

        // Total deposits = 2000e8, but each deposit respects 1000e8 limit
        uint256 usdcAll = registry.getAllFunds(user1, asset1);
        uint256 usdtAll = registry.getAllFunds(user1, asset2);

        assertEq(usdcAll, 1000 * 10 ** IERC20Detailed(asset1).decimals(), "asset1 total correct");
        assertEq(usdtAll, 1000 * 10 ** IERC20Detailed(asset2).decimals(), "asset2 total correct");
    }

    // ============ ACCESS CONTROL TESTS ============

    /**
     * @notice Test: Only POINTS_MANAGER can increase trust points
     */
    function test_AccessControl_OnlyPointsManagerCanIncrease(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        // Unauthorized user tries
        vm.prank(unauthorizedUser);
        vm.expectRevert(bytes(Errors.SAM_UNAUTHORIZED));
        registry.increaseTrustPoints(user1, 100);

        // POINTS_MANAGER succeeds
        vm.prank(pointsManager);
        registry.increaseTrustPoints(user1, 100);

        // ADMIN succeeds
        vm.prank(admin);
        registry.increaseTrustPoints(user1, 100);

        uint8 tier = registry.getUserLevel(user1, asset);
        assertEq(tier, 1, "Trust points increased successfully");
    }

    /**
     * @notice Test: Only POINTS_MANAGER or ADMIN can decrease trust points
     */
    function test_AccessControl_OnlyPointsManagerCanDecrease(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        // Setup
        vm.prank(pointsManager);
        registry.increaseTrustPoints(user1, 100);

        // Unauthorized user tries
        vm.prank(unauthorizedUser);
        vm.expectRevert(bytes(Errors.SAM_UNAUTHORIZED));
        registry.decreaseTrustPoints(user1, 50);

        // POINTS_MANAGER succeeds
        vm.prank(pointsManager);
        registry.decreaseTrustPoints(user1, 50);

        // ADMIN succeeds
        vm.prank(admin);
        registry.decreaseTrustPoints(user1, 50);

        uint8 tier = registry.getUserLevel(user1, asset);
        assertEq(tier, 0, "Trust points decreased successfully");
    }

    /**
     * @notice Test: Only ADMIN can set level parameters
     */
    function test_AccessControl_OnlyAdminCanSetParams(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        // Unauthorized user tries
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        // Admin succeeds
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        // Verify params set
        uint8 tier = registry.getUserLevel(user1, asset);
        assertEq(tier, 0, "Initial tier is 0");
    }

    // ============ PARAMETER VALIDATION TESTS ============

    /**
     * @notice Test: Invalid tier parameters are rejected
     */
    function test_Parameters_Validation_Ordering(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        // Test 1: Cooldown not decreasing (should be rejected)
        uint32[] memory badCooldown = new uint32[](3);
        badCooldown[0] = 1 days;
        badCooldown[1] = 2 days; // Increasing, should fail
        badCooldown[2] = 3 days; // Increasing, should fail

        vm.prank(admin);
        vm.expectRevert(bytes(Errors.SAM_COOLDOWN_NOT_DECREASING));
        registry.setLevelParams(badCooldown, maxDeposits, trustThresholds, asset);

        // Test 2: Max deposits not increasing (should be rejected)
        uint208[] memory badDeposits = new uint208[](3);
        badDeposits[0] = uint208(5000 * 10 ** IERC20Detailed(USDC).decimals());
        badDeposits[1] = uint208(1000 * 10 ** IERC20Detailed(USDC).decimals()); // Decreasing, should fail
        badDeposits[2] = uint208(500 * 10 ** IERC20Detailed(USDC).decimals()); // Decreasing, should fail

        vm.prank(admin);
        vm.expectRevert(bytes(Errors.SAM_MAX_DEPOSIT_NOT_INCREASING));
        registry.setLevelParams(cooldownTimes, badDeposits, trustThresholds, asset);

        // Test 3: Thresholds not increasing (should be rejected)
        uint16[] memory badThresholds = new uint16[](3);
        badThresholds[0] = 100;
        badThresholds[1] = 50; // Decreasing, should fail
        badThresholds[2] = 10; // Decreasing, should fail

        vm.prank(admin);
        vm.expectRevert(bytes(Errors.SAM_TRUSTPOINTS_NOT_INCREASING));
        registry.setLevelParams(cooldownTimes, maxDeposits, badThresholds, asset);
    }

    /**
     * @notice Test: Array length mismatch is rejected
     */
    function test_Parameters_Validation_ArrayLength(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        uint32[] memory shortCooldown = new uint32[](2);
        shortCooldown[0] = 2 days;
        shortCooldown[1] = 1 days;

        vm.prank(admin);
        vm.expectRevert(bytes(Errors.SAM_WRONG_ARRAY_LENGTH));
        registry.setLevelParams(shortCooldown, maxDeposits, trustThresholds, asset);
    }

    // ============ INTEGRATION TESTS ============

    /**
     * @notice Test: Full user journey from Tier 0 to Tier 1
     */
    function test_Integration_FullUserJourney(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        address asset1 = assets[(offset + 1) % 4];
        vm.startPrank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset1);
        vm.stopPrank();

        // Day 1: User deposits at Tier 0
        vm.startPrank(asset);
        registry.registerDeposit(uint208(500 * 10 ** IERC20Detailed(asset).decimals()), user1);
        vm.stopPrank();

        assertEq(registry.getUserLevel(user1, asset), 0, "Should start at Tier 0");
        assertEq(registry.getLiquidFunds(user1, asset), 0, "Locked (2 day cooldown)");

        // Day 3: Deposit unlocks, gets promoted to Tier 1
        vm.warp(block.timestamp + 2 days + 1 seconds);

        assertEq(
            registry.getLiquidFunds(user1, asset),
            500 * 10 ** IERC20Detailed(asset).decimals(),
            "Not unlocked after cooldown"
        );

        vm.prank(pointsManager);
        registry.increaseTrustPoints(user1, 150); // Now Tier 1

        assertEq(registry.getUserLevel(user1, asset), 1, "Promoted to Tier 1");

        // Day 4: Make new deposit with Tier 1 limits
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(asset1);
        registry.registerDeposit(uint208(5000 * 10 ** IERC20Detailed(asset1).decimals()), user1);
        vm.stopPrank();
        assertEq(registry.getLiquidFunds(user1, asset1), 0, "New deposit locked (1 day cooldown)");

        // Day 5: New deposit unlocks
        vm.warp(block.timestamp + 1 days);

        assertEq(
            registry.getAllFunds(user1, asset),
            500 * 10 ** IERC20Detailed(asset).decimals(),
            "USDC changed"
        );
        assertEq(
            registry.getAllFunds(user1, asset1),
            5000 * 10 ** IERC20Detailed(asset1).decimals(),
            "USDT not accumulated"
        );
        vm.warp(block.timestamp + 1 seconds);
        assertEq(
            registry.getLiquidFunds(user1, asset1),
            5000 * 10 ** IERC20Detailed(asset1).decimals(),
            "Not unlocked after 1 day"
        );
    }

    // ============ EDGE CASE TESTS ============

    /**
     * @notice Test: New uninitialized user defaults to Tier 0
     */
    function test_EdgeCase_NewUserDefaultTier(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        address newUser = address(0x12345);

        uint8 tier = registry.getUserLevel(newUser, asset);
        assertEq(tier, 0, "New user should be Tier 0");

        uint256 funds = registry.getAllFunds(newUser, USDC);
        assertEq(funds, 0, "New user has no funds");
    }

    /**
     * @notice Test: Exact cooldown boundary
     */
    function test_EdgeCase_CooldownExactBoundary(uint256 offset) public {
        offset = bound(offset, 0, 3);
        address asset = assets[offset];
        vm.prank(admin);
        registry.setLevelParams(cooldownTimes, maxDeposits, trustThresholds, asset);

        vm.startPrank(asset);
        registry.registerDeposit(uint208(1000 * 10 ** IERC20Detailed(asset).decimals()), user1);
        vm.stopPrank();

        uint256 depositTime = block.timestamp;
        uint256 cooldownPeriod = 2 days;

        // At T + 2 days - 1 second: Should be 0
        vm.warp(depositTime + cooldownPeriod - 1 seconds);
        uint256 liquid = registry.getLiquidFunds(user1, asset);
        assertEq(liquid, 0, "Not liquid 1 second before cooldown expires");

        // At T + 2 days: Should be 0 (already passed)
        vm.warp(depositTime + cooldownPeriod);
        liquid = registry.getLiquidFunds(user1, asset);
        assertEq(
            liquid,
            1000 * 10 ** IERC20Detailed(asset).decimals(),
            "Not liquid at exact cooldown time"
        );

        // At T + 2 days + 1 second: Should unlock
        vm.warp(depositTime + cooldownPeriod + 1 seconds);
        liquid = registry.getLiquidFunds(user1, asset);
        assertEq(
            liquid, 1000 * 10 ** IERC20Detailed(asset).decimals(), "Should be liquid after cooldown"
        );
    }
}
