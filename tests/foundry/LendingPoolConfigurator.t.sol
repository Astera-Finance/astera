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
        address indexed asset, bool reserveType, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus
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
    event ReserveInterestRateStrategyChanged(address indexed asset, bool reserveType, address strategy);
    event ATokenUpgraded(
        address indexed asset, address indexed proxy, address indexed implementation, bool reserveType
    );
    event VariableDebtTokenUpgraded(address indexed asset, address indexed proxy, address indexed implementation);

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider,
            deployedContracts.protocolDataProvider
        );
        (grainTokens, variableDebtTokens) =
            fixture_getGrainTokensAndDebts(tokens, deployedContracts.protocolDataProvider);
        mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        // fixture_transferTokensToTestContract(erc20Tokens, tokensWhales, address(this));
    }

    function testActivateReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveActivated(address(erc20Tokens[idx]), false);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.activateReserve(address(erc20Tokens[idx]), false);
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testDeactivateReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveDeactivated(address(erc20Tokens[idx]), false);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.deactivateReserve(address(erc20Tokens[idx]), false);
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testFreezeReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveFrozen(address(erc20Tokens[idx]), false);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.freezeReserve(address(erc20Tokens[idx]), false);
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testUnfreezeReserve() public {
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, true);
            emit ReserveUnfrozen(address(erc20Tokens[idx]), false);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.unfreezeReserve(address(erc20Tokens[idx]), false);
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testSetReserveFactor_Positive(uint256 validReserveFactor) public {
        validReserveFactor = bound(validReserveFactor, 0, MAX_VALID_RESERVE_FACTOR);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, false);
            emit ReserveFactorChanged(address(erc20Tokens[idx]), false, validReserveFactor);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.setReserveFactor(
                address(erc20Tokens[idx]), false, validReserveFactor
            );
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testSetReserveFactor_Negative(uint256 invalidReserveFactor) public {
        invalidReserveFactor = bound(invalidReserveFactor, MAX_VALID_RESERVE_FACTOR + 1, type(uint256).max);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectRevert(bytes(Errors.RC_INVALID_RESERVE_FACTOR));
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.setReserveFactor(
                address(erc20Tokens[idx]), false, invalidReserveFactor
            );
        }
    }

    function testSetDepositCap_Positive(uint256 validDepositCap) public {
        validDepositCap = bound(validDepositCap, 0, MAX_VALID_DEPOSIT_CAP);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectEmit(true, false, false, false);
            emit ReserveDepositCapChanged(address(erc20Tokens[idx]), false, validDepositCap);
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.setDepositCap(address(erc20Tokens[idx]), false, validDepositCap);
            // DataTypes.ReserveConfigurationMap memory currentConfig =
            //     deployedContracts.lendingPool.getConfiguration(address(erc20Tokens[idx]), false);
            // assertEq(currentConfig.getReserveFactor(), validReserveFactor);
        }
    }

    function testSetDepositCap_Negative(uint256 invalidDepositCap) public {
        invalidDepositCap = bound(invalidDepositCap, MAX_VALID_DEPOSIT_CAP + 1, type(uint256).max);
        for (uint32 idx; idx < erc20Tokens.length; idx++) {
            vm.expectRevert(bytes(Errors.RC_INVALID_DEPOSIT_CAP));
            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.setDepositCap(address(erc20Tokens[idx]), false, invalidDepositCap);
        }
    }

    function testPoolInteractions(uint256 farmingPct, uint256 claimingThreshold) public {
        address aTokenAddress = address(grainTokens[0]);

        address lendingPoolAddr = address(deployedContracts.lendingPool);

        vm.startPrank(admin);
        /* set vault positive */
        vm.expectCall(
            lendingPoolAddr,
            abi.encodeCall(deployedContracts.lendingPool.setVault, (aTokenAddress, address(mockedVaults[0])))
        );
        deployedContracts.lendingPoolConfigurator.setVault(aTokenAddress, address(mockedVaults[0]));

        /* set vault negative - 84 */
        vm.expectRevert(bytes("84"));
        deployedContracts.lendingPoolConfigurator.setVault(aTokenAddress, address(0));

        /* set farming pct positive */
        farmingPct = bound(farmingPct, 0, 10000);
        vm.expectCall(
            lendingPoolAddr, abi.encodeCall(deployedContracts.lendingPool.setFarmingPct, (aTokenAddress, farmingPct))
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
            abi.encodeCall(deployedContracts.lendingPool.setClaimingThreshold, (aTokenAddress, claimingThreshold))
        );
        deployedContracts.lendingPoolConfigurator.setClaimingThreshold(aTokenAddress, claimingThreshold);

        /* set farming pct drift positive */
        farmingPct = bound(farmingPct, 0, 10000);
        vm.expectCall(
            lendingPoolAddr,
            abi.encodeCall(deployedContracts.lendingPool.setFarmingPctDrift, (aTokenAddress, farmingPct))
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
            abi.encodeCall(deployedContracts.lendingPool.setProfitHandler, (aTokenAddress, profitHandler))
        );
        deployedContracts.lendingPoolConfigurator.setProfitHandler(aTokenAddress, profitHandler);

        /* set profit handler negative - 83 */
        profitHandler = address(0);
        vm.expectRevert(bytes("83"));
        deployedContracts.lendingPoolConfigurator.setProfitHandler(aTokenAddress, profitHandler);

        vm.stopPrank();
    }

    function testAccessControlForPoolInteractions() public {
        address aTokenAddress = makeAddr("aTokenAddress");
        uint256 randomNumber;
        randomNumber = bound(randomNumber, 0, type(uint256).max);
        /* access controls */
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setFarmingPct(aTokenAddress, randomNumber);
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setClaimingThreshold(aTokenAddress, randomNumber);
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setFarmingPctDrift(aTokenAddress, randomNumber);
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setProfitHandler(aTokenAddress, aTokenAddress);
        vm.expectRevert(bytes("33"));
        deployedContracts.lendingPoolConfigurator.setVault(aTokenAddress, aTokenAddress);
        vm.expectRevert(bytes("76"));
        deployedContracts.lendingPoolConfigurator.rebalance(aTokenAddress);
    }
}
