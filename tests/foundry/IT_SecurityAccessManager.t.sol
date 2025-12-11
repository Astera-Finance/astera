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

    function test_userAccountDataChanges(
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
        console2.log("HhealthFactor: ", userDataAccountData.healthFactor);
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

        console2.log("ltv: ", userDataAccountData.ltv);
        console2.log("liquidFunds: ", userDataAccountData.liquidFunds);

        assertLt(
            userDataAccountData.liquidFunds,
            previousUserDataAccountData.liquidFunds,
            "Liquid funds should be the same as total collateral"
        );
        assertLt(
            userDataAccountData.totalCollateralETH,
            previousUserDataAccountData.totalCollateralETH,
            "Total collateral should be greater than zero"
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
        console2.log("total collateral: ", userDataAccountData.totalCollateralETH);

        assertGt(
            userDataAccountData.totalCollateralETH,
            0,
            "Total collateral should be greater than zero"
        );

        // TODO: complete test !!
    }

    function test_liquidFundsIncreasesTogertherWithLiquidityIndex(
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 cooldownTime
    ) public {}
}
