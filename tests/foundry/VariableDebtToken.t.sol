// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

contract VariableDebtTokenTest is Common {
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
        variableDebtTokens =
            fixture_getVarDebtTokens(tokens, deployedContracts.protocolDataProvider);
        mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function testAccessControl() public {
        for (uint32 idx = 0; idx < aTokens.length; idx++) {
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            variableDebtTokens[idx].mint(address(this), address(this), 1, 1);
            vm.expectRevert(bytes(Errors.CT_CALLER_MUST_BE_LENDING_POOL));
            variableDebtTokens[idx].burn(admin, 1, 1);
        }
    }

    function testMintingAndBurningVariableDebtTokens(uint256 maxValToMintAndBurn) public {
        uint8 nrOfIterations = 20;
        maxValToMintAndBurn = bound(maxValToMintAndBurn, nrOfIterations, 20_000_000);

        uint256 granuality = maxValToMintAndBurn / nrOfIterations;
        maxValToMintAndBurn = maxValToMintAndBurn - (maxValToMintAndBurn % granuality); // accept only multiplicity of 20
        vm.startPrank(address(deployedContracts.lendingPool));
        for (uint32 idx = 0; idx < variableDebtTokens.length; idx++) {
            /* Minting tests with additiveness */
            for (uint256 cnt = 0; cnt < maxValToMintAndBurn; cnt += granuality) {
                variableDebtTokens[idx].mint(address(this), address(this), granuality, 1);
            }
            assertEq(
                variableDebtTokens[idx].balanceOf(address(this)), maxValToMintAndBurn.rayDiv(1)
            );
            variableDebtTokens[idx].mint(address(this), address(this), maxValToMintAndBurn, 1);
            assertEq(
                variableDebtTokens[idx].balanceOf(address(this)), 2 * maxValToMintAndBurn.rayDiv(1)
            );
            assertEq(variableDebtTokens[idx].totalSupply(), 2 * maxValToMintAndBurn.rayDiv(1));

            /* Burning tests with additiveness */
            for (uint256 cnt = 0; cnt < maxValToMintAndBurn; cnt += granuality) {
                variableDebtTokens[idx].burn(address(this), granuality, 1);
            }
            assertEq(
                variableDebtTokens[idx].balanceOf(address(this)), maxValToMintAndBurn.rayDiv(1)
            );
            variableDebtTokens[idx].burn(address(this), maxValToMintAndBurn, 1);
            assertEq(variableDebtTokens[idx].balanceOf(address(this)), 0);
            assertEq(variableDebtTokens[idx].totalSupply(), 0);
        }
        vm.stopPrank();
    }

    function testBalanceAfterBorrow(uint256 maxValToDeposit) public {
        uint8 nrOfIterations = 20;
        maxValToDeposit = bound(maxValToDeposit, nrOfIterations, 2_000_000);

        for (uint32 idx = 0; idx < variableDebtTokens.length; idx++) {
            /* Minting tests with additiveness */
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), maxValToDeposit);
            deployedContracts.lendingPool.deposit(
                address(erc20Tokens[idx]), true, maxValToDeposit, address(this)
            );

            assertEq(variableDebtTokens[idx].balanceOf(address(this)), 0);
            assertEq(variableDebtTokens[idx].totalSupply(), 0);

            /* Burning tests with additiveness */
            (, uint256 currentAssetLtv,,,,,,,) = deployedContracts
                .protocolDataProvider
                .getReserveConfigurationData(address(erc20Tokens[idx]), true);

            uint256 amountToBorrowRaw = maxValToDeposit * currentAssetLtv / 10_000;
            deployedContracts.lendingPool.borrow(
                address(erc20Tokens[idx]), true, amountToBorrowRaw, address(this)
            );
            assertEq(variableDebtTokens[idx].balanceOf(address(this)), amountToBorrowRaw);
            assertEq(variableDebtTokens[idx].totalSupply(), amountToBorrowRaw);
        }
    }
}
