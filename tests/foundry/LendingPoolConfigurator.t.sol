// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {LendingPoolFixtures} from "tests/foundry/LendingPoolFixtures.t.sol";

// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract LendingPoolConfiguratorTest is Common, LendingPoolFixtures {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 constant MAX_VALID_RESERVE_FACTOR = 4000;
    uint256 constant MAX_VALID_DEPOSIT_CAP = type(uint72).max;

    event ReserveInitialized(
        address indexed asset,
        address indexed aToken,
        bool reserveType,
        address variableDebtToken,
        address interestRateStrategyAddress
    );
    event BorrowingEnabledOnReserve(address indexed asset, bool reserveType);
    event BorrowingDisabledOnReserve(address indexed asset, bool reserveType);
    event CollateralConfigurationChanged(
        address indexed asset,
        bool reserveType,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    );
    event ReserveActivated(address indexed asset, bool reserveType);
    event ReserveDeactivated(address indexed asset, bool reserveType);
    event ReserveFrozen(address indexed asset, bool reserveType);
    event ReserveUnfrozen(address indexed asset, bool reserveType);
    event ReserveFactorChanged(address indexed asset, bool reserveType, uint256 factor);
    event ReserveVolatilityTierChanged(address indexed asset, bool reserveType, uint256 tier);
    event ReserveLowVolatilityLtvChanged(address indexed asset, bool reserveType, uint256 ltv);
    event ReserveMediumVolatilityLtvChanged(address indexed asset, bool reserveType, uint256 ltv);
    event ReserveHighVolatilityLtvChanged(address indexed asset, bool reserveType, uint256 ltv);
    event ReserveDecimalsChanged(address indexed asset, bool reserveType, uint256 decimals);
    event ReserveDepositCapChanged(address indexed asset, bool reserveType, uint256 depositCap);
    event ReserveInterestRateStrategyChanged(
        address indexed asset, bool reserveType, address strategy
    );
    event ATokenUpgraded(
        address indexed asset,
        address indexed proxy,
        address indexed implementation,
        bool reserveType
    );
    event VariableDebtTokenUpgraded(
        address indexed asset, address indexed proxy, address indexed implementation
    );
    event Paused();
    event Unpaused();
    event EnableFlashloan(address indexed asset, bool reserveType);
    event DisableFlashloan(address indexed asset, bool reserveType);

    ERC20[] erc20Tokens;

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

        commonContracts.mockedVaults =
            fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
    }

    function testDisableBorrowingOnReserve() public {
        address provider = makeAddr("provider");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            TokenTypes memory borrowType = TokenTypes({
                token: erc20Tokens[idx],
                aToken: commonContracts.aTokens[idx],
                debtToken: commonContracts.variableDebtTokens[idx]
            });

            TokenTypes memory collateralType = TokenTypes({
                token: erc20Tokens[(idx + 1) % 3],
                aToken: commonContracts.aTokens[(idx + 1) % 3],
                debtToken: commonContracts.variableDebtTokens[(idx + 1) % 3]
            });

            vm.expectEmit(true, false, false, true);
            emit BorrowingDisabledOnReserve(address(borrowType.token), true);
            vm.startPrank(admin);
            deployedContracts.lendingPoolConfigurator
                .disableBorrowingOnReserve(address(borrowType.token), true);
            vm.stopPrank();

            uint256 amount = 1_000_000 * 10 ** collateralType.token.decimals();
            deal(address(collateralType.token), address(this), amount);
            fixture_deposit(
                collateralType.token, collateralType.aToken, address(this), address(this), amount
            );

            amount = 1_000_000 * 10 ** borrowType.token.decimals();
            deal(address(borrowType.token), provider, amount); //type(uint256).max - 1
            fixture_deposit(borrowType.token, borrowType.aToken, provider, provider, amount);

            uint256 amountToBorrow = (10 ** borrowType.token.decimals());

            vm.expectRevert(bytes(Errors.VL_BORROWING_NOT_ENABLED));
            deployedContracts.lendingPool
                .borrow(address(borrowType.token), true, amountToBorrow, address(this));

            vm.startPrank(admin);
            deployedContracts.lendingPoolConfigurator
                .enableBorrowingOnReserve(address(borrowType.token), true);
            vm.stopPrank();
            deployedContracts.lendingPool
                .borrow(address(borrowType.token), true, amountToBorrow, address(this));
        }
    }

    function testActivateReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveActivated(address(erc20Tokens[idx]), true);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator
                .activateReserve(address(erc20Tokens[idx]), true);
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getAsteraReserveFactor(), validReserveFactor);
        }
    }

    function testDeactivateReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            TokenTypes memory collateralType = TokenTypes({
                token: erc20Tokens[idx],
                aToken: commonContracts.aTokens[idx],
                debtToken: commonContracts.variableDebtTokens[idx]
            });

            uint256 amount = 10 ** collateralType.token.decimals();
            deal(address(collateralType.token), address(this), amount);
            collateralType.token.approve(address(deployedContracts.lendingPool), amount);
            deployedContracts.lendingPool
                .deposit(address(collateralType.token), true, amount, address(this));
            console2.log("0.Balance: ", collateralType.token.balanceOf(address(this)));
            deployedContracts.lendingPool
                .borrow(address(collateralType.token), true, amount / 10, address(this));

            vm.startPrank(admin);
            /* Shouldn't be able to deactivate when liquidity is not zero */
            vm.expectRevert(bytes(Errors.VL_RESERVE_LIQUIDITY_NOT_0));
            deployedContracts.lendingPoolConfigurator
                .deactivateReserve(address(erc20Tokens[idx]), true);
            vm.stopPrank();

            /* remove liquidity */
            collateralType.token.approve(address(deployedContracts.lendingPool), amount / 10);
            deployedContracts.lendingPool
                .repay(address(collateralType.token), true, amount / 10, address(this));
            deployedContracts.lendingPool
                .withdraw(
                    address(collateralType.token),
                    true,
                    collateralType.aToken.balanceOf(address(this)),
                    address(this)
                );
            vm.startPrank(admin);
            /* deactivate reserve - now shall be possible */
            vm.expectEmit(true, false, false, true);
            emit ReserveDeactivated(address(erc20Tokens[idx]), true);
            deployedContracts.lendingPoolConfigurator
                .deactivateReserve(address(erc20Tokens[idx]), true);
            vm.stopPrank();

            amount = 10 ** collateralType.token.decimals();
            collateralType.token.approve(address(deployedContracts.lendingPool), amount);

            /* deactivated reserve - new deposits shouldn't be possible */
            vm.expectRevert(bytes(Errors.VL_NO_ACTIVE_RESERVE));
            deployedContracts.lendingPool
                .deposit(address(collateralType.token), true, amount, address(this));
        }
    }

    function testFreezeReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            TokenTypes memory collateralType = TokenTypes({
                token: erc20Tokens[idx],
                aToken: commonContracts.aTokens[idx],
                debtToken: commonContracts.variableDebtTokens[idx]
            });

            uint256 amount = 10 ** collateralType.token.decimals();
            deal(address(collateralType.token), address(this), amount);
            collateralType.token.approve(address(deployedContracts.lendingPool), amount);
            deployedContracts.lendingPool
                .deposit(address(collateralType.token), true, amount, address(this));
            deployedContracts.lendingPool
                .borrow(address(collateralType.token), true, amount / 10, address(this));

            vm.expectEmit(true, false, false, true);
            emit ReserveFrozen(address(erc20Tokens[idx]), true);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.freezeReserve(address(erc20Tokens[idx]), true);

            amount = 10 ** collateralType.token.decimals();
            collateralType.token.approve(address(deployedContracts.lendingPool), amount);

            /* deactivated reserve - new deposits shouldn't be possible */
            vm.expectRevert(bytes(Errors.VL_RESERVE_FROZEN));
            deployedContracts.lendingPool
                .deposit(address(collateralType.token), true, amount, address(this));
            vm.expectRevert(bytes(Errors.VL_RESERVE_FROZEN));
            deployedContracts.lendingPool
                .borrow(address(collateralType.token), true, amount / 10, address(this));
            /* repay and withdraw actions shall pass */
            deployedContracts.lendingPool
                .repay(address(collateralType.token), true, amount / 10, address(this));
            deployedContracts.lendingPool
                .withdraw(address(collateralType.token), true, amount, address(this));
        }
    }

    function testUnfreezeReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveUnfrozen(address(erc20Tokens[idx]), true);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator
                .unfreezeReserve(address(erc20Tokens[idx]), true);
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getAsteraReserveFactor(), validReserveFactor);
        }
    }

    function testsetAsteraReserveFactor_Positive(uint256 validReserveFactor) public {
        validReserveFactor = bound(validReserveFactor, 0, MAX_VALID_RESERVE_FACTOR);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, false);
            emit ReserveFactorChanged(address(erc20Tokens[idx]), true, validReserveFactor);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator
                .setAsteraReserveFactor(address(erc20Tokens[idx]), true, validReserveFactor);
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getAsteraReserveFactor(), validReserveFactor);
        }
    }

    function testsetAsteraReserveFactor_Negative(uint256 invalidReserveFactor) public {
        invalidReserveFactor =
            bound(invalidReserveFactor, MAX_VALID_RESERVE_FACTOR + 1, type(uint256).max);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectRevert(bytes(Errors.RC_INVALID_RESERVE_FACTOR));
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator
                .setAsteraReserveFactor(address(erc20Tokens[idx]), true, invalidReserveFactor);
        }
    }

    function testSetDepositCap_Positive(uint256 validDepositCap) public {
        validDepositCap = bound(validDepositCap, 0, MAX_VALID_DEPOSIT_CAP - 1);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, false);
            emit ReserveDepositCapChanged(address(erc20Tokens[idx]), true, validDepositCap);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator
                .setDepositCap(address(erc20Tokens[idx]), true, validDepositCap);
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getAsteraReserveFactor(), validReserveFactor);
        }
    }

    function testSetDepositCap_Negative(uint256 invalidDepositCap) public {
        invalidDepositCap = bound(invalidDepositCap, MAX_VALID_DEPOSIT_CAP + 1, type(uint256).max);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectRevert(bytes(Errors.RC_INVALID_DEPOSIT_CAP));
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator
                .setDepositCap(address(erc20Tokens[idx]), false, invalidDepositCap);
        }
    }

    function testPoolInteractions(uint256 farmingPct, uint256 claimingThreshold) public {
        address aTokenAddress = address(commonContracts.aTokens[0]);

        address lendingPoolAddr = address(deployedContracts.lendingPool);

        vm.startPrank(admin);
        /* set profit handler positive */
        address profitHandler = makeAddr("profitHandler");
        vm.assume(profitHandler != address(0));
        vm.expectCall(
            lendingPoolAddr,
            abi.encodeCall(
                deployedContracts.lendingPool.setProfitHandler, (aTokenAddress, profitHandler)
            )
        );
        deployedContracts.lendingPoolConfigurator.setProfitHandler(aTokenAddress, profitHandler);

        /* set vault positive */
        vm.expectCall(
            lendingPoolAddr,
            abi.encodeCall(
                deployedContracts.lendingPool.setVault,
                (aTokenAddress, address(commonContracts.mockedVaults[0]))
            )
        );
        deployedContracts.lendingPoolConfigurator
            .setVault(aTokenAddress, address(commonContracts.mockedVaults[0]));

        /* set vault negative - 84 */
        vm.expectRevert(bytes(Errors.AT_INVALID_ADDRESS));
        deployedContracts.lendingPoolConfigurator.setVault(aTokenAddress, address(0));

        /* set farming pct positive */
        farmingPct = bound(farmingPct, 0, 10000);
        vm.expectCall(
            lendingPoolAddr,
            abi.encodeCall(deployedContracts.lendingPool.setFarmingPct, (aTokenAddress, farmingPct))
        );
        deployedContracts.lendingPoolConfigurator.setFarmingPct(aTokenAddress, farmingPct);

        /* set farming pct negative - 82 */
        farmingPct = bound(farmingPct, 10001, type(uint256).max);
        vm.expectRevert(bytes(Errors.AT_INVALID_AMOUNT));
        deployedContracts.lendingPoolConfigurator.setFarmingPct(aTokenAddress, farmingPct);

        /* set claiming threshold positive */
        claimingThreshold = bound(claimingThreshold, 0, type(uint256).max);
        vm.expectCall(
            lendingPoolAddr,
            abi.encodeCall(
                deployedContracts.lendingPool.setClaimingThreshold,
                (aTokenAddress, claimingThreshold)
            )
        );
        deployedContracts.lendingPoolConfigurator
            .setClaimingThreshold(aTokenAddress, claimingThreshold);

        /* set farming pct drift positive */
        farmingPct = bound(farmingPct, 0, 10000);
        vm.expectCall(
            lendingPoolAddr,
            abi.encodeCall(
                deployedContracts.lendingPool.setFarmingPctDrift, (aTokenAddress, farmingPct)
            )
        );
        deployedContracts.lendingPoolConfigurator.setFarmingPctDrift(aTokenAddress, farmingPct);

        /* set farming pct drift negative - 82 */
        farmingPct = bound(farmingPct, 10001, type(uint256).max);
        vm.expectRevert(bytes(Errors.AT_INVALID_AMOUNT));
        deployedContracts.lendingPoolConfigurator.setFarmingPctDrift(aTokenAddress, farmingPct);

        /* set profit handler negative - 83 */
        profitHandler = address(0);
        vm.expectRevert(bytes(Errors.AT_INVALID_ADDRESS));
        deployedContracts.lendingPoolConfigurator.setProfitHandler(aTokenAddress, profitHandler);

        vm.stopPrank();
    }

    function testAccessControlForPoolInteractions() public {
        address tokenAddress = makeAddr("tokenAddress");
        address randomAddress = makeAddr("randomAddress");
        uint256 randomNumber;
        randomNumber = bound(randomNumber, 0, type(uint256).max);
        /* access controls */
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        deployedContracts.lendingPoolConfigurator.setFarmingPct(tokenAddress, randomNumber);
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        deployedContracts.lendingPoolConfigurator.setClaimingThreshold(tokenAddress, randomNumber);
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        deployedContracts.lendingPoolConfigurator.setFarmingPctDrift(tokenAddress, randomNumber);
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        deployedContracts.lendingPoolConfigurator.setProfitHandler(tokenAddress, tokenAddress);
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        deployedContracts.lendingPoolConfigurator.setVault(tokenAddress, tokenAddress);

        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_EMERGENCY_ADMIN));
        deployedContracts.lendingPoolConfigurator.rebalance(tokenAddress);

        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        deployedContracts.lendingPoolConfigurator
            .setReserveInterestRateStrategyAddress(tokenAddress, true, randomAddress);
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_EMERGENCY_ADMIN));
        deployedContracts.lendingPoolConfigurator.setPoolPause(true);
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        deployedContracts.lendingPoolConfigurator.updateFlashloanPremiumTotal(uint128(randomNumber));
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        deployedContracts.lendingPoolConfigurator
            .setRewarderForReserve(tokenAddress, true, randomAddress);
        vm.expectRevert(bytes(Errors.VL_CALLER_NOT_POOL_ADMIN));
        deployedContracts.lendingPoolConfigurator.setTreasury(tokenAddress, true, randomAddress);
    }

    function testSetReserveInterestRateStrategyAddress() public {
        address newInterestRateStrategy = address(
            new DefaultReserveInterestRateStrategy(
                deployedContracts.lendingPoolAddressesProvider,
                sStrat[0],
                sStrat[1],
                sStrat[2],
                sStrat[3]
            )
        );
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator
                .setReserveInterestRateStrategyAddress(
                    address(erc20Tokens[idx]), true, newInterestRateStrategy
                );
            DataTypes.ReserveData memory data =
                deployedContracts.lendingPool.getReserveData(address(erc20Tokens[idx]), true);
            assertEq(data.interestRateStrategyAddress, newInterestRateStrategy);
        }
    }

    function testSetPause(uint256 idx) public {
        idx = bound(idx, 0, 3);
        TokenTypes memory collateralType = TokenTypes({
            token: erc20Tokens[idx],
            aToken: commonContracts.aTokens[idx],
            debtToken: commonContracts.variableDebtTokens[idx]
        });

        uint256 amount = 10 ** collateralType.token.decimals();
        deal(address(collateralType.token), address(this), 10 * amount);
        collateralType.token.approve(address(deployedContracts.lendingPool), 10 * amount);
        deployedContracts.lendingPool
            .deposit(address(collateralType.token), true, amount, address(this));
        deployedContracts.lendingPool
            .borrow(address(collateralType.token), true, amount / 10, address(this));

        vm.expectEmit(false, false, false, false);
        emit Paused();
        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.setPoolPause(true);
        assertEq(deployedContracts.lendingPool.paused(), true);

        /* pool paused - new deposits/borrows shouldn't be possible */
        vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
        deployedContracts.lendingPool
            .deposit(address(collateralType.token), true, amount, address(this));
        vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
        deployedContracts.lendingPool
            .borrow(address(collateralType.token), true, amount / 10, address(this));
        /* repay and withdraw actions shall pass */
        vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
        deployedContracts.lendingPool
            .repay(address(collateralType.token), true, amount / 10, address(this));
        vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
        deployedContracts.lendingPool
            .withdraw(address(collateralType.token), true, amount, address(this));

        vm.expectEmit(false, false, false, false);
        emit Unpaused();
        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.setPoolPause(false);
        assertEq(deployedContracts.lendingPool.paused(), false);

        deployedContracts.lendingPool
            .deposit(address(collateralType.token), true, amount, address(this));
        deployedContracts.lendingPool
            .borrow(address(collateralType.token), true, amount / 10, address(this));
        /* repay and withdraw actions shall pass */
        deployedContracts.lendingPool
            .repay(address(collateralType.token), true, amount / 10, address(this));
        deployedContracts.lendingPool
            .withdraw(address(collateralType.token), true, amount, address(this));
    }

    function testGetTotalManagedAssets() public {
        uint256 amount = 1e18;
        address user = makeAddr("user");
        for (uint32 idx = 0; idx < commonContracts.aTokens.length; idx++) {
            deal(address(erc20Tokens[idx]), address(this), amount);
            uint256 _userGrainBalanceBefore = commonContracts.aTokens[idx].balanceOf(address(user));
            uint256 _thisBalanceTokenBefore = erc20Tokens[idx].balanceOf(address(this));

            /* Deposit on behalf of user */
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amount);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), true, amount, user);
            assertEq(_thisBalanceTokenBefore, erc20Tokens[idx].balanceOf(address(this)) + amount);
            assertEq(
                _userGrainBalanceBefore + amount,
                commonContracts.aTokens[idx].balanceOf(address(user))
            );
            assertEq(
                deployedContracts.lendingPoolConfigurator
                    .getTotalManagedAssets(address(commonContracts.aTokens[idx])),
                amount
            );
        }
    }

    function testUpdateFlashloanPremiumTotal(uint128 flashLoanPremiumTotal) public {
        vm.assume(flashLoanPremiumTotal <= 1e4);
        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.updateFlashloanPremiumTotal(flashLoanPremiumTotal);
        assertEq(deployedContracts.lendingPool.FLASHLOAN_PREMIUM_TOTAL(), flashLoanPremiumTotal);
    }

    function testUpdateFlashloanPremiumTotalNegative(uint128 flashLoanPremiumTotal) public {
        vm.assume(flashLoanPremiumTotal > 1e4);
        vm.prank(admin);
        vm.expectRevert(bytes(Errors.VL_FLASHLOAN_PREMIUM_INVALID));
        deployedContracts.lendingPoolConfigurator.updateFlashloanPremiumTotal(flashLoanPremiumTotal);
    }

    function testSetRewarderForReserve() public {
        address newRewarder = makeAddr("newRewarder");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator
                .setRewarderForReserve(address(erc20Tokens[idx]), true, newRewarder);
            assertEq(address(commonContracts.aTokens[idx].getIncentivesController()), newRewarder);
            assertEq(
                address(commonContracts.variableDebtTokens[idx].getIncentivesController()),
                newRewarder
            );
        }
    }

    function testSetTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator
                .setTreasury(address(erc20Tokens[idx]), true, newTreasury);
            assertEq(commonContracts.aTokens[idx].RESERVE_TREASURY_ADDRESS(), newTreasury);
        }
    }

    function testConfigureWithoutLiquidationThreshold() public {
        vm.startPrank(admin);
        deployedContracts.lendingPoolConfigurator.configureReserveAsCollateral(USDC, true, 0, 0, 0);
        deployedContracts.lendingPoolConfigurator.configureReserveAsCollateral(WBTC, true, 0, 0, 0);
        deployedContracts.lendingPoolConfigurator.configureReserveAsCollateral(WETH, true, 0, 0, 0);
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

    function testEnableDisableFlashloans() public {
        bool[] memory reserveTypes = new bool[](1);
        address[] memory tokenAddresses = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);
        uint256[] memory balanceBefore = new uint256[](1);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
        {
            uint256 amountToDeposit = IERC20(tokens[USDC_OFFSET]).balanceOf(address(this));
            erc20Tokens[USDC_OFFSET].approve(
                address(deployedContracts.lendingPool), amountToDeposit
            );
            deployedContracts.lendingPool
                    .deposit(
                    address(erc20Tokens[USDC_OFFSET]), true, amountToDeposit, address(this)
                );
            reserveTypes[0] = true;
            tokenAddresses[0] = address(erc20Tokens[USDC_OFFSET]);
            amounts[0] = IERC20(tokens[USDC_OFFSET]).balanceOf(address(this)) / 2;
            modes[0] = 0;
            balanceBefore[0] = IERC20(tokens[USDC_OFFSET]).balanceOf(address(this));
        }

        ILendingPool.FlashLoanParams memory flashloanParams = ILendingPool.FlashLoanParams(
            address(this), tokenAddresses, reserveTypes, address(this)
        );

        bytes memory params = abi.encode(balanceBefore, address(this));

        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit DisableFlashloan(USDC, true);
        deployedContracts.lendingPoolConfigurator.disableFlashloan(USDC, true);

        vm.expectEmit(true, true, true, true);
        emit DisableFlashloan(WETH, false);
        deployedContracts.lendingPoolConfigurator.disableFlashloan(WETH, false);
        vm.stopPrank();

        vm.expectRevert(bytes(Errors.VL_FLASHLOAN_DISABLED));
        deployedContracts.lendingPool.flashLoan(flashloanParams, amounts, modes, params);

        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit EnableFlashloan(USDC, true);
        deployedContracts.lendingPoolConfigurator.enableFlashloan(USDC, true);

        vm.expectEmit(true, true, true, true);
        emit EnableFlashloan(WETH, false);
        deployedContracts.lendingPoolConfigurator.enableFlashloan(WETH, false);
        vm.stopPrank();

        // deal(address(erc20Tokens[USDC_OFFSET]), address(this), 10 * amount);
        deployedContracts.lendingPool.flashLoan(flashloanParams, amounts, modes, params);
    }

    struct UserAccountData {
        uint256 totalCollateralETH;
        uint256 totalDebtETH;
        uint256 availableBorrowsETH;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
    }

    function testLpUniqueTokensReinitialization(uint256 offset, uint256 amount) public {
        offset = bound(offset, 0, 3);
        TokenParams memory collateralTokenParams = TokenParams(
            erc20Tokens[offset],
            commonContracts.aTokensWrapper[offset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[offset]))
        );
        amount = bound(
            amount,
            10 ** (collateralTokenParams.token.decimals() - 2), // 0,01
            10 ** (collateralTokenParams.token.decimals() + 3) // 1000
        );
        deal(address(collateralTokenParams.token), address(this), amount);
        console2.log("Deposit asset to the mainPool");
        fixture_deposit(
            collateralTokenParams.token,
            collateralTokenParams.aToken,
            address(this),
            address(this),
            amount
        );
        UserAccountData memory beforeUserAccountData;
        (
            beforeUserAccountData.totalCollateralETH,
            beforeUserAccountData.totalDebtETH,
            beforeUserAccountData.availableBorrowsETH,
            beforeUserAccountData.currentLiquidationThreshold,
            beforeUserAccountData.ltv,
            beforeUserAccountData.healthFactor
        ) = deployedContracts.asteraDataProvider.getLpUserAccountData(address(this));

        {
            console2.log("Reinit the asset");
            ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
                new ILendingPoolConfigurator.InitReserveInput[](1);
            string memory tmpSymbol = ERC20(tokens[offset]).symbol();
            string memory tmpName = ERC20(tokens[offset]).name();

            address interestStrategy = isStableStrategy[offset] != false
                ? configAddresses.stableStrategy
                : configAddresses.volatileStrategy;
            initInputParams[0] = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: address(commonContracts.aToken),
                variableDebtTokenImpl: address(commonContracts.variableDebtToken),
                underlyingAssetDecimals: ERC20(tokens[offset]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: tokens[offset],
                reserveType: reserveTypes[offset],
                treasury: configAddresses.treasury,
                incentivesController: configAddresses.rewarder,
                underlyingAssetName: tmpSymbol,
                aTokenName: string.concat("Astera ", tmpSymbol),
                aTokenSymbol: string.concat("cl", tmpSymbol),
                variableDebtTokenName: string.concat("Astera variable debt bearing ", tmpSymbol),
                variableDebtTokenSymbol: string.concat("variableDebt", tmpSymbol),
                params: "0x10"
            });

            console2.log("BatchInitReserve");
            vm.startPrank(address(deployedContracts.lendingPoolAddressesProvider.getPoolAdmin()));
            vm.expectRevert(bytes(Errors.RL_RESERVE_ALREADY_INITIALIZED));
            deployedContracts.lendingPoolConfigurator.batchInitReserve(initInputParams);
            vm.stopPrank();
        }

        UserAccountData memory afterUserAccountData;
        (
            afterUserAccountData.totalCollateralETH,
            afterUserAccountData.totalDebtETH,
            afterUserAccountData.availableBorrowsETH,
            afterUserAccountData.currentLiquidationThreshold,
            afterUserAccountData.ltv,
            afterUserAccountData.healthFactor
        ) = deployedContracts.asteraDataProvider.getLpUserAccountData(address(this));

        assertEq(afterUserAccountData.totalCollateralETH, beforeUserAccountData.totalCollateralETH);
        assertEq(afterUserAccountData.totalDebtETH, beforeUserAccountData.totalDebtETH);
        assertEq(
            afterUserAccountData.availableBorrowsETH, beforeUserAccountData.availableBorrowsETH
        );
        assertEq(
            afterUserAccountData.currentLiquidationThreshold,
            beforeUserAccountData.currentLiquidationThreshold
        );
        assertEq(afterUserAccountData.ltv, beforeUserAccountData.ltv);
        assertEq(afterUserAccountData.healthFactor, beforeUserAccountData.healthFactor);
    }
}
