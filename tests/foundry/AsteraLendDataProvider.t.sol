// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {LendingPoolConfigurator} from
    "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import {MiniPoolConfigurator} from "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import {MathUtils} from "contracts/protocol/libraries/math/MathUtils.sol";
import {AsteraLendDataProvider} from "contracts/misc/AsteraLendDataProvider.sol";
import "contracts/interfaces/IAsteraLendDataProvider.sol";
import "forge-std/StdUtils.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import "./MiniPoolFixtures.t.sol";

contract AsteraLendDataProviderTest is MiniPoolFixtures {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    ERC20[] erc20Tokens;
    AsteraLendDataProvider asteraLendDataProvider;

    function setUp() public override {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.asteraLendDataProvider),
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
        commonContracts.mockedVaults =
            fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));
        uint256 miniPoolId;
        (miniPoolContracts, miniPoolId) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.asteraLendDataProvider),
            miniPoolContracts
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console2.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] =
                    address(commonContracts.aTokens[idx - tokens.length].WRAPPER_ADDRESS());
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
            aToken: commonContracts.aTokens[0],
            debtToken: commonContracts.variableDebtTokens[0]
        });

        TokenTypes memory wbtcTypes = TokenTypes({
            token: erc20Tokens[1],
            aToken: commonContracts.aTokens[1],
            debtToken: commonContracts.variableDebtTokens[1]
        });
        console2.log("Dealing...");
        deal(address(wbtcTypes.token), address(this), type(uint256).max / 2);
        deal(address(usdcTypes.token), user1, type(uint256).max / 2);
        deal(address(wbtcTypes.token), user2, type(uint256).max / 2);
        deal(address(usdcTypes.token), user3, type(uint256).max / 2);
        console2.log("Deposit borrow...");
        fixture_depositAndBorrow(usdcTypes, wbtcTypes, address(this), user1, usdcDepositAmount);
        fixture_depositAndBorrow(usdcTypes, wbtcTypes, user2, user3, usdcDepositAmount);

        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.setDepositCap(address(usdcTypes.token), true, 200);

        StaticData memory staticData = deployedContracts
            .asteraLendDataProvider
            .getLpReserveStaticData(address(usdcTypes.token), true);
        console2.log("depositCap ", staticData.depositCap);
        assertEq(staticData.depositCap, 200);
    }

    function testProvider() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        uint256 usdcDepositAmount = 1e16; // bound(usdcDepositAmount, 1e12, 10_000e18);
        TokenTypes memory usdcTypes = TokenTypes({
            token: erc20Tokens[0],
            aToken: commonContracts.aTokens[0],
            debtToken: commonContracts.variableDebtTokens[0]
        });

        TokenTypes memory wbtcTypes = TokenTypes({
            token: erc20Tokens[1],
            aToken: commonContracts.aTokens[1],
            debtToken: commonContracts.variableDebtTokens[1]
        });
        console2.log("Dealing...");
        deal(address(wbtcTypes.token), address(this), type(uint256).max / 2);
        deal(address(usdcTypes.token), user1, type(uint256).max / 2);
        deal(address(wbtcTypes.token), user2, type(uint256).max / 2);
        deal(address(usdcTypes.token), user3, type(uint256).max / 2);
        console2.log("Deposit borrow...");
        fixture_depositAndBorrow(usdcTypes, wbtcTypes, address(this), user1, usdcDepositAmount);
        fixture_depositAndBorrow(usdcTypes, wbtcTypes, user2, user3, usdcDepositAmount);
        {
            StaticData memory staticData = deployedContracts
                .asteraLendDataProvider
                .getLpReserveStaticData(address(usdcTypes.token), true);

            console2.log("Decimals: ", staticData.decimals);
            assertEq(staticData.decimals, usdcTypes.token.decimals());

            console2.log("Ltv: ", staticData.ltv);
            assertEq(staticData.ltv, 8000);
            console2.log("Liquidation threshold: ", staticData.liquidationThreshold);
            assertEq(staticData.liquidationThreshold, 8500);
            console2.log("LiquidationBonus ", staticData.liquidationBonus);
            assertEq(staticData.liquidationBonus, 10500);
            console2.log("reserveFactor ", staticData.asteraReserveFactor);
            assertEq(staticData.asteraReserveFactor, 1500);
            console2.log("depositCap ", staticData.depositCap);
            assertEq(staticData.depositCap, 0);
            console2.log("borrowingEnabled ", staticData.borrowingEnabled);
            assertEq(staticData.borrowingEnabled, true);
            console2.log("flashloanEnabled ", staticData.flashloanEnabled);
            assertEq(staticData.flashloanEnabled, true);
            console2.log("isActive ", staticData.isActive);
            assertEq(staticData.isActive, true);
            console2.log("isFrozen ", staticData.isFrozen);
            assertEq(staticData.isFrozen, false);

            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
            deployedContracts.lendingPoolConfigurator.setDepositCap(
                address(usdcTypes.token), true, 200
            );
            vm.stopPrank();

            staticData = deployedContracts.asteraLendDataProvider.getLpReserveStaticData(
                address(usdcTypes.token), true
            );
            assertEq(staticData.depositCap, 200);
        }
        {
            DynamicData memory dynamicData;
            console2.log("\n>>>> USDC <<<<");

            dynamicData = deployedContracts.asteraLendDataProvider.getLpReserveDynamicData(
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
            console2.log("\n>>>> WBTC <<<<<");

            dynamicData = deployedContracts.asteraLendDataProvider.getLpReserveDynamicData(
                address(wbtcTypes.token), true
            );
            uint256 wbtcAmount =
                fixture_getMaxValueToBorrow(usdcTypes.token, wbtcTypes.token, usdcDepositAmount);
            console2.log(
                "availableLiquidity: %s vs %s",
                dynamicData.availableLiquidity,
                (2 * wbtcAmount * 15 / 10) - 2 * wbtcAmount
            );
            assertEq(
                (2 * wbtcAmount * 15 / 10) - 2 * wbtcAmount,
                dynamicData.availableLiquidity,
                "Wrong availableLiquidity"
            );
            console2.log(
                "totalVariableDeb: %s vs %s", dynamicData.totalVariableDebt, 2 * wbtcAmount
            );
            assertEq(2 * wbtcAmount, dynamicData.totalVariableDebt, "Wrong totalVariableDebt");
            console2.log("liquidityRate ", dynamicData.liquidityRate);
            console2.log("variableBorrowRate ", dynamicData.variableBorrowRate);
            console2.log("liquidityIndex ", dynamicData.liquidityIndex);
            console2.log("variableBorrowIndex ", dynamicData.variableBorrowIndex);
            console2.log("lastUpdateTimestamp ", dynamicData.lastUpdateTimestamp);
        }
        {
            (,, address[] memory aTokens, address[] memory debtTokens) =
                deployedContracts.asteraLendDataProvider.getAllLpTokens();
            // for (uint256 idx = 0; idx < aTokens.length; idx++) {
            //     console2.log(
            //         "%sa. Address: %s (%s)",
            //         idx,
            //         commonContracts.aTokens[idx],
            //         ERC20(aTokens[idx]).symbol()
            //     );
            //     console2.log(
            //         "%sb. Address: %s (%s)", idx, debtTokens[idx], ERC20(debtTokens[idx]).symbol()
            //     );
            // }
        }
        {
            console2.log("\n>>>> USER USDC <<<<");
            UserReserveData memory userReservesData = deployedContracts
                .asteraLendDataProvider
                .getLpUserData(address(usdcTypes.token), true, address(this));
            console2.log("aToken: ", userReservesData.aToken);
            console2.log("debtToken: ", userReservesData.debtToken);
            console2.log("scaledATokenBalance: ", userReservesData.scaledATokenBalance);
            console2.log("scaledVariableDebt: ", userReservesData.scaledVariableDebt);
            console2.log(
                "usageAsCollateralEnabledOnUser: ", userReservesData.usageAsCollateralEnabledOnUser
            );
            console2.log("isBorrowing: ", userReservesData.isBorrowing);

            userReservesData = deployedContracts.asteraLendDataProvider.getLpUserData(
                address(wbtcTypes.token), true, address(this)
            );
            console2.log("\n>>>> USER WBTC <<<<<");
            uint256 wbtcAmount =
                fixture_getMaxValueToBorrow(usdcTypes.token, wbtcTypes.token, usdcDepositAmount);
            console2.log("aToken: ", userReservesData.aToken);
            console2.log("debtToken: ", userReservesData.debtToken);

            console2.log("scaledATokenBalance: ", userReservesData.scaledATokenBalance);
            console2.log("scaledVariableDebt: ", userReservesData.scaledVariableDebt);
            assertEq(
                userReservesData.scaledATokenBalance, wbtcAmount * 15 / 10, "Wrong wbtc amount"
            );
            assertEq(userReservesData.scaledVariableDebt, 0);
            console2.log(
                "usageAsCollateralEnabledOnUser: ", userReservesData.usageAsCollateralEnabledOnUser
            );
            assertEq(
                userReservesData.usageAsCollateralEnabledOnUser, true, "Wrong usage as collateral"
            );
            console2.log("isBorrowing: ", userReservesData.isBorrowing);
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
            aToken: commonContracts.aTokensWrapper[0],
            price: commonContracts.oracle.getAssetPrice(address(erc20Tokens[0]))
        });

        TokenParams memory wbtcParams = TokenParams({
            token: erc20Tokens[1],
            aToken: commonContracts.aTokensWrapper[1],
            price: commonContracts.oracle.getAssetPrice(address(erc20Tokens[1]))
        });
        console2.log("Dealing...");
        deal(address(wbtcParams.token), address(this), type(uint256).max / 2);
        deal(address(usdcParams.token), user1, type(uint256).max / 2);
        deal(address(wbtcParams.token), user2, type(uint256).max / 2);
        deal(address(usdcParams.token), user3, type(uint256).max / 2);
        console2.log("Deposit borrow...");
        fixture_miniPoolBorrow(borrowAmount, 1, 0, wbtcParams, usdcParams, address(this));
        // fixture_miniPoolBorrow(depositAmount, 1, 0, wbtcParams, usdcParams, user2);
        {
            StaticData memory staticData = deployedContracts
                .asteraLendDataProvider
                .getMpReserveStaticData(address(usdcParams.token), 0);

            console2.log("Decimals: ", staticData.decimals);
            assertEq(staticData.decimals, usdcParams.token.decimals());

            console2.log("Ltv: ", staticData.ltv);
            assertEq(staticData.ltv, 9500);
            console2.log("Liquidation threshold: ", staticData.liquidationThreshold);
            assertEq(staticData.liquidationThreshold, 9700);
            console2.log("LiquidationBonus ", staticData.liquidationBonus);
            assertEq(staticData.liquidationBonus, 10100);
            console2.log("reserveFactor ", staticData.asteraReserveFactor);
            assertEq(staticData.asteraReserveFactor, 0);
            console2.log("depositCap ", staticData.depositCap);
            assertEq(staticData.depositCap, 0);
            console2.log("borrowingEnabled ", staticData.borrowingEnabled);
            assertEq(staticData.borrowingEnabled, true);
            console2.log("flashloanEnabled ", staticData.flashloanEnabled);
            assertEq(staticData.flashloanEnabled, true);
            console2.log("isActive ", staticData.isActive);
            assertEq(staticData.isActive, true);
            console2.log("isFrozen ", staticData.isFrozen);
            assertEq(staticData.isFrozen, false);

            vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
            miniPoolContracts.miniPoolConfigurator.setDepositCap(
                address(usdcParams.token),
                200,
                IMiniPool(miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0))
            );
            vm.stopPrank();

            staticData = deployedContracts.asteraLendDataProvider.getMpReserveStaticData(
                address(usdcParams.token), 0
            );
            assertEq(staticData.depositCap, 200);
        }
        {
            console2.log("\n>>>> USDC <<<<");
            DynamicData memory dynamicData = deployedContracts
                .asteraLendDataProvider
                .getMpReserveDynamicData(address(usdcParams.token), 0);
            assertEq(dynamicData.availableLiquidity, 0, "Wrong available liquidity");
            assertEq(dynamicData.totalVariableDebt, borrowAmount, "Wrong totalVariableDebt");
            console2.log("liquidityRate ", dynamicData.liquidityRate);
            console2.log("variableBorrowRate ", dynamicData.variableBorrowRate);
            console2.log("liquidityIndex ", dynamicData.liquidityIndex);
            console2.log("variableBorrowIndex ", dynamicData.variableBorrowIndex);
            console2.log("lastUpdateTimestamp ", dynamicData.lastUpdateTimestamp);

            console2.log("\n>>>> WBTC <<<<<");
            dynamicData = deployedContracts.asteraLendDataProvider.getMpReserveDynamicData(
                address(wbtcParams.token), 0
            );

            console2.log("availableLiquidity: %", dynamicData.availableLiquidity);
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
            ) = deployedContracts.asteraLendDataProvider.getAllMpTokenInfo(0);
            for (uint256 idx = 0; idx < commonContracts.aTokens.length; idx++) {
                console2.log("%sa. Address: %s ", idx, aErc6909Token[idx]);
                console2.log(
                    "%sb. Address: %s (%s)", idx, reserves[idx], ERC20(reserves[idx]).symbol()
                );
                console2.log("%sa. aTokenId: %s", idx, aTokenIds[idx]);
                console2.log("%sb. variableTokenId: %s ", idx, variableDebtTokenIds[idx]);
            }
        }
        {
            console2.log("\n>>>> USER USDC <<<<");
            MiniPoolUserReserveData memory userReservesData = deployedContracts
                .asteraLendDataProvider
                .getMpUserData(address(this), 0, address(usdcParams.token));
            console2.log("aTokenId: ", userReservesData.aTokenId);
            console2.log("debtTokenId: ", userReservesData.debtTokenId);
            console2.log("scaledATokenBalance: ", userReservesData.scaledATokenBalance);
            console2.log("scaledVariableDebt: ", userReservesData.scaledVariableDebt);
            console2.log(
                "usageAsCollateralEnabledOnUser: ", userReservesData.usageAsCollateralEnabledOnUser
            );
            console2.log("isBorrowing: ", userReservesData.isBorrowing);

            userReservesData = deployedContracts.asteraLendDataProvider.getMpUserData(
                address(this), 0, address(wbtcParams.token)
            );
            console2.log("\n>>>> USER WBTC <<<<<");

            console2.log("aTokenId: ", userReservesData.aTokenId);
            console2.log("debtTokenId: ", userReservesData.debtTokenId);

            console2.log("scaledATokenBalance: ", userReservesData.scaledATokenBalance);
            console2.log("scaledVariableDebt: ", userReservesData.scaledVariableDebt);
            assertGt(userReservesData.scaledATokenBalance, 0, "Wrong wbtc amount");
            assertEq(userReservesData.scaledVariableDebt, 0);
            console2.log(
                "usageAsCollateralEnabledOnUser: ", userReservesData.usageAsCollateralEnabledOnUser
            );
            assertEq(
                userReservesData.usageAsCollateralEnabledOnUser, true, "Wrong usage as collateral"
            );
            console2.log("isBorrowing: ", userReservesData.isBorrowing);
            assertEq(userReservesData.isBorrowing, false, "Wrong is borrowing flag");

            address underlying =
                deployedContracts.asteraLendDataProvider.getUnderlyingAssetFromId(1128, 0);
            console2.log(ERC20(underlying).symbol());
            assertEq(0, deployedContracts.asteraLendDataProvider.getMpUnderlyingBalanceOf(1128, 0));

            underlying = deployedContracts.asteraLendDataProvider.getUnderlyingAssetFromId(1129, 0);
            console2.log(ERC20(underlying).symbol());
            assertGt(deployedContracts.asteraLendDataProvider.getMpUnderlyingBalanceOf(1129, 0), 0);
        }
    }

    function testReservesForMiniPools(uint256 borrowAmount) public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        borrowAmount = 1e18; // bound(usdcDepositAmount, 1e12, 10_000e18);
        TokenParams memory usdcParams = TokenParams({
            token: erc20Tokens[0],
            aToken: commonContracts.aTokensWrapper[0],
            price: commonContracts.oracle.getAssetPrice(address(erc20Tokens[0]))
        });

        TokenParams memory wbtcParams = TokenParams({
            token: erc20Tokens[1],
            aToken: commonContracts.aTokensWrapper[1],
            price: commonContracts.oracle.getAssetPrice(address(erc20Tokens[1]))
        });
        console2.log("Dealing...");
        deal(address(wbtcParams.token), address(this), type(uint256).max / 2);
        deal(address(usdcParams.token), user1, type(uint256).max / 2);
        deal(address(wbtcParams.token), user2, type(uint256).max / 2);
        deal(address(usdcParams.token), user3, type(uint256).max / 2);
        console2.log("Deposit borrow...");
        fixture_miniPoolBorrow(borrowAmount, 1, 0, wbtcParams, usdcParams, address(this));

        /* Deploy new mini pools */
        console2.log("Deploy more miniPools");
        (, uint256 miniPoolId) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.asteraLendDataProvider),
            miniPoolContracts
        );
        console2.log("MiniPoolId: ", miniPoolId);

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console2.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] =
                    address(commonContracts.aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        miniPool = fixture_configureMiniPoolReserves(
            reserves, configAddresses, miniPoolContracts, miniPoolId
        );
        borrowAmount = 7e18;
        fixture_miniPoolBorrow(borrowAmount, 1, 0, wbtcParams, usdcParams, user2);

        (address[] memory miniPools, uint256[] memory miniPoolIds) = deployedContracts
            .asteraLendDataProvider
            .getMiniPoolsWithReserve(address(wbtcParams.token));
        for (uint256 idx = 0; idx < miniPools.length; idx++) {
            console2.log("%s. Address: %s, Id: %s", idx, miniPools[idx], miniPoolIds[idx]);
        }

        (miniPools, miniPoolIds) = deployedContracts.asteraLendDataProvider.getMiniPoolsWithReserve(
            address(usdcParams.token)
        );
        for (uint256 idx = 0; idx < miniPools.length; idx++) {
            console2.log("%s. Address: %s, Id: %s", idx, miniPools[idx], miniPoolIds[idx]);
        }

        (miniPools, miniPoolIds) =
            deployedContracts.asteraLendDataProvider.getMiniPoolsWithReserve(makeAddr("random"));
        for (uint256 idx = 0; idx < miniPools.length; idx++) {
            console2.log("%s. Address: %s, Id: %s", idx, miniPools[idx], miniPoolIds[idx]);
        }
    }
}
