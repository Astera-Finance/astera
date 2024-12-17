// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract DefaultReserveInterestRateStrategyTest is Common {
    using WadRayMath for uint256;

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
            address(commonContracts.aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        commonContracts.aTokens =
            fixture_getATokens(tokens, deployedContracts.cod3xLendDataProvider);
        commonContracts.variableDebtTokens =
            fixture_getVarDebtTokens(tokens, deployedContracts.cod3xLendDataProvider);
        commonContracts.mockedVaults =
            fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function testCheckRatesAtZeroUtilizationRate() public view {
        StaticData[] memory staticData = new StaticData[](erc20Tokens.length);
        for (uint32 idx = 0; idx < erc20Tokens.length; idx++) {
            uint256 currentLiquidityRate = 0;
            uint256 currentVariableBorrowRate = 0;
            staticData[idx] = deployedContracts.cod3xLendDataProvider.getLpReserveStaticData(
                address(erc20Tokens[idx]), false
            );
            (currentLiquidityRate, currentVariableBorrowRate) = deployedContracts
                .stableStrategy
                .calculateInterestRates(
                address(erc20Tokens[idx]),
                address(commonContracts.aTokens[idx]),
                0,
                0,
                0,
                staticData[idx].cod3xReserveFactor
            );
            assertEq(currentLiquidityRate, 0);
            assertEq(currentVariableBorrowRate, 0);
        }
    }

    function testCheckRatesAtEightyUtilizationRate() public view {
        StaticData[] memory staticData = new StaticData[](erc20Tokens.length);
        for (uint32 idx = 0; idx < erc20Tokens.length; idx++) {
            uint256 currentLiquidityRate = 0;
            uint256 currentVariableBorrowRate = 0;
            staticData[idx] = deployedContracts.cod3xLendDataProvider.getLpReserveStaticData(
                address(erc20Tokens[idx]), false
            );
            (currentLiquidityRate, currentVariableBorrowRate) = deployedContracts
                .stableStrategy
                .calculateInterestRates(
                address(erc20Tokens[idx]),
                address(commonContracts.aTokens[idx]),
                200000000000000000,
                0,
                800000000000000000,
                staticData[idx].cod3xReserveFactor
            );
            uint256 baseVariableBorrowRate =
                deployedContracts.stableStrategy.baseVariableBorrowRate();
            uint256 variableRateSlope1 = deployedContracts.stableStrategy.variableRateSlope1();
            uint256 expectedVariableRate = baseVariableBorrowRate + variableRateSlope1;
            uint256 value = expectedVariableRate * 80 / 100;
            uint256 percentage = PERCENTAGE_FACTOR - staticData[idx].cod3xReserveFactor;
            uint256 expectedLiquidityRate = (value * percentage + 5000) / PERCENTAGE_FACTOR;

            assertEq(currentLiquidityRate, expectedLiquidityRate);
            assertEq(currentVariableBorrowRate, expectedVariableRate);
        }
    }

    function testCheckRatesAtHundredUtilizationRate() public view {
        StaticData[] memory staticData = new StaticData[](erc20Tokens.length);
        for (uint32 idx = 0; idx < erc20Tokens.length; idx++) {
            uint256 currentLiquidityRate = 0;
            uint256 currentVariableBorrowRate = 0;
            staticData[idx] = deployedContracts.cod3xLendDataProvider.getLpReserveStaticData(
                address(erc20Tokens[idx]), false
            );
            (currentLiquidityRate, currentVariableBorrowRate) = deployedContracts
                .stableStrategy
                .calculateInterestRates(
                address(erc20Tokens[idx]),
                address(commonContracts.aTokens[idx]),
                0,
                0,
                800000000000000000,
                staticData[idx].cod3xReserveFactor
            );
            uint256 baseVariableBorrowRate =
                deployedContracts.stableStrategy.baseVariableBorrowRate();
            uint256 variableRateSlope1 = deployedContracts.stableStrategy.variableRateSlope1();
            uint256 variableRateSlope2 = deployedContracts.stableStrategy.variableRateSlope2();
            uint256 expectedVariableRate =
                baseVariableBorrowRate + variableRateSlope1 + variableRateSlope2;
            uint256 value = expectedVariableRate;
            uint256 percentage = PERCENTAGE_FACTOR - staticData[idx].cod3xReserveFactor;
            uint256 expectedLiquidityRate = (value * percentage + 5000) / PERCENTAGE_FACTOR;

            assertEq(currentLiquidityRate, expectedLiquidityRate);
            assertEq(currentVariableBorrowRate, expectedVariableRate);
        }
    }
}
