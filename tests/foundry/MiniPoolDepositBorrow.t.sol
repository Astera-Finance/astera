// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolFixtures.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

import "forge-std/StdUtils.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract MiniPoolDepositBorrowTest is MiniPoolFixtures {
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
}
