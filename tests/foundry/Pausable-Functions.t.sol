// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

contract PausableFunctionsTest is Common {
    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;
    DeployedMiniPoolContracts miniPoolContracts;
    address miniPool;

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
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
        (miniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            address(0)
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] = address(aTokens[idx - tokens.length]);
            }
        }

        miniPool =
            fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts, 0);

        vm.label(miniPool, "MiniPool");
    }

    function testLendingPoolFunctionsWhenPaused() public {
        uint256 amount;

        /* Pause Lending Pool */
        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.setPoolPause(true);

        for (uint8 idx = 0; idx < erc20Tokens.length; idx++) {
            amount = erc20Tokens[idx].balanceOf(address(this));
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amount);
            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            deployedContracts.lendingPool.deposit(
                address(erc20Tokens[idx]), false, amount, address(this)
            );

            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            deployedContracts.lendingPool.withdraw(
                address(erc20Tokens[idx]), false, amount, address(this)
            );

            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            deployedContracts.lendingPool.borrow(
                address(erc20Tokens[idx]), false, amount, address(this)
            );

            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            deployedContracts.lendingPool.repay(
                address(erc20Tokens[idx]), false, amount, address(this)
            );

            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            deployedContracts.lendingPool.liquidationCall(
                address(erc20Tokens[idx]),
                false,
                address(erc20Tokens[idx]),
                false,
                address(this),
                amount,
                false
            );

            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            deployedContracts.lendingPool.setUserUseReserveAsCollateral(
                address(erc20Tokens[idx]), false, true
            );

            address[] memory tokenAddresses = new address[](3);
            uint256[] memory balancesBefore = new uint256[](3);
            uint256[] memory amounts = new uint256[](3);
            uint256[] memory modes = new uint256[](3);
            ILendingPool.FlashLoanParams memory flashloanParams = ILendingPool.FlashLoanParams(
                address(this), tokenAddresses, reserveTypes, address(this)
            );
            bytes memory params = abi.encode(balancesBefore, address(this));
            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            deployedContracts.lendingPool.flashLoan(flashloanParams, amounts, modes, params);
        }
    }

    function testMiniPoolFunctionsWhenPaused() public {
        uint256 amount;

        vm.prank(admin);
        miniPoolContracts.miniPoolConfigurator.setPoolPause(true, IMiniPool(miniPool));

        for (uint8 idx = 0; idx < erc20Tokens.length; idx++) {
            amount = erc20Tokens[idx].balanceOf(address(this));
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amount);
            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            IMiniPool(miniPool).deposit(address(erc20Tokens[idx]), false, amount, address(this));

            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            IMiniPool(miniPool).withdraw(address(erc20Tokens[idx]), amount, address(this));

            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            IMiniPool(miniPool).borrow(address(erc20Tokens[idx]), amount, address(this));

            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            IMiniPool(miniPool).repay(address(erc20Tokens[idx]), amount, address(this));

            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            IMiniPool(miniPool).liquidationCall(
                address(erc20Tokens[idx]), address(erc20Tokens[idx]), address(this), amount, false
            );

            vm.expectRevert(bytes(Errors.LP_IS_PAUSED));
            IMiniPool(miniPool).setUserUseReserveAsCollateral(address(erc20Tokens[idx]), true);
        }
    }
}
