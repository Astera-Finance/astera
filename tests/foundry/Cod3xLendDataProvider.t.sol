// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {LendingPoolConfigurator} from
    "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import {MiniPoolConfigurator} from "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import "forge-std/StdUtils.sol";
import {MathUtils} from "contracts/protocol/libraries/math/MathUtils.sol";
import "./LendingPoolFixtures.t.sol";
import "./MiniPoolFixtures.t.sol";
import "../../contracts/misc/Cod3xLendDataProvider.sol";

contract Cod3xLendDataProviderTest is MiniPoolFixtures, LendingPoolFixtures {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    ERC20[] erc20Tokens;
    Cod3xLendDataProvider cod3xLendDataProvider;

    function setUp() public override(MiniPoolFixtures, LendingPoolFixtures) {
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
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));
        miniPoolContracts = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool)
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
        configAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool = fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts);
        vm.label(miniPool, "MiniPool");
    }

    function testProvider(uint256 usdcDepositAmount) public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        usdcDepositAmount = bound(usdcDepositAmount, 1e12, 10_000e18);
        TokenTypes memory usdcTypes = TokenTypes({
            token: erc20Tokens[0],
            aToken: aTokens[0],
            debtToken: variableDebtTokens[0]
        });

        TokenTypes memory wbtcTypes = TokenTypes({
            token: erc20Tokens[1],
            aToken: aTokens[1],
            debtToken: variableDebtTokens[1]
        });
        console.log("Dealing...");
        deal(address(usdcTypes.token), address(this), type(uint256).max / 2);
        deal(address(wbtcTypes.token), user1, type(uint256).max / 2);
        deal(address(usdcTypes.token), user2, type(uint256).max / 2);
        deal(address(wbtcTypes.token), user3, type(uint256).max / 2);
        console.log("Deposit borrow...");
        fixture_depositAndBorrow(usdcTypes, wbtcTypes, address(this), user1, usdcDepositAmount);
        fixture_depositAndBorrow(usdcTypes, wbtcTypes, user2, user3, usdcDepositAmount);
        {
            StaticData memory staticData = deployedContracts
                .cod3xLendDataProvider
                .getLpReserveStaticData(address(usdcTypes.token), true);

            console.log("Decimals: ", staticData.decimals);
            console.log("Ltv: ", staticData.ltv);
            console.log("Liquidation threshold: ", staticData.liquidationThreshold);
            console.log("LiquidationBonus ", staticData.liquidationBonus);
            console.log("reserveFactor ", staticData.reserveFactor);
            console.log("depositCap ", staticData.depositCap);
            console.log("borrowingEnabled ", staticData.borrowingEnabled);
            console.log("flashloanEnabled ", staticData.flashloanEnabled);
            console.log("isActive ", staticData.isActive);
            console.log("isFrozen ", staticData.isFrozen);
        }
        {
            console.log("USDC\n");
            (
                uint256 availableLiquidity,
                uint256 totalVariableDebt,
                uint256 liquidityRate,
                uint256 variableBorrowRate,
                uint256 liquidityIndex,
                uint256 variableBorrowIndex,
                uint40 lastUpdateTimestamp
            ) = deployedContracts.cod3xLendDataProvider.getLpReserveDynamicData(
                address(usdcTypes.token), true
            );
            console.log(
                "availableLiquidity: %s vs deposited %s", availableLiquidity, 2 * usdcDepositAmount
            );
            console.log("totalVariableDebt ", totalVariableDebt);
            console.log("liquidityRate ", liquidityRate);
            console.log("variableBorrowRate ", variableBorrowRate);
            console.log("liquidityIndex ", liquidityIndex);
            console.log("variableBorrowIndex ", variableBorrowIndex);
            console.log("lastUpdateTimestamp ", lastUpdateTimestamp);
            console.log("WBTC\n");
            (
                availableLiquidity,
                totalVariableDebt,
                liquidityRate,
                variableBorrowRate,
                liquidityIndex,
                variableBorrowIndex,
                lastUpdateTimestamp
            ) = deployedContracts.cod3xLendDataProvider.getLpReserveDynamicData(
                address(wbtcTypes.token), true
            );
            console.log("availableLiquidity: ", availableLiquidity);
            console.log("totalVariableDebt ", totalVariableDebt);
            console.log("liquidityRate ", liquidityRate);
            console.log("variableBorrowRate ", variableBorrowRate);
            console.log("liquidityIndex ", liquidityIndex);
            console.log("variableBorrowIndex ", variableBorrowIndex);
            console.log("lastUpdateTimestamp ", lastUpdateTimestamp);
        }
        {
            (address[] memory aTokens, address[] memory debtTokens) =
                deployedContracts.cod3xLendDataProvider.getLpAllTokens();
            for (uint256 idx = 0; idx < aTokens.length; idx++) {
                console.log("%s. Address: %s", aTokens[idx]);
                console.log("%s. Address: %s", debtTokens[idx]);
            }
        }
        {
            UserReserveData memory userReservesData = deployedContracts
                .cod3xLendDataProvider
                .getLpUserData(address(usdcTypes.token), true, address(this));
            console.log("aToken: ", userReservesData.aToken);
            console.log("debtToken: ", userReservesData.debtToken);
            console.log("scaledATokenBalance: ", userReservesData.scaledATokenBalance);
            console.log("scaledVariableDebt: ", userReservesData.scaledVariableDebt);
            console.log(
                "usageAsCollateralEnabledOnUser: ", userReservesData.usageAsCollateralEnabledOnUser
            );
            console.log("isBorrowing: ", userReservesData.isBorrowing);
        }

        assert(false);
    }
}
