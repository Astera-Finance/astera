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
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));
    }

    function testLiquidationOfHealthyLoan() public {
        address user = makeAddr("user");

        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = erc20Tokens[1];
        uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
        uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
        (, uint256 usdcLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), true);
        uint256 usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;
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
        console.log("Wbtc balance before: ", wbtcBalanceBeforeBorrow);

        /* Main user borrows maxPossible amount of wbtc */
        deployedContracts.lendingPool.borrow(
            address(wbtc), true, wbtcMaxBorrowAmountWithUsdcCollateral, address(this)
        );

        (, uint256 debtToCover,,,) = deployedContracts.protocolDataProvider.getUserReserveData(
            address(usdc), true, address(this)
        );

        vm.expectRevert(bytes(Errors.LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD));
        deployedContracts.lendingPool.liquidationCall(
            address(usdc), true, address(wbtc), true, address(this), debtToCover, false
        );
    }

    function testLiquidationOfUnhealthyLoanWithDebtIncreased(uint256 priceIncrease) public {
        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = ERC20(erc20Tokens[1]);

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
        {
            uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here
            (, uint256 usdcLtv,,,,,,,) = deployedContracts
                .protocolDataProvider
                .getReserveConfigurationData(address(usdc), true);

            uint256 usdcMaxBorrowAmount = usdcLtv * usdcDepositAmount / 10_000;

            uint256 wbtcMaxToBorrowRay = usdcMaxBorrowAmount.rayDiv(wbtcPrice);
            uint256 wbtcMaxBorrowAmountWithUsdcCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxToBorrowRay, usdc.decimals(), wbtc.decimals()
            );
            require(
                wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral,
                "Too less wbtc"
            );
            uint256 wbtcDepositAmount = wbtc.balanceOf(address(this)) / 2;

            /* Main user deposits usdc and wants to borrow */
            usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
            deployedContracts.lendingPool.deposit(
                address(usdc), true, usdcDepositAmount, address(this)
            );

            /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
            {
                address user = makeAddr("user");
                wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
                deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);
            }
            /* Main user borrows maxPossible amount of wbtc */
            deployedContracts.lendingPool.borrow(
                address(wbtc), true, wbtcMaxBorrowAmountWithUsdcCollateral, address(this)
            );
        }
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            assertGe(healthFactor, 1 ether);
        }

        /* simulate btc price increase */
        {
            priceIncrease = bound(priceIncrease, 800, 1_200); // 8-12%
            uint256 newPrice = (wbtcPrice + wbtcPrice * priceIncrease / 10_000);

            int256[] memory prices = new int256[](4);
            prices[0] = int256(oracle.getAssetPrice(address(usdc)));
            prices[1] = int256(newPrice);
            prices[2] = int256(oracle.getAssetPrice(address(weth)));
            prices[3] = int256(oracle.getAssetPrice(address(dai)));
            address[] memory aggregators = new address[](4);
            (, aggregators) = fixture_getTokenPriceFeeds(erc20Tokens, prices);

            oracle.setAssetSources(tokens, aggregators);
            wbtcPrice = newPrice;
        }

        ReserveDataParams memory wbtcReserveParamsBefore =
            fixture_getReserveData(address(wbtc), deployedContracts.protocolDataProvider);
        ReserveDataParams memory usdcReserveParamsBefore =
            fixture_getReserveData(address(usdc), deployedContracts.protocolDataProvider);
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
        {
            (, uint256 debtToCover, uint256 _scaledVariableDebt,,) = deployedContracts
                .protocolDataProvider
                .getUserReserveData(address(wbtc), true, address(this));
            amountToLiquidate = debtToCover / 2; // maximum possible liquidation amount
            scaledVariableDebt = _scaledVariableDebt;
        }
        {
            /* prepare funds */
            address liquidator = makeAddr("liquidator");
            wbtc.transfer(liquidator, amountToLiquidate);

            vm.startPrank(liquidator);
            wbtc.approve(address(deployedContracts.lendingPool), amountToLiquidate);
            deployedContracts.lendingPool.liquidationCall(
                address(usdc), true, address(wbtc), true, address(this), amountToLiquidate, false
            );
            vm.stopPrank();
        }
        /**
         * LIQUIDATION PROCESS - END ***********
         */
        ReserveDataParams memory wbtcReserveParamsAfter =
            fixture_getReserveData(address(wbtc), deployedContracts.protocolDataProvider);
        ReserveDataParams memory usdcReserveParamsAfter =
            fixture_getReserveData(address(usdc), deployedContracts.protocolDataProvider);
        uint256 expectedCollateralLiquidated;

        {
            (,,, uint256 liquidationBonus,,,,,) = deployedContracts
                .protocolDataProvider
                .getReserveConfigurationData(address(usdc), true);

            expectedCollateralLiquidated = wbtcPrice
                * (amountToLiquidate * liquidationBonus / 10_000) * 10 ** usdc.decimals()
                / (usdcPrice * 10 ** wbtc.decimals());
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
            // console.log("AFTER LIQUIDATION: ");
            // console.log("healthFactor: ", healthFactor);
            assertGt(healthFactor, 1 ether);
        }

        (, uint256 currentVariableDebt,,,) = deployedContracts
            .protocolDataProvider
            .getUserReserveData(address(wbtc), true, address(this));

        assertApproxEqRel(currentVariableDebt, variableDebtBeforeTx - amountToLiquidate, 0.01e18);
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
        {
            (,,,, bool usageAsCollateralEnabled) = deployedContracts
                .protocolDataProvider
                .getUserReserveData(address(usdc), true, address(this));
            assertEq(usageAsCollateralEnabled, true);
        }
    }

    function testLiquidationOfUnhealthyLoanWithCollateralDecreased(uint256 priceDecrease) public {
        ERC20 usdc = erc20Tokens[0];
        ERC20 wbtc = ERC20(erc20Tokens[1]);

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
        {
            uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here
            uint256 usdcMaxBorrowValue;
            {
                uint256 usdcDepositValue =
                    usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
                (, uint256 usdcLtv,,,,,,,) = deployedContracts
                    .protocolDataProvider
                    .getReserveConfigurationData(address(usdc), true);

                usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;
            }

            uint256 wbtcMaxToBorrowRay = usdcMaxBorrowValue.rayDiv(wbtcPrice);
            uint256 wbtcMaxBorrowAmountWithUsdcCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxToBorrowRay, usdc.decimals(), wbtc.decimals()
            );
            // console.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
            // console.log("Balance: ", wbtc.balanceOf(address(this)));
            require(
                wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral,
                "Too less wbtc"
            );

            uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral * 15 / 10; // *1,5

            /* Main user deposits usdc and wants to borrow */
            usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
            deployedContracts.lendingPool.deposit(
                address(usdc), true, usdcDepositAmount, address(this)
            );

            /* Other user deposits wbtc, thanks to that there is enough funds to borrow */
            address user = makeAddr("user");
            wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
            deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);

            /* Main user borrows maxPossible amount of wbtc */
            deployedContracts.lendingPool.borrow(
                address(wbtc), true, wbtcMaxBorrowAmountWithUsdcCollateral, address(this)
            );
        }
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            // console.log("BEFORE: ");
            // console.log("healthFactor: ", healthFactor);
            assertGe(healthFactor, 1 ether);
        }

        /* simulate usdc price decrease */

        {
            uint256 newUsdcPrice;
            priceDecrease = bound(priceDecrease, 600, 1_000); /* descrease by 6 - 50% */
            newUsdcPrice = (usdcPrice - usdcPrice * priceDecrease / 10_000);
            // console.log("Price: ", newUsdcPrice);

            int256[] memory prices = new int256[](4);
            prices[0] = int256(newUsdcPrice);
            prices[1] = int256(oracle.getAssetPrice(address(wbtc)));
            prices[2] = int256(oracle.getAssetPrice(address(weth)));
            prices[3] = int256(oracle.getAssetPrice(address(dai)));
            address[] memory aggregators = new address[](4);
            (, aggregators) = fixture_getTokenPriceFeeds(erc20Tokens, prices);

            oracle.setAssetSources(tokens, aggregators);
            usdcPrice = newUsdcPrice;
        }

        ReserveDataParams memory wbtcReserveParamsBefore =
            fixture_getReserveData(address(wbtc), deployedContracts.protocolDataProvider);
        ReserveDataParams memory usdcReserveParamsBefore =
            fixture_getReserveData(address(usdc), deployedContracts.protocolDataProvider);
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            // console.log("AFTER PRICE CHANGE: ");
            // console.log("healthFactor: ", healthFactor);
            assertLt(healthFactor, 1 ether);
        }

        /**
         * LIQUIDATION PROCESS - START ***********
         */
        uint256 amountToLiquidate;
        uint256 scaledVariableDebt;

        {
            (, uint256 debtToCover, uint256 _scaledVariableDebt,,) = deployedContracts
                .protocolDataProvider
                .getUserReserveData(address(wbtc), true, address(this));
            amountToLiquidate = debtToCover / 2; // maximum possible liquidation amount
            scaledVariableDebt = _scaledVariableDebt;
        }
        {
            /* prepare funds */
            address liquidator = makeAddr("liquidator");
            wbtc.transfer(liquidator, amountToLiquidate);

            vm.startPrank(liquidator);
            wbtc.approve(address(deployedContracts.lendingPool), amountToLiquidate);
            deployedContracts.lendingPool.liquidationCall(
                address(usdc), true, address(wbtc), true, address(this), amountToLiquidate, false
            );
            vm.stopPrank();
        }
        /**
         * LIQUIDATION PROCESS - END ***********
         */
        ReserveDataParams memory wbtcReserveParamsAfter =
            fixture_getReserveData(address(wbtc), deployedContracts.protocolDataProvider);
        ReserveDataParams memory usdcReserveParamsAfter =
            fixture_getReserveData(address(usdc), deployedContracts.protocolDataProvider);
        uint256 expectedCollateralLiquidated;

        (, uint256 currentVariableDebt,,,) = deployedContracts
            .protocolDataProvider
            .getUserReserveData(address(wbtc), true, address(this));

        {
            (,,, uint256 liquidationBonus,,,,,) = deployedContracts
                .protocolDataProvider
                .getReserveConfigurationData(address(usdc), true);

            expectedCollateralLiquidated = wbtcPrice
                * (amountToLiquidate * liquidationBonus / 10_000) * 10 ** usdc.decimals()
                / (usdcPrice * 10 ** wbtc.decimals());
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
            // console.log("AFTER LIQUIDATION: ");
            // console.log("healthFactor: ", healthFactor);
            assertGt(healthFactor, 1 ether);
        }
        // console.log("currentVariableDebt: ", currentVariableDebt);
        // console.log("variableDebtBeforeTx : ", variableDebtBeforeTx);
        // console.log("amountToLiquidate: ", amountToLiquidate);
        // console.log("availableLiquidity: ", usdcReserveParamsBefore.availableLiquidity);
        // console.log("expectedCollateralLiquidated: ", expectedCollateralLiquidated);

        assertApproxEqRel(currentVariableDebt, variableDebtBeforeTx - amountToLiquidate, 0.01e18);
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
        {
            (,,,, bool usageAsCollateralEnabled) = deployedContracts
                .protocolDataProvider
                .getUserReserveData(address(usdc), true, address(this));
            assertEq(usageAsCollateralEnabled, true);
        }
    }
}
