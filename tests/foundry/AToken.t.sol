// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

contract ATokenTest is Common {
    using WadRayMath for uint256;

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
        fixture_transferTokensToTestContract(erc20Tokens, tokensWhales, address(this));
    }

    function testAccessControl_NotLiquidityPool() public {
        address addr = makeAddr("RandomAddress");
        for (uint32 idx = 0; idx < grainTokens.length; idx++) {
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            grainTokens[idx].mint(address(this), 1, 1);
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            grainTokens[idx].burn(admin, admin, 1, 1);
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            grainTokens[idx].transferOnLiquidation(admin, addr, 1);
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            grainTokens[idx].transferUnderlyingTo(address(this), 1);
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            grainTokens[idx].setVault(address(mockedVaults[idx]));
        }
    }

    function testMinting(uint256 maxValToMint) public {
        uint8 nrOfIterations = 20;
        maxValToMint = bound(maxValToMint, nrOfIterations, 20_000_000);

        uint256 granuality = maxValToMint / nrOfIterations;
        maxValToMint = maxValToMint - (maxValToMint % granuality); // accept only multiplicity of 20
        console.log("maxValToMint: ", maxValToMint);
        vm.startPrank(address(deployedContracts.lendingPool));
        for (uint32 idx = 0; idx < grainTokens.length; idx++) {
            for (uint256 cnt = 0; cnt < maxValToMint; cnt += granuality) {
                grainTokens[idx].mint(address(this), granuality, 1);
                console.log("minted in: ", granuality);
            }
            assertEq(grainTokens[idx].balanceOf(address(this)), maxValToMint.rayDiv(1));
            grainTokens[idx].mint(address(this), maxValToMint, 1);
            console.log("minted out: ", maxValToMint);
            assertEq(grainTokens[idx].balanceOf(address(this)), 2 * maxValToMint.rayDiv(1));
            assertEq(grainTokens[idx].totalSupply(), 2 * maxValToMint.rayDiv(1));
        }
        vm.stopPrank();
    }

    function testBurning(uint256 maxValToBurn) public {
        uint8 nrOfIterations = 20;
        maxValToBurn = bound(maxValToBurn, nrOfIterations, 20_000_000);
        uint256 granuality = maxValToBurn / nrOfIterations;
        maxValToBurn = maxValToBurn - (maxValToBurn % granuality); // accept only multiplicity of 20
        console.log("maxValToBurn: ", maxValToBurn);

        for (uint32 idx = 0; idx < grainTokens.length; idx++) {
            console.log("Depositing... ", maxValToBurn);
            console.log("1. Balance: ", grainTokens[idx].balanceOf(address(this)));
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), 2 * maxValToBurn);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), false, 2 * maxValToBurn, address(this));
            console.log("2. Balance: ", grainTokens[idx].balanceOf(address(this)));
            // vm.startPrank(address(deployedContracts.lendingPool));
            // grainTokens[idx].mint(address(this), 2 * maxValToBurn, 1);
            for (uint256 cnt = 0; cnt < maxValToBurn; cnt += granuality) {
                console.log("Burning in test... ", maxValToBurn);
                // grainTokens[idx].burn(address(deployedContracts.lendingPool), address(this), granuality, 1);
                deployedContracts.lendingPool.withdraw(address(erc20Tokens[idx]), false, granuality, address(this));
                console.log("burned in: ", granuality);
            }
            assertEq(grainTokens[idx].balanceOf(address(this)), maxValToBurn);
            deployedContracts.lendingPool.withdraw(address(erc20Tokens[idx]), false, maxValToBurn, address(this));
            console.log("burned out: ", maxValToBurn);
            assertEq(grainTokens[idx].balanceOf(address(this)), 0);
            assertEq(grainTokens[idx].totalSupply(), 0);
            // vm.stopPrank();
        }
    }

    function testDepositTransferBorrow(uint256 amount) public {
        address user = makeAddr("user");

        uint8 nrOfIterations = 20;
        amount = bound(amount, nrOfIterations, 20_000_000);
        uint256 granuality = amount / nrOfIterations;
        vm.assume(amount % granuality == 0);
        console.log("amount: ", amount);

        for (uint32 idx = 0; idx < grainTokens.length; idx++) {
            // uint256 _underlyingAmount = grainTokens[idx].underlyingAmount();
            uint256 _grainUserBalanceBefore = grainTokens[idx].balanceOf(user);

            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), 2 * amount);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), false, 2 * amount, address(this));
            uint256 _grainThisBalanceBefore = grainTokens[idx].balanceOf(address(this));
            for (uint256 cnt = 0; cnt < amount; cnt += granuality) {
                grainTokens[idx].transfer(user, granuality);
                console.log("Deposited: ", grainTokens[idx].balanceOf(user));
                console.log("Deducted: ", grainTokens[idx].balanceOf(address(this)));
            }

            /* Token balance of this shall be less by {amount} as after transfer */
            console.log("Expected: ", _grainThisBalanceBefore - amount);
            console.log("Token balance of this shall be less by {amount} as after transfer");
            assertEq(_grainThisBalanceBefore - amount, grainTokens[idx].balanceOf(address(this)));
            /* AToken balance of this shall be greater by {amount} as after transfer */
            console.log("AToken balance of this shall be greater by {amount} as after transfer");
            assertEq(_grainUserBalanceBefore + amount, grainTokens[idx].balanceOf(user));
            grainTokens[idx].transfer(user, amount);
            assertEq(_grainThisBalanceBefore - 2 * amount, grainTokens[idx].balanceOf(address(this)));
            assertEq(grainTokens[idx].balanceOf(user), _grainUserBalanceBefore + 2 * amount);

            console.log("Borrowing: ", grainTokens[idx].balanceOf(user));
            vm.startPrank(user);
            uint256 amountToBorrow;
            (, uint256 ltv,,,,,,,) =
                deployedContracts.protocolDataProvider.getReserveConfigurationData(address(erc20Tokens[idx]), false);
            amountToBorrow = ((ltv * 2 * amount) / 10_000) - 1; // Issue: Must be -1 somewhere we are losing precision ?

            deployedContracts.lendingPool.borrow(address(erc20Tokens[idx]), false, amountToBorrow, user);
            assertEq(erc20Tokens[idx].balanceOf(user), amountToBorrow);
            assertEq(grainTokens[idx].balanceOf(user), _grainUserBalanceBefore + 2 * amount);
            vm.stopPrank();
        }
    }

    function testDepositTransferBorrow_AllCoins() public {
        address user = makeAddr("user");

        uint256 amountToTransfer;
        uint256 amountToBorrow;

        for (uint32 idx = 0; idx < grainTokens.length; idx++) {
            uint32 nextTokenIndex = (idx + 1) % uint32(grainTokens.length);
            console.log(">>>>> Idx: ", idx);
            console.log("Deposit: ", erc20Tokens[idx].symbol());
            console.log("Borrow: ", erc20Tokens[nextTokenIndex].symbol());
            uint256 _userGrainBalanceBefore = grainTokens[idx].balanceOf(user);
            uint256 _userBalanceNextTokenBefore = erc20Tokens[nextTokenIndex].balanceOf(user);
            uint256 _thisBalanceGrainTokenBefore = grainTokens[idx].balanceOf(address(this));
            uint256 _thisBalanceGrainNextTokenBefore = grainTokens[nextTokenIndex].balanceOf(address(this));

            uint256 currentAssetMaxBorrowValue;
            {
                amountToTransfer = (erc20Tokens[idx].balanceOf(address(this))) / grainTokens.length;
                uint256 currentAssetPrice = oracle.getAssetPrice(address(erc20Tokens[idx]));
                uint256 nextTokenAssetPrice = oracle.getAssetPrice(address(erc20Tokens[nextTokenIndex]));
                (, uint256 currentAssetLtv,,,,,,,) =
                    deployedContracts.protocolDataProvider.getReserveConfigurationData(address(erc20Tokens[idx]), false);

                uint256 currentAssetDepositValue = amountToTransfer * currentAssetPrice / 10 ** PRICE_FEED_DECIMALS;
                currentAssetMaxBorrowValue = currentAssetDepositValue * currentAssetLtv / 10_000;
                uint256 amountToBorrowRaw =
                    (currentAssetMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / nextTokenAssetPrice;
                amountToBorrow = (erc20Tokens[nextTokenIndex].decimals() > erc20Tokens[idx].decimals())
                    ? amountToBorrowRaw * (10 ** erc20Tokens[nextTokenIndex].decimals() / 10 ** erc20Tokens[idx].decimals())
                    : amountToBorrowRaw / (10 ** erc20Tokens[idx].decimals() / 10 ** erc20Tokens[nextTokenIndex].decimals());

                console.log("amountToTransfer: ", amountToTransfer);
                console.log("currentAssetPrice: ", currentAssetPrice);
                console.log("nextTokenAssetPrice: ", nextTokenAssetPrice);
                console.log("currentAssetDepositValue: ", currentAssetDepositValue);
                console.log("currentAssetMaxBorrowValue: ", currentAssetMaxBorrowValue);
                console.log("amountToBorrow: ", amountToBorrow);
            }

            /* Deposit to get gToken and transfer to other user which will borrow against it */
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amountToTransfer);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), false, amountToTransfer, address(this));
            console.log("Amount of aToken received: ", grainTokens[idx].balanceOf(address(this)));
            grainTokens[idx].transfer(user, amountToTransfer);

            /* Must deposit callateral of next token of the same type to have sth to borrow */
            erc20Tokens[nextTokenIndex].approve(address(deployedContracts.lendingPool), amountToBorrow);
            deployedContracts.lendingPool.deposit(
                address(erc20Tokens[nextTokenIndex]), false, amountToBorrow, address(this)
            );

            console.log("Borrowing: ", grainTokens[idx].balanceOf(address(this)));
            vm.startPrank(user);
            deployedContracts.lendingPool.borrow(address(erc20Tokens[nextTokenIndex]), false, amountToBorrow, user);
            vm.stopPrank();

            /* User shall have borrowed erc20 tokens */
            assertEq(_userBalanceNextTokenBefore + amountToBorrow, erc20Tokens[nextTokenIndex].balanceOf(user));
            /* User shall have gTokens corresponding with transfer */
            assertEq(_userGrainBalanceBefore + amountToTransfer, grainTokens[idx].balanceOf(user));
            /* This shall have gTokens corresponding with second deposit */
            assertEq(
                _thisBalanceGrainNextTokenBefore + amountToBorrow, grainTokens[nextTokenIndex].balanceOf(address(this))
            );
            /* This shall not have gTokens corresponding with first deposit */
            assertEq(_thisBalanceGrainTokenBefore, grainTokens[idx].balanceOf(address(this)));
        }
    }
}
