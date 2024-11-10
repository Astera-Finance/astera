// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract LendingPoolConfiguratorTest is Common {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 constant MAX_VALID_RESERVE_FACTOR = 65535;
    uint256 constant MAX_VALID_DEPOSIT_CAP = 256;

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

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    function setUp() public {
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
            address(aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );

        mockedVaults = fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        // fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function testDisableBorrowingOnReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit BorrowingDisabledOnReserve(address(erc20Tokens[idx]), true);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.disableBorrowingOnReserve(
                address(erc20Tokens[idx]), true
            );
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testActivateReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveActivated(address(erc20Tokens[idx]), true);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.activateReserve(
                address(erc20Tokens[idx]), true
            );
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testDeactivateReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveDeactivated(address(erc20Tokens[idx]), true);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.deactivateReserve(
                address(erc20Tokens[idx]), true
            );
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testFreezeReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveFrozen(address(erc20Tokens[idx]), true);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.freezeReserve(address(erc20Tokens[idx]), true);
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testUnfreezeReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveUnfrozen(address(erc20Tokens[idx]), true);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.unfreezeReserve(
                address(erc20Tokens[idx]), true
            );
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testSetReserveFactor_Positive(uint256 validReserveFactor) public {
        validReserveFactor = bound(validReserveFactor, 0, MAX_VALID_RESERVE_FACTOR);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, false);
            emit ReserveFactorChanged(address(erc20Tokens[idx]), true, validReserveFactor);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.setReserveFactor(
                address(erc20Tokens[idx]), true, validReserveFactor
            );
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testSetReserveFactor_Negative(uint256 invalidReserveFactor) public {
        invalidReserveFactor =
            bound(invalidReserveFactor, MAX_VALID_RESERVE_FACTOR + 1, type(uint256).max);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectRevert(bytes(Errors.RC_INVALID_RESERVE_FACTOR));
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.setReserveFactor(
                address(erc20Tokens[idx]), true, invalidReserveFactor
            );
        }
    }

    function testSetDepositCap_Positive(uint256 validDepositCap) public {
        validDepositCap = bound(validDepositCap, 0, MAX_VALID_DEPOSIT_CAP - 1);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, false);
            emit ReserveDepositCapChanged(address(erc20Tokens[idx]), true, validDepositCap);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.setDepositCap(
                address(erc20Tokens[idx]), true, validDepositCap
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
            deployedContracts.lendingPoolConfigurator.setDepositCap(
                address(erc20Tokens[idx]), false, invalidDepositCap
            );
        }
    }

    function testPoolInteractions(uint256 farmingPct, uint256 claimingThreshold) public {
        address aTokenAddress = address(aTokens[0]);

        address lendingPoolAddr = address(deployedContracts.lendingPool);

        vm.startPrank(admin);
        /* set vault positive */
        vm.expectCall(
            lendingPoolAddr,
            abi.encodeCall(
                deployedContracts.lendingPool.setVault, (aTokenAddress, address(mockedVaults[0]))
            )
        );
        deployedContracts.lendingPoolConfigurator.setVault(aTokenAddress, address(mockedVaults[0]));

        /* set vault negative - 84 */
        vm.expectRevert(bytes("84"));
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
        vm.expectRevert(bytes("82"));
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
        deployedContracts.lendingPoolConfigurator.setClaimingThreshold(
            aTokenAddress, claimingThreshold
        );

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
        vm.expectRevert(bytes("82"));
        deployedContracts.lendingPoolConfigurator.setFarmingPctDrift(aTokenAddress, farmingPct);

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

        /* set profit handler negative - 83 */
        profitHandler = address(0);
        vm.expectRevert(bytes("83"));
        deployedContracts.lendingPoolConfigurator.setProfitHandler(aTokenAddress, profitHandler);

        vm.stopPrank();
    }

    function testAccessControlForPoolInteractions() public {
        address tokenAddress = makeAddr("tokenAddress");
        address randomAddress = makeAddr("randomAddress");
        uint256 randomNumber;
        randomNumber = bound(randomNumber, 0, type(uint256).max);
        /* access controls */
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setFarmingPct(tokenAddress, randomNumber);
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setClaimingThreshold(tokenAddress, randomNumber);
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setFarmingPctDrift(tokenAddress, randomNumber);
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setProfitHandler(tokenAddress, tokenAddress);
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setVault(tokenAddress, tokenAddress);
        vm.expectRevert(bytes("76"));
        deployedContracts.lendingPoolConfigurator.rebalance(tokenAddress);

        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setReserveInterestRateStrategyAddress(
            tokenAddress, true, randomAddress
        );
        vm.expectRevert(bytes("76"));
        deployedContracts.lendingPoolConfigurator.setPoolPause(true);
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.updateFlashloanPremiumTotal(uint128(randomNumber));
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setRewarderForReserve(
            tokenAddress, true, randomAddress
        );
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setTreasury(tokenAddress, true, randomAddress);
    }

    function testSetReserveInterestRateStrategyAddress() public {
        address newInterestRateStrategy = makeAddr("newInterestRateStrategy");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.setReserveInterestRateStrategyAddress(
                address(erc20Tokens[idx]), true, newInterestRateStrategy
            );
            DataTypes.ReserveData memory data =
                deployedContracts.lendingPool.getReserveData(address(erc20Tokens[idx]), true);
            assertEq(data.interestRateStrategyAddress, newInterestRateStrategy);
        }
    }

    function testSetPause() public {
        vm.expectEmit(false, false, false, false);
        emit Paused();
        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.setPoolPause(true);
        assertEq(deployedContracts.lendingPool.paused(), true);

        vm.expectEmit(false, false, false, false);
        emit Unpaused();
        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.setPoolPause(false);
        assertEq(deployedContracts.lendingPool.paused(), false);
    }

    function testGetTotalManagedAssets() public {
        uint256 amount = 1e18;
        address user = makeAddr("user");
        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            deal(address(erc20Tokens[idx]), address(this), amount);
            uint256 _userGrainBalanceBefore = aTokens[idx].balanceOf(address(user));
            uint256 _thisBalanceTokenBefore = erc20Tokens[idx].balanceOf(address(this));

            /* Deposit on behalf of user */
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amount);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), true, amount, user);
            assertEq(_thisBalanceTokenBefore, erc20Tokens[idx].balanceOf(address(this)) + amount);
            assertEq(_userGrainBalanceBefore + amount, aTokens[idx].balanceOf(address(user)));
            assertEq(
                deployedContracts.lendingPoolConfigurator.getTotalManagedAssets(
                    address(aTokens[idx])
                ),
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
        vm.expectRevert(bytes(Errors.LPC_FLASHLOAN_PREMIUM_INVALID));
        deployedContracts.lendingPoolConfigurator.updateFlashloanPremiumTotal(flashLoanPremiumTotal);
    }

    function testSetRewarderForReserve() public {
        address newRewarder = makeAddr("newRewarder");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.setRewarderForReserve(
                address(erc20Tokens[idx]), true, newRewarder
            );
            assertEq(address(aTokens[idx].getIncentivesController()), newRewarder);
            assertEq(address(variableDebtTokens[idx].getIncentivesController()), newRewarder);
        }
    }

    function testSetTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.setTreasury(
                address(erc20Tokens[idx]), true, newTreasury
            );
            assertEq(aTokens[idx].RESERVE_TREASURY_ADDRESS(), newTreasury);
        }
    }
}
