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
        mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, tokensWhales, address(this));
    }

    function testAccessControl_NotLiquidityPool() public {
        address addr = makeAddr("RandomAddress");
        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            aTokens[idx].mint(address(this), 1, 1);
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            aTokens[idx].burn(admin, admin, 1, 1);
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            aTokens[idx].transferOnLiquidation(admin, addr, 1);
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            aTokens[idx].transferUnderlyingTo(address(this), 1);
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            aTokens[idx].setVault(address(mockedVaults[idx]));
        }
    }

    function testMinting(uint256 maxValToMint) public {
        uint8 nrOfIterations = 20;
        maxValToMint = bound(maxValToMint, nrOfIterations, 20_000_000);

        uint256 granuality = maxValToMint / nrOfIterations;
        maxValToMint = maxValToMint - (maxValToMint % granuality); // accept only multiplicity of 20
        vm.startPrank(address(deployedContracts.lendingPool));
        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            for (uint256 cnt = 0; cnt < maxValToMint; cnt += granuality) {
                aTokens[idx].mint(address(this), granuality, 1);
            }
            assertEq(aTokens[idx].balanceOf(address(this)), maxValToMint.rayDiv(1));
            aTokens[idx].mint(address(this), maxValToMint, 1);
            assertEq(aTokens[idx].balanceOf(address(this)), 2 * maxValToMint.rayDiv(1));
            assertEq(aTokens[idx].totalSupply(), 2 * maxValToMint.rayDiv(1));
        }
        vm.stopPrank();
    }

    function testBurning(uint256 maxValToBurn) public {
        uint8 nrOfIterations = 20;
        maxValToBurn = bound(maxValToBurn, nrOfIterations, 2_000_000);
        uint256 granuality = maxValToBurn / nrOfIterations;
        maxValToBurn = maxValToBurn - (maxValToBurn % granuality); // accept only multiplicity of 20

        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), 2 * maxValToBurn);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), false, 2 * maxValToBurn, address(this));
            for (uint256 cnt = 0; cnt < maxValToBurn; cnt += granuality) {
                deployedContracts.lendingPool.withdraw(address(erc20Tokens[idx]), false, granuality, address(this));
            }
            assertEq(aTokens[idx].balanceOf(address(this)), maxValToBurn);
            deployedContracts.lendingPool.withdraw(address(erc20Tokens[idx]), false, maxValToBurn, address(this));
            assertEq(aTokens[idx].balanceOf(address(this)), 0);
            assertEq(aTokens[idx].totalSupply(), 0);
        }
    }

    function testDepositTransferBorrow(uint256 amount) public {
        address user = makeAddr("user");

        uint8 nrOfIterations = 20;
        amount = bound(amount, nrOfIterations, 20_000_000);
        uint256 granuality = amount / nrOfIterations;
        vm.assume(amount % granuality == 0);

        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            uint256 _grainUserBalanceBefore = aTokens[idx].balanceOf(user);

            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), 2 * amount);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), false, 2 * amount, address(this));
            uint256 _grainThisBalanceBefore = aTokens[idx].balanceOf(address(this));
            for (uint256 cnt = 0; cnt < amount; cnt += granuality) {
                aTokens[idx].transfer(user, granuality);
            }

            /* Token balance of this shall be less by {amount} as after transfer */
            assertEq(_grainThisBalanceBefore - amount, aTokens[idx].balanceOf(address(this)));
            /* AToken balance of this shall be greater by {amount} as after transfer */
            assertEq(_grainUserBalanceBefore + amount, aTokens[idx].balanceOf(user));
            aTokens[idx].transfer(user, amount);
            assertEq(_grainThisBalanceBefore - 2 * amount, aTokens[idx].balanceOf(address(this)));
            assertEq(aTokens[idx].balanceOf(user), _grainUserBalanceBefore + 2 * amount);

            vm.startPrank(user);
            uint256 amountToBorrow;
            (, uint256 ltv,,,,,,,) =
                deployedContracts.protocolDataProvider.getReserveConfigurationData(address(erc20Tokens[idx]), false);
            amountToBorrow = ((ltv * 2 * amount) / 10_000) - 1; // Issue: Must be -1 somewhere we are losing precision ?

            deployedContracts.lendingPool.borrow(address(erc20Tokens[idx]), false, amountToBorrow, user);
            assertEq(erc20Tokens[idx].balanceOf(user), amountToBorrow);
            assertEq(aTokens[idx].balanceOf(user), _grainUserBalanceBefore + 2 * amount);
            vm.stopPrank();
        }
    }

    function testDepositTransferBorrow_AllTokens() public {
        address user = makeAddr("user");

        uint256 amountToTransfer;
        uint256 amountToBorrow;

        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            uint32 nextTokenIndex = (idx + 1) % uint32(aTokens.length);
            uint256 _userGrainBalanceBefore = aTokens[idx].balanceOf(user);
            uint256 _userBalanceNextTokenBefore = erc20Tokens[nextTokenIndex].balanceOf(user);
            uint256 _thisBalanceGrainTokenBefore = aTokens[idx].balanceOf(address(this));
            uint256 _thisBalanceGrainNextTokenBefore = aTokens[nextTokenIndex].balanceOf(address(this));

            uint256 currentAssetMaxBorrowValue;
            {
                amountToTransfer = (erc20Tokens[idx].balanceOf(address(this))) / 1000;
                uint256 currentAssetPrice = oracle.getAssetPrice(address(erc20Tokens[idx]));
                uint256 nextTokenAssetPrice = oracle.getAssetPrice(address(erc20Tokens[nextTokenIndex]));
                (, uint256 currentAssetLtv,,,,,,,) =
                    deployedContracts.protocolDataProvider.getReserveConfigurationData(address(erc20Tokens[idx]), false);

                uint256 currentAssetDepositValue = amountToTransfer * currentAssetPrice / 10 ** PRICE_FEED_DECIMALS;
                currentAssetMaxBorrowValue = currentAssetDepositValue * currentAssetLtv / 10_000;
                uint256 amountToBorrowRaw =
                    (currentAssetMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / nextTokenAssetPrice;
                amountToBorrow = (erc20Tokens[nextTokenIndex].decimals() > erc20Tokens[idx].decimals())
                    ? amountToBorrowRaw * (10 ** (erc20Tokens[nextTokenIndex].decimals() - erc20Tokens[idx].decimals()))
                    : amountToBorrowRaw / (10 ** (erc20Tokens[idx].decimals() - erc20Tokens[nextTokenIndex].decimals()));

                // console.log("amountToTransfer: ", amountToTransfer);
                // console.log("currentAssetPrice: ", currentAssetPrice);
                // console.log("nextTokenAssetPrice: ", nextTokenAssetPrice);
                // console.log("currentAssetDepositValue: ", currentAssetDepositValue);
                // console.log("currentAssetMaxBorrowValue: ", currentAssetMaxBorrowValue);
                // console.log("amountToBorrow: ", amountToBorrow);
            }

            /* Deposit to get gToken and transfer to other user which will borrow against it */
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amountToTransfer);
            console.log("Symbol: ", erc20Tokens[idx].symbol());
            console.log("Amount to transfer: ", amountToTransfer);
            console.log("Balance>>>>>>>>>>>: ", erc20Tokens[idx].balanceOf(address(this)));
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), false, amountToTransfer, address(this));
            aTokens[idx].transfer(user, amountToTransfer);

            /* Must deposit callateral of next token of the same type to have sth to borrow */
            erc20Tokens[nextTokenIndex].approve(address(deployedContracts.lendingPool), amountToBorrow);
            console.log("Symbol: ", erc20Tokens[nextTokenIndex].symbol());
            console.log("Amount to borrow: ", amountToBorrow);
            console.log("Balance>>>>>>>>>: ", erc20Tokens[nextTokenIndex].balanceOf(address(this)));
            deployedContracts.lendingPool.deposit(
                address(erc20Tokens[nextTokenIndex]), false, amountToBorrow, address(this)
            );

            vm.startPrank(user);
            deployedContracts.lendingPool.borrow(address(erc20Tokens[nextTokenIndex]), false, amountToBorrow, user);
            vm.stopPrank();

            /* User shall have borrowed erc20 tokens */
            assertEq(_userBalanceNextTokenBefore + amountToBorrow, erc20Tokens[nextTokenIndex].balanceOf(user));
            /* User shall have gTokens corresponding with transfer */
            assertEq(_userGrainBalanceBefore + amountToTransfer, aTokens[idx].balanceOf(user));
            /* This shall have gTokens corresponding with second deposit */
            assertEq(
                _thisBalanceGrainNextTokenBefore + amountToBorrow, aTokens[nextTokenIndex].balanceOf(address(this))
            );
            /* This shall not have gTokens corresponding with first deposit */
            assertEq(_thisBalanceGrainTokenBefore, aTokens[idx].balanceOf(address(this)));
        }
    }
}
