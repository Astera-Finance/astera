// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

contract LiquidationTest is Common {
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;
    DeployedMiniPoolContracts miniPoolContracts;
    address miniPool;

    function setOraclePrices(uint256 newPrice, uint256 index) internal {
        uint256[] memory timeouts = new uint256[](4);

        int256[] memory prices = new int256[](4);
        for (uint256 idx = 0; idx < erc20Tokens.length; idx++) {
            if (idx == index) {
                prices[idx] = int256(newPrice);
            } else {
                prices[idx] =
                    int256(commonContracts.oracle.getAssetPrice(address(erc20Tokens[idx])));
            }
        }
        address[] memory aggregators = new address[](4);
        (, aggregators, timeouts) = fixture_getTokenPriceFeeds(erc20Tokens, prices);

        commonContracts.oracle.setAssetSources(tokens, aggregators, timeouts);
    }

    function resetOraclePrices() internal {
        console2.log("RESET ->>>>>>>>>>>>>>>>>>>>>>>>>>>>>");
        uint256[] memory timeouts = new uint256[](4);

        int256[] memory prices = new int256[](4);
        prices[0] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // USDC
        prices[1] = int256(67_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[2] = int256(3700 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[3] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // DAI
        address[] memory aggregators = new address[](4);
        (, aggregators, timeouts) = fixture_getTokenPriceFeeds(erc20Tokens, prices);

        commonContracts.oracle.setAssetSources(tokens, aggregators, timeouts);
    }

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.asteraDataProvider),
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
        resetOraclePrices();

        (miniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.asteraDataProvider),
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
        configAddresses.asteraDataProvider = address(miniPoolContracts.miniPoolAddressesProvider);
        configAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts, 0);
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setMinDebtThreshold(0, IMiniPool(miniPool));
        vm.label(miniPool, "MiniPool");
    }

    function testLiquidationOfHealthyLoan() public {
        address user = makeAddr("user");

        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = commonContracts.oracle.getAssetPrice(address(wbtc));
        uint256 usdcPrice = commonContracts.oracle.getAssetPrice(address(usdc));
        uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        StaticData memory staticData =
            deployedContracts.asteraDataProvider.getLpReserveStaticData(address(usdc), true);
        uint256 usdcMaxBorrowValue = staticData.ltv * usdcDepositValue / 10_000;
        uint256 wbtcMaxBorrowAmountWithUsdcCollateral;
        {
            // uint256 wbtcMaxBorrowAmountRaw = (usdcMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
            uint256 wbtcMaxBorrowAmountRay = usdcMaxBorrowValue.rayDiv(wbtcPrice);
            wbtcMaxBorrowAmountWithUsdcCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxBorrowAmountRay, usdc.decimals(), wbtc.decimals()
            );
            require(
                wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral,
                "Too less wbtc"
            );
        }
        uint256 wbtcDepositAmount = wbtc.balanceOf(address(this));

        /* Main user deposits usdc and wants to borrow */
        usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
        deployedContracts.lendingPool.deposit(address(usdc), true, usdcDepositAmount, address(this));

        /* Other user deposits wbtc thanks to that there is enough funds to borrow */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
        deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);

        uint256 wbtcBalanceBeforeBorrow = wbtc.balanceOf(address(this));
        console2.log("Wbtc balance before: ", wbtcBalanceBeforeBorrow);

        /* Main user borrows maxPossible amount of wbtc */
        deployedContracts.lendingPool.borrow(
            address(wbtc), true, wbtcMaxBorrowAmountWithUsdcCollateral, address(this)
        );

        UserReserveData memory userReservesData =
            deployedContracts.asteraDataProvider.getLpUserData(address(usdc), true, address(this));

        vm.expectRevert(bytes(Errors.LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD));
        deployedContracts.lendingPool.liquidationCall(
            address(usdc),
            true,
            address(wbtc),
            true,
            address(this),
            userReservesData.currentVariableDebt,
            false
        );
    }

    function testLiquidationOfUnhealthyLoanWithDebtIncreased(uint256 priceIncrease) public {
        TokenParams[] memory tokensParams = new TokenParams[](erc20Tokens.length);

        tokensParams[USDC_OFFSET].token = erc20Tokens[USDC_OFFSET];
        tokensParams[USDC_OFFSET].price =
            commonContracts.oracle.getAssetPrice(address(tokensParams[USDC_OFFSET].token));

        tokensParams[WBTC_OFFSET].token = erc20Tokens[WBTC_OFFSET];
        tokensParams[WBTC_OFFSET].price =
            commonContracts.oracle.getAssetPrice(address(tokensParams[WBTC_OFFSET].token));

        {
            uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here
            StaticData memory staticData = deployedContracts
                .asteraDataProvider
                .getLpReserveStaticData(address(tokensParams[USDC_OFFSET].token), true);

            uint256 usdcMaxBorrowAmount = staticData.ltv * usdcDepositAmount / 10_000;

            uint256 wbtcMaxToBorrowRay = usdcMaxBorrowAmount.rayDiv(tokensParams[WBTC_OFFSET].price);
            uint256 wbtcMaxBorrowAmountWithUsdcCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxToBorrowRay,
                tokensParams[USDC_OFFSET].token.decimals(),
                tokensParams[WBTC_OFFSET].token.decimals()
            );
            require(
                tokensParams[WBTC_OFFSET].token.balanceOf(address(this))
                    > wbtcMaxBorrowAmountWithUsdcCollateral,
                "Too less wbtc"
            );
            uint256 wbtcDepositAmount = tokensParams[WBTC_OFFSET].token.balanceOf(address(this)) / 2;

            /* Main user deposits usdc and wants to borrow */
            tokensParams[USDC_OFFSET].token.approve(
                address(deployedContracts.lendingPool), usdcDepositAmount
            );
            deployedContracts.lendingPool.deposit(
                address(tokensParams[USDC_OFFSET].token), true, usdcDepositAmount, address(this)
            );

            /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
            {
                address user = makeAddr("user");
                tokensParams[WBTC_OFFSET].token.approve(
                    address(deployedContracts.lendingPool), wbtcDepositAmount
                );
                deployedContracts.lendingPool.deposit(
                    address(tokensParams[WBTC_OFFSET].token), true, wbtcDepositAmount, user
                );
            }
            /* Main user borrows maxPossible amount of wbtc */
            deployedContracts.lendingPool.borrow(
                address(tokensParams[WBTC_OFFSET].token),
                true,
                wbtcMaxBorrowAmountWithUsdcCollateral,
                address(this)
            );
        }
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            assertGe(healthFactor, 1 ether);
        }

        /* simulate btc price increase */
        {
            priceIncrease = bound(priceIncrease, 800, 1200); // 8% -12%
            uint256 newPrice = (
                tokensParams[WBTC_OFFSET].price
                    + tokensParams[WBTC_OFFSET].price * priceIncrease / 10_000
            );
            setOraclePrices(newPrice, WBTC_OFFSET);
            tokensParams[WBTC_OFFSET].price = newPrice;
        }

        DynamicData memory wbtcReserveParamsBefore = deployedContracts
            .asteraDataProvider
            .getLpReserveDynamicData(address(tokensParams[WBTC_OFFSET].token), true);
        DynamicData memory usdcReserveParamsBefore = deployedContracts
            .asteraDataProvider
            .getLpReserveDynamicData(address(tokensParams[USDC_OFFSET].token), true);

        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            assertLt(healthFactor, 1 ether);
        }

        /**
         * LIQUIDATION PROCESS - START ***********
         */
        uint256 amountToLiquidate;
        uint256 scaledVariableDebt;

        UserReserveData memory userReservesData = deployedContracts.asteraDataProvider.getLpUserData(
            address(tokensParams[WBTC_OFFSET].token), true, address(this)
        );
        amountToLiquidate = userReservesData.currentVariableDebt / 2; // maximum possible liquidation amount
        scaledVariableDebt = userReservesData.scaledVariableDebt;

        {
            /* prepare funds */
            address liquidator = makeAddr("liquidator");
            tokensParams[WBTC_OFFSET].token.transfer(liquidator, amountToLiquidate);

            vm.startPrank(liquidator);
            tokensParams[WBTC_OFFSET].token.approve(
                address(deployedContracts.lendingPool), amountToLiquidate
            );
            deployedContracts.lendingPool.liquidationCall(
                address(tokensParams[USDC_OFFSET].token),
                true,
                address(tokensParams[WBTC_OFFSET].token),
                true,
                address(this),
                amountToLiquidate,
                false
            );
            vm.stopPrank();
        }
        /**
         * LIQUIDATION PROCESS - END ***********
         */
        DynamicData memory wbtcReserveParamsAfter = deployedContracts
            .asteraDataProvider
            .getLpReserveDynamicData(address(tokensParams[WBTC_OFFSET].token), true);
        DynamicData memory usdcReserveParamsAfter = deployedContracts
            .asteraDataProvider
            .getLpReserveDynamicData(address(tokensParams[USDC_OFFSET].token), true);
        uint256 expectedCollateralLiquidated;

        {
            StaticData memory staticData = deployedContracts
                .asteraDataProvider
                .getLpReserveStaticData(address(tokensParams[USDC_OFFSET].token), true);

            expectedCollateralLiquidated = tokensParams[WBTC_OFFSET].price
                * (amountToLiquidate * staticData.liquidationBonus / 10_000)
                * 10 ** tokensParams[USDC_OFFSET].token.decimals()
                / (tokensParams[USDC_OFFSET].price * 10 ** tokensParams[WBTC_OFFSET].token.decimals());
        }
        uint256 variableDebtBeforeTx = fixture_calcExpectedVariableDebtTokenBalance(
            wbtcReserveParamsBefore.variableBorrowRate,
            wbtcReserveParamsBefore.variableBorrowIndex,
            wbtcReserveParamsBefore.lastUpdateTimestamp,
            scaledVariableDebt,
            block.timestamp
        );
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            // console2.log("AFTER LIQUIDATION: ");
            // console2.log("healthFactor: ", healthFactor);
            assertGt(healthFactor, 1 ether);
        }

        userReservesData = deployedContracts.asteraDataProvider.getLpUserData(
            address(tokensParams[WBTC_OFFSET].token), true, address(this)
        );

        assertApproxEqRel(
            userReservesData.currentVariableDebt, variableDebtBeforeTx - amountToLiquidate, 0.01e18
        );
        assertApproxEqRel(
            wbtcReserveParamsAfter.availableLiquidity,
            wbtcReserveParamsBefore.availableLiquidity + amountToLiquidate,
            0.01e18
        );
        assertGe(wbtcReserveParamsAfter.liquidityIndex, wbtcReserveParamsBefore.liquidityIndex);
        assertLt(wbtcReserveParamsAfter.liquidityRate, wbtcReserveParamsBefore.liquidityRate);
        assertApproxEqRel(
            usdcReserveParamsAfter.availableLiquidity,
            usdcReserveParamsBefore.availableLiquidity - expectedCollateralLiquidated,
            0.01e18
        );
        userReservesData = deployedContracts.asteraDataProvider.getLpUserData(
            address(tokensParams[USDC_OFFSET].token), true, address(this)
        );
        assertEq(userReservesData.usageAsCollateralEnabledOnUser, true);
    }

    function testLiquidationOfUnhealthyLoanWithCollateralDecreased(uint256 priceDecrease) public {
        TokenParams[] memory tokensParams = new TokenParams[](erc20Tokens.length);

        tokensParams[USDC_OFFSET].token = erc20Tokens[USDC_OFFSET];
        tokensParams[USDC_OFFSET].price =
            commonContracts.oracle.getAssetPrice(address(tokensParams[USDC_OFFSET].token));

        tokensParams[WBTC_OFFSET].token = erc20Tokens[WBTC_OFFSET];
        tokensParams[WBTC_OFFSET].price =
            commonContracts.oracle.getAssetPrice(address(tokensParams[WBTC_OFFSET].token));
        {
            uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here
            uint256 usdcMaxBorrowValue;
            {
                uint256 usdcDepositValue = usdcDepositAmount * tokensParams[USDC_OFFSET].price
                    / (10 ** PRICE_FEED_DECIMALS);
                StaticData memory staticData = deployedContracts
                    .asteraDataProvider
                    .getLpReserveStaticData(address(tokensParams[USDC_OFFSET].token), true);

                usdcMaxBorrowValue = staticData.ltv * usdcDepositValue / 10_000;
            }

            uint256 wbtcMaxToBorrowRay = usdcMaxBorrowValue.rayDiv(tokensParams[WBTC_OFFSET].price);
            uint256 wbtcMaxBorrowAmountWithUsdcCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxToBorrowRay,
                tokensParams[USDC_OFFSET].token.decimals(),
                tokensParams[WBTC_OFFSET].token.decimals()
            );
            // console2.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
            // console2.log("Balance: ", wbtc.balanceOf(address(this)));
            require(
                tokensParams[WBTC_OFFSET].token.balanceOf(address(this))
                    > wbtcMaxBorrowAmountWithUsdcCollateral,
                "Too less wbtc"
            );

            uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral * 15 / 10; // *1,5

            /* Main user deposits usdc and wants to borrow */
            tokensParams[USDC_OFFSET].token.approve(
                address(deployedContracts.lendingPool), usdcDepositAmount
            );
            deployedContracts.lendingPool.deposit(
                address(tokensParams[USDC_OFFSET].token), true, usdcDepositAmount, address(this)
            );

            /* Other user deposits wbtc, thanks to that there is enough funds to borrow */
            address user = makeAddr("user");
            tokensParams[WBTC_OFFSET].token.approve(
                address(deployedContracts.lendingPool), wbtcDepositAmount
            );
            deployedContracts.lendingPool.deposit(
                address(tokensParams[WBTC_OFFSET].token), true, wbtcDepositAmount, user
            );

            /* Main user borrows maxPossible amount of wbtc */
            deployedContracts.lendingPool.borrow(
                address(tokensParams[WBTC_OFFSET].token),
                true,
                wbtcMaxBorrowAmountWithUsdcCollateral,
                address(this)
            );
        }
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            // console2.log("BEFORE: ");
            // console2.log("healthFactor: ", healthFactor);
            assertGe(healthFactor, 1 ether);
        }

        /* simulate usdc price decrease */

        {
            uint256 newUsdcPrice;
            priceDecrease = bound(priceDecrease, 600, 1000); /* descrease by 10 - 15% */
            newUsdcPrice = (
                tokensParams[USDC_OFFSET].price
                    - tokensParams[USDC_OFFSET].price * priceDecrease / 10_000
            );
            console2.log("NEW Price: ", newUsdcPrice);

            setOraclePrices(newUsdcPrice, USDC_OFFSET);
            tokensParams[USDC_OFFSET].price = newUsdcPrice;
        }

        DynamicData memory wbtcReserveParamsBefore = deployedContracts
            .asteraDataProvider
            .getLpReserveDynamicData(address(tokensParams[WBTC_OFFSET].token), true);
        DynamicData memory usdcReserveParamsBefore = deployedContracts
            .asteraDataProvider
            .getLpReserveDynamicData(address(tokensParams[USDC_OFFSET].token), true);
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            // console2.log("AFTER PRICE CHANGE: ");
            console2.log("healthFactor :::: ", healthFactor);
            assertLt(healthFactor, 1 ether);
        }

        /**
         * LIQUIDATION PROCESS - START ***********
         */
        uint256 amountToLiquidate;
        uint256 scaledVariableDebt;

        UserReserveData memory userReservesData = deployedContracts.asteraDataProvider.getLpUserData(
            address(tokensParams[WBTC_OFFSET].token), true, address(this)
        );
        amountToLiquidate = userReservesData.currentVariableDebt / 2; // maximum possible liquidation amount
        scaledVariableDebt = userReservesData.scaledVariableDebt;

        {
            /* prepare funds */
            address liquidator = makeAddr("liquidator");
            tokensParams[WBTC_OFFSET].token.transfer(liquidator, amountToLiquidate);

            vm.startPrank(liquidator);
            tokensParams[WBTC_OFFSET].token.approve(
                address(deployedContracts.lendingPool), amountToLiquidate
            );
            deployedContracts.lendingPool.liquidationCall(
                address(tokensParams[USDC_OFFSET].token),
                true,
                address(tokensParams[WBTC_OFFSET].token),
                true,
                address(this),
                amountToLiquidate,
                false
            );
            vm.stopPrank();
        }
        /**
         * LIQUIDATION PROCESS - END ***********
         */
        DynamicData memory wbtcReserveParamsAfter = deployedContracts
            .asteraDataProvider
            .getLpReserveDynamicData(address(tokensParams[WBTC_OFFSET].token), true);
        DynamicData memory usdcReserveParamsAfter = deployedContracts
            .asteraDataProvider
            .getLpReserveDynamicData(address(tokensParams[USDC_OFFSET].token), true);
        uint256 expectedCollateralLiquidated;

        userReservesData = deployedContracts.asteraDataProvider.getLpUserData(
            address(tokensParams[WBTC_OFFSET].token), true, address(this)
        );

        {
            StaticData memory staticData = deployedContracts
                .asteraDataProvider
                .getLpReserveStaticData(address(tokensParams[USDC_OFFSET].token), true);

            expectedCollateralLiquidated = tokensParams[WBTC_OFFSET].price
                * (amountToLiquidate * staticData.liquidationBonus / 10_000)
                * 10 ** tokensParams[USDC_OFFSET].token.decimals()
                / (tokensParams[USDC_OFFSET].price * 10 ** tokensParams[WBTC_OFFSET].token.decimals());
        }
        uint256 variableDebtBeforeTx = fixture_calcExpectedVariableDebtTokenBalance(
            wbtcReserveParamsBefore.variableBorrowRate,
            wbtcReserveParamsBefore.variableBorrowIndex,
            wbtcReserveParamsBefore.lastUpdateTimestamp,
            scaledVariableDebt,
            block.timestamp
        );
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            // console2.log("AFTER LIQUIDATION: ");
            // console2.log("healthFactor: ", healthFactor);
            assertGt(healthFactor, 1 ether);
        }
        // console2.log("currentVariableDebt: ", currentVariableDebt);
        // console2.log("variableDebtBeforeTx : ", variableDebtBeforeTx);
        // console2.log("amountToLiquidate: ", amountToLiquidate);
        // console2.log("availableLiquidity: ", usdcReserveParamsBefore.availableLiquidity);
        // console2.log("expectedCollateralLiquidated: ", expectedCollateralLiquidated);

        assertApproxEqRel(
            userReservesData.currentVariableDebt, variableDebtBeforeTx - amountToLiquidate, 0.01e18
        );
        assertApproxEqRel(
            wbtcReserveParamsAfter.availableLiquidity,
            wbtcReserveParamsBefore.availableLiquidity + amountToLiquidate,
            0.01e18
        );
        assertGe(wbtcReserveParamsAfter.liquidityIndex, wbtcReserveParamsBefore.liquidityIndex);
        assertLt(wbtcReserveParamsAfter.liquidityRate, wbtcReserveParamsBefore.liquidityRate);
        assertApproxEqRel(
            usdcReserveParamsAfter.availableLiquidity,
            usdcReserveParamsBefore.availableLiquidity - expectedCollateralLiquidated,
            0.01e18
        );

        userReservesData = deployedContracts.asteraDataProvider.getLpUserData(
            address(tokensParams[USDC_OFFSET].token), true, address(this)
        );
        assertEq(userReservesData.usageAsCollateralEnabledOnUser, true);
    }
}
