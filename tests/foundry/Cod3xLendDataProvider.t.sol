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
// import "./LendingPoolFixtures.t.sol";
import "./MiniPoolFixtures.t.sol";
import "contracts/misc/Cod3xLendDataProvider.sol";
import "contracts/interfaces/ICod3xLendDataProvider.sol";

contract Cod3xLendDataProviderTest is MiniPoolFixtures {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    ERC20[] erc20Tokens;
    Cod3xLendDataProvider cod3xLendDataProvider;

    function setUp() public override {
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
        uint256 miniPoolId;
        (miniPoolContracts, miniPoolId) = fixture_deployMiniPoolSetup(
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
        configAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool = fixture_configureMiniPoolReserves(
            reserves, configAddresses, miniPoolContracts, miniPoolId
        );
        vm.label(miniPool, "MiniPool");
    }

    function testDepositCap() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        uint256 usdcDepositAmount = 1e16; // bound(usdcDepositAmount, 1e12, 10_000e18);
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
        deal(address(wbtcTypes.token), address(this), type(uint256).max / 2);
        deal(address(usdcTypes.token), user1, type(uint256).max / 2);
        deal(address(wbtcTypes.token), user2, type(uint256).max / 2);
        deal(address(usdcTypes.token), user3, type(uint256).max / 2);
        console.log("Deposit borrow...");
        fixture_depositAndBorrow(usdcTypes, wbtcTypes, address(this), user1, usdcDepositAmount);
        fixture_depositAndBorrow(usdcTypes, wbtcTypes, user2, user3, usdcDepositAmount);

        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.setDepositCap(address(usdcTypes.token), true, 200);

        StaticData memory staticData = deployedContracts
            .cod3xLendDataProvider
            .getLpReserveStaticData(address(usdcTypes.token), true);
        console.log("depositCap ", staticData.depositCap);
        assertEq(staticData.depositCap, 200);
    }

    function testProvider() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        uint256 usdcDepositAmount = 1e16; // bound(usdcDepositAmount, 1e12, 10_000e18);
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
        deal(address(wbtcTypes.token), address(this), type(uint256).max / 2);
        deal(address(usdcTypes.token), user1, type(uint256).max / 2);
        deal(address(wbtcTypes.token), user2, type(uint256).max / 2);
        deal(address(usdcTypes.token), user3, type(uint256).max / 2);
        console.log("Deposit borrow...");
        fixture_depositAndBorrow(usdcTypes, wbtcTypes, address(this), user1, usdcDepositAmount);
        fixture_depositAndBorrow(usdcTypes, wbtcTypes, user2, user3, usdcDepositAmount);
        {
            StaticData memory staticData = deployedContracts
                .cod3xLendDataProvider
                .getLpReserveStaticData(address(usdcTypes.token), true);

            console.log("Decimals: ", staticData.decimals);
            assertEq(staticData.decimals, usdcTypes.token.decimals());

            console.log("Ltv: ", staticData.ltv);
            assertEq(staticData.ltv, 8000);
            console.log("Liquidation threshold: ", staticData.liquidationThreshold);
            assertEq(staticData.liquidationThreshold, 8500);
            console.log("LiquidationBonus ", staticData.liquidationBonus);
            assertEq(staticData.liquidationBonus, 10500);
            console.log("reserveFactor ", staticData.cod3xReserveFactor);
            assertEq(staticData.cod3xReserveFactor, 1500);
            console.log("depositCap ", staticData.depositCap);
            assertEq(staticData.depositCap, 0);
            console.log("borrowingEnabled ", staticData.borrowingEnabled);
            assertEq(staticData.borrowingEnabled, true);
            console.log("flashloanEnabled ", staticData.flashloanEnabled);
            assertEq(staticData.flashloanEnabled, true);
            console.log("isActive ", staticData.isActive);
            assertEq(staticData.isActive, true);
            console.log("isFrozen ", staticData.isFrozen);
            assertEq(staticData.isFrozen, false);

            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
            deployedContracts.lendingPoolConfigurator.setDepositCap(
                address(usdcTypes.token), true, 200
            );
            vm.stopPrank();

            staticData = deployedContracts.cod3xLendDataProvider.getLpReserveStaticData(
                address(usdcTypes.token), true
            );
            assertEq(staticData.depositCap, 200);
        }
        {
            DynamicData memory dynamicData;
            console.log("\n>>>> USDC <<<<");

            dynamicData = deployedContracts.cod3xLendDataProvider.getLpReserveDynamicData(
                address(usdcTypes.token), true
            );
            assertEq(
                dynamicData.availableLiquidity, 2 * usdcDepositAmount, "Wrong available liquidity"
            );
            assertEq(dynamicData.totalVariableDebt, 0, "Wrong totalVariableDebt");
            assertEq(dynamicData.liquidityRate, 0, "Wrong liquidityRate");
            assertEq(dynamicData.liquidityIndex, 1e27, "Wrong liquidityRate");
            assertEq(dynamicData.variableBorrowRate, 0, "Wrong variableBorrowRate");
            assertEq(dynamicData.variableBorrowIndex, 1e27, "Wrong variableBorrowIndex");
            assertEq(dynamicData.lastUpdateTimestamp, block.timestamp, "Wrong lastUpdateTimestamp");
            console.log("\n>>>> WBTC <<<<<");

            dynamicData = deployedContracts.cod3xLendDataProvider.getLpReserveDynamicData(
                address(wbtcTypes.token), true
            );
            uint256 wbtcAmount =
                fixture_getMaxValueToBorrow(usdcTypes.token, wbtcTypes.token, usdcDepositAmount);
            console.log(
                "availableLiquidity: %s vs %s",
                dynamicData.availableLiquidity,
                (2 * wbtcAmount * 15 / 10) - 2 * wbtcAmount
            );
            assertEq(
                (2 * wbtcAmount * 15 / 10) - 2 * wbtcAmount,
                dynamicData.availableLiquidity,
                "Wrong availableLiquidity"
            );
            console.log("totalVariableDeb: %s vs %s", dynamicData.totalVariableDebt, 2 * wbtcAmount);
            assertEq(2 * wbtcAmount, dynamicData.totalVariableDebt, "Wrong totalVariableDebt");
            console.log("liquidityRate ", dynamicData.liquidityRate);
            console.log("variableBorrowRate ", dynamicData.variableBorrowRate);
            console.log("liquidityIndex ", dynamicData.liquidityIndex);
            console.log("variableBorrowIndex ", dynamicData.variableBorrowIndex);
            console.log("lastUpdateTimestamp ", dynamicData.lastUpdateTimestamp);
        }
        {
            (,, address[] memory aTokens, address[] memory debtTokens) =
                deployedContracts.cod3xLendDataProvider.getAllLpTokens();
            for (uint256 idx = 0; idx < aTokens.length; idx++) {
                console.log(
                    "%sa. Address: %s (%s)", idx, aTokens[idx], ERC20(aTokens[idx]).symbol()
                );
                console.log(
                    "%sb. Address: %s (%s)", idx, debtTokens[idx], ERC20(debtTokens[idx]).symbol()
                );
            }
        }
        {
            console.log("\n>>>> USER USDC <<<<");
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

            userReservesData = deployedContracts.cod3xLendDataProvider.getLpUserData(
                address(wbtcTypes.token), true, address(this)
            );
            console.log("\n>>>> USER WBTC <<<<<");
            uint256 wbtcAmount =
                fixture_getMaxValueToBorrow(usdcTypes.token, wbtcTypes.token, usdcDepositAmount);
            console.log("aToken: ", userReservesData.aToken);
            console.log("debtToken: ", userReservesData.debtToken);

            console.log("scaledATokenBalance: ", userReservesData.scaledATokenBalance);
            console.log("scaledVariableDebt: ", userReservesData.scaledVariableDebt);
            assertEq(
                userReservesData.scaledATokenBalance, wbtcAmount * 15 / 10, "Wrong wbtc amount"
            );
            assertEq(userReservesData.scaledVariableDebt, 0);
            console.log(
                "usageAsCollateralEnabledOnUser: ", userReservesData.usageAsCollateralEnabledOnUser
            );
            assertEq(
                userReservesData.usageAsCollateralEnabledOnUser, true, "Wrong usage as collateral"
            );
            console.log("isBorrowing: ", userReservesData.isBorrowing);
            assertEq(userReservesData.isBorrowing, false, "Wrong is borrowing flag");
        }
    }

    function testMpProvider(uint256 borrowAmount) public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        borrowAmount = 1e19; // bound(usdcDepositAmount, 1e12, 10_000e18);
        TokenParams memory usdcParams = TokenParams({
            token: erc20Tokens[0],
            aToken: aTokensWrapper[0],
            price: oracle.getAssetPrice(address(erc20Tokens[0]))
        });

        TokenParams memory wbtcParams = TokenParams({
            token: erc20Tokens[1],
            aToken: aTokensWrapper[1],
            price: oracle.getAssetPrice(address(erc20Tokens[1]))
        });
        console.log("Dealing...");
        deal(address(wbtcParams.token), address(this), type(uint256).max / 2);
        deal(address(usdcParams.token), user1, type(uint256).max / 2);
        deal(address(wbtcParams.token), user2, type(uint256).max / 2);
        deal(address(usdcParams.token), user3, type(uint256).max / 2);
        console.log("Deposit borrow...");
        fixture_miniPoolBorrow(borrowAmount, 1, 0, wbtcParams, usdcParams, address(this));
        // fixture_miniPoolBorrow(depositAmount, 1, 0, wbtcParams, usdcParams, user2);
        {
            StaticData memory staticData = deployedContracts
                .cod3xLendDataProvider
                .getMpReserveStaticData(address(usdcParams.token), 0);

            console.log("Decimals: ", staticData.decimals);
            assertEq(staticData.decimals, usdcParams.token.decimals());

            console.log("Ltv: ", staticData.ltv);
            assertEq(staticData.ltv, 9500);
            console.log("Liquidation threshold: ", staticData.liquidationThreshold);
            assertEq(staticData.liquidationThreshold, 9700);
            console.log("LiquidationBonus ", staticData.liquidationBonus);
            assertEq(staticData.liquidationBonus, 10100);
            console.log("reserveFactor ", staticData.cod3xReserveFactor);
            assertEq(staticData.cod3xReserveFactor, 0);
            console.log("depositCap ", staticData.depositCap);
            assertEq(staticData.depositCap, 0);
            console.log("borrowingEnabled ", staticData.borrowingEnabled);
            assertEq(staticData.borrowingEnabled, true);
            console.log("flashloanEnabled ", staticData.flashloanEnabled);
            assertEq(staticData.flashloanEnabled, true);
            console.log("isActive ", staticData.isActive);
            assertEq(staticData.isActive, true);
            console.log("isFrozen ", staticData.isFrozen);
            assertEq(staticData.isFrozen, false);

            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
            miniPoolContracts.miniPoolConfigurator.setDepositCap(
                address(usdcParams.token),
                200,
                IMiniPool(miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0))
            );
            vm.stopPrank();

            staticData = deployedContracts.cod3xLendDataProvider.getMpReserveStaticData(
                address(usdcParams.token), 0
            );
            assertEq(staticData.depositCap, 200);
        }
        {
            console.log("\n>>>> USDC <<<<");
            DynamicData memory dynamicData = deployedContracts
                .cod3xLendDataProvider
                .getMpReserveDynamicData(address(usdcParams.token), 0);
            assertEq(dynamicData.availableLiquidity, 0, "Wrong available liquidity");
            assertEq(dynamicData.totalVariableDebt, borrowAmount, "Wrong totalVariableDebt");
            console.log("liquidityRate ", dynamicData.liquidityRate);
            console.log("variableBorrowRate ", dynamicData.variableBorrowRate);
            console.log("liquidityIndex ", dynamicData.liquidityIndex);
            console.log("variableBorrowIndex ", dynamicData.variableBorrowIndex);
            console.log("lastUpdateTimestamp ", dynamicData.lastUpdateTimestamp);

            console.log("\n>>>> WBTC <<<<<");
            dynamicData = deployedContracts.cod3xLendDataProvider.getMpReserveDynamicData(
                address(wbtcParams.token), 0
            );

            console.log("availableLiquidity: %", dynamicData.availableLiquidity);
            assertGt(dynamicData.availableLiquidity, 0, "Wrong availableLiquidity");
            assertEq(0, dynamicData.totalVariableDebt, "Wrong totalVariableDebt");
            assertEq(dynamicData.liquidityRate, 0, "Wrong liquidityRate");
            assertEq(dynamicData.liquidityIndex, 1e27, "Wrong liquidityRate");
            assertEq(dynamicData.variableBorrowRate, 0, "Wrong variableBorrowRate");
            assertEq(dynamicData.variableBorrowIndex, 1e27, "Wrong variableBorrowIndex");
            assertEq(dynamicData.lastUpdateTimestamp, block.timestamp, "Wrong lastUpdateTimestamp");
        }
        {
            (
                address[] memory aErc6909Token,
                address[] memory reserves,
                uint256[] memory aTokenIds,
                uint256[] memory variableDebtTokenIds
            ) = deployedContracts.cod3xLendDataProvider.getAllMpTokenInfo(0);
            for (uint256 idx = 0; idx < aTokens.length; idx++) {
                console.log("%sa. Address: %s ", idx, aErc6909Token[idx]);
                console.log(
                    "%sb. Address: %s (%s)", idx, reserves[idx], ERC20(reserves[idx]).symbol()
                );
                console.log("%sa. aTokenId: %s", idx, aTokenIds[idx]);
                console.log("%sb. variableTokenId: %s ", idx, variableDebtTokenIds[idx]);
            }
        }
        {
            console.log("\n>>>> USER USDC <<<<");
            MiniPoolUserReserveData memory userReservesData = deployedContracts
                .cod3xLendDataProvider
                .getMpUserData(address(this), 0, address(usdcParams.token));
            console.log("aTokenId: ", userReservesData.aTokenId);
            console.log("debtTokenId: ", userReservesData.debtTokenId);
            console.log("scaledATokenBalance: ", userReservesData.scaledATokenBalance);
            console.log("scaledVariableDebt: ", userReservesData.scaledVariableDebt);
            console.log(
                "usageAsCollateralEnabledOnUser: ", userReservesData.usageAsCollateralEnabledOnUser
            );
            console.log("isBorrowing: ", userReservesData.isBorrowing);

            userReservesData = deployedContracts.cod3xLendDataProvider.getMpUserData(
                address(this), 0, address(wbtcParams.token)
            );
            console.log("\n>>>> USER WBTC <<<<<");

            console.log("aTokenId: ", userReservesData.aTokenId);
            console.log("debtTokenId: ", userReservesData.debtTokenId);

            console.log("scaledATokenBalance: ", userReservesData.scaledATokenBalance);
            console.log("scaledVariableDebt: ", userReservesData.scaledVariableDebt);
            assertGt(userReservesData.scaledATokenBalance, 0, "Wrong wbtc amount");
            assertEq(userReservesData.scaledVariableDebt, 0);
            console.log(
                "usageAsCollateralEnabledOnUser: ", userReservesData.usageAsCollateralEnabledOnUser
            );
            assertEq(
                userReservesData.usageAsCollateralEnabledOnUser, true, "Wrong usage as collateral"
            );
            console.log("isBorrowing: ", userReservesData.isBorrowing);
            assertEq(userReservesData.isBorrowing, false, "Wrong is borrowing flag");

            address underlying =
                deployedContracts.cod3xLendDataProvider.getUnderlyingAssetFromId(1128, 0);
            console.log(ERC20(underlying).symbol());
            assertEq(0, deployedContracts.cod3xLendDataProvider.getMpUnderlyingBalanceOf(1128, 0));

            underlying = deployedContracts.cod3xLendDataProvider.getUnderlyingAssetFromId(1129, 0);
            console.log(ERC20(underlying).symbol());
            assertGt(deployedContracts.cod3xLendDataProvider.getMpUnderlyingBalanceOf(1129, 0), 0);
        }
    }

    function testReservesForMiniPools(uint256 borrowAmount) public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        borrowAmount = 1e18; // bound(usdcDepositAmount, 1e12, 10_000e18);
        TokenParams memory usdcParams = TokenParams({
            token: erc20Tokens[0],
            aToken: aTokensWrapper[0],
            price: oracle.getAssetPrice(address(erc20Tokens[0]))
        });

        TokenParams memory wbtcParams = TokenParams({
            token: erc20Tokens[1],
            aToken: aTokensWrapper[1],
            price: oracle.getAssetPrice(address(erc20Tokens[1]))
        });
        console.log("Dealing...");
        deal(address(wbtcParams.token), address(this), type(uint256).max / 2);
        deal(address(usdcParams.token), user1, type(uint256).max / 2);
        deal(address(wbtcParams.token), user2, type(uint256).max / 2);
        deal(address(usdcParams.token), user3, type(uint256).max / 2);
        console.log("Deposit borrow...");
        fixture_miniPoolBorrow(borrowAmount, 1, 0, wbtcParams, usdcParams, address(this));

        /* Deploy new mini pools */
        console.log("Deploy more miniPools");
        (, uint256 miniPoolId) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            address(miniPoolContracts.miniPoolAddressesProvider)
        );
        console.log("MiniPoolId: ", miniPoolId);

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] = address(aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        miniPool = fixture_configureMiniPoolReserves(
            reserves, configAddresses, miniPoolContracts, miniPoolId
        );
        borrowAmount = 7e18;
        fixture_miniPoolBorrow(borrowAmount, 1, 0, wbtcParams, usdcParams, user2);

        (address[] memory miniPools, uint256[] memory miniPoolIds) = deployedContracts
            .cod3xLendDataProvider
            .getMiniPoolsWithReserve(address(wbtcParams.token));
        for (uint256 idx = 0; idx < miniPools.length; idx++) {
            console.log("%s. Address: %s, Id: %s", idx, miniPools[idx], miniPoolIds[idx]);
        }

        (miniPools, miniPoolIds) = deployedContracts.cod3xLendDataProvider.getMiniPoolsWithReserve(
            address(usdcParams.token)
        );
        for (uint256 idx = 0; idx < miniPools.length; idx++) {
            console.log("%s. Address: %s, Id: %s", idx, miniPools[idx], miniPoolIds[idx]);
        }

        (miniPools, miniPoolIds) =
            deployedContracts.cod3xLendDataProvider.getMiniPoolsWithReserve(makeAddr("random"));
        for (uint256 idx = 0; idx < miniPools.length; idx++) {
            console.log("%s. Address: %s, Id: %s", idx, miniPools[idx], miniPoolIds[idx]);
        }
    }
}
