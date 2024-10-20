// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

contract ATokenNonRebasingTest is Common {
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.protocolDataProvider),
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
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function unbackedATokenMint_fixture() public {
        vm.startPrank(address(deployedContracts.lendingPool));
        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            aTokens[idx].mint(address(this), 1000e18, 2e27); // 2e27 == 2 => /2
        }
        vm.stopPrank();
    }

    function testViewFunctions() public {
        unbackedATokenMint_fixture();
        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            assertEq(aTokens[idx].name(), AToken(aTokens[idx].WRAPPER_ADDRESS()).name());
            assertEq(aTokens[idx].symbol(), AToken(aTokens[idx].WRAPPER_ADDRESS()).symbol());
            assertEq(aTokens[idx].decimals(), AToken(aTokens[idx].WRAPPER_ADDRESS()).decimals());
            assertEq(aTokens[idx].totalSupply(), AToken(aTokens[idx]).scaledTotalSupply());

            assertEq(
                aTokens[idx].totalSupply(), AToken(aTokens[idx].WRAPPER_ADDRESS()).totalSupply()
            );
            assertEq(
                aTokens[idx].balanceOf(address(this)),
                AToken(aTokens[idx].WRAPPER_ADDRESS()).balanceOf(address(this))
            );
        }
    }

    function testBasicShareTransfer() public {
        unbackedATokenMint_fixture();
        address user = makeAddr("user");
        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            aTokens[idx].transfer(user, 100e18);

            assertEq(aTokens[idx].balanceOf(user), 100e18);

            AToken(aTokens[idx].WRAPPER_ADDRESS()).transfer(user, 50e18);

            assertEq(aTokens[idx].balanceOf(user), 150e18);
        }
    }

    function testBasicShareAllowances() public {
        unbackedATokenMint_fixture();

        address user = makeAddr("user");

        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            AToken(aTokens[idx].WRAPPER_ADDRESS()).approve(user, 100e18);

            assertEq(AToken(aTokens[idx].WRAPPER_ADDRESS()).allowance(address(this), user), 100e18);
        }
    }

    function testBasicShareTransferFrom1() public {
        unbackedATokenMint_fixture();

        address user = makeAddr("user");

        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            AToken(aTokens[idx].WRAPPER_ADDRESS()).approve(user, 100e18);
            assertEq(
                AToken(aTokens[idx].WRAPPER_ADDRESS()).allowance(address(this), user), 100e18, "124"
            );

            vm.startPrank(user);
            AToken(aTokens[idx].WRAPPER_ADDRESS()).transferFrom(address(this), user, 50e18);
            vm.stopPrank();

            assertEq(aTokens[idx].balanceOf(user), 50e18);
        }
    }

    function testBasicShareTransferFromRevert() public {
        unbackedATokenMint_fixture();

        address user = makeAddr("user");

        for (uint32 idx = 0; idx < 1; /* aTokens.length */ idx++) {
            AToken(aTokens[idx].WRAPPER_ADDRESS()).approve(user, 100e18);

            vm.startPrank(user);
            ATokenNonRebasing aw = ATokenNonRebasing(aTokens[idx].WRAPPER_ADDRESS());

            vm.expectRevert();
            aw.transferFrom(address(this), user, 150e18);
            vm.stopPrank();

            assertEq(aTokens[idx].balanceOf(user), 0);
        }
    }

    function testShareTransfer2() public {
        address user = makeAddr("user");
        uint256 amt = 1000e6;

        erc20Tokens[0].approve(address(deployedContracts.lendingPool), amt * 10000);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[0]), true, amt, address(this));

        deal(address(erc20Tokens[1]), user, 10e8);

        vm.startPrank(user);
        erc20Tokens[1].approve(address(deployedContracts.lendingPool), 100e8);

        deployedContracts.lendingPool.deposit(address(erc20Tokens[1]), true, 1e8, address(user));

        deployedContracts.lendingPool.borrow(address(erc20Tokens[0]), true, amt, address(user));
        vm.stopPrank();

        assertEq(
            aTokens[0].scaledBalanceOf(address(this)),
            AToken(aTokens[0].WRAPPER_ADDRESS()).balanceOf(address(this))
        );

        skip(300 days);

        deployedContracts.lendingPool.deposit(address(erc20Tokens[0]), true, 1, address(this)); // update index

        /// now a share worth 155,19% more that the underlying.

        assertEq(
            aTokens[0].scaledBalanceOf(address(this)),
            AToken(aTokens[0].WRAPPER_ADDRESS()).balanceOf(address(this))
        );

        // test transfer share vs normal transfer.
        uint256 amt1 = 100e6;
        aTokens[0].transfer(user, amt1);
        assertEq(aTokens[0].balanceOf(user), amt1);
        AToken(aTokens[0].WRAPPER_ADDRESS()).transfer(user, amt1);
        assertApproxEqRel(
            aTokens[0].balanceOf(user),
            amt1
                + amt1 * aTokens[0].balanceOf(address(this))
                    / AToken(aTokens[0].WRAPPER_ADDRESS()).balanceOf(address(this)),
            1e13
        );
    }
}
