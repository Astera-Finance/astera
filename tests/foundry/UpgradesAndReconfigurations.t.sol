// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolFixtures.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import "contracts/misc/Cod3xLendDataProvider.sol";
import {LendingPoolV2} from "tests/foundry/helpers/LendingPoolV2.sol";
import {MiniPoolV2} from "tests/foundry/helpers/MiniPoolV2.sol";
import {ATokenERC6909V2} from "tests/foundry/helpers/ATokenERC6909V2.sol";
import {ATokenV2} from "tests/foundry/helpers/ATokenV2.sol";
import {VariableDebtTokenV2} from "tests/foundry/helpers/VariableDebtTokenV2.sol";
import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";

import "forge-std/StdUtils.sol";
import "forge-std/console.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract UpgradesAndReconfigurationsTest is MiniPoolFixtures {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;

    function fixture_depositBorrowAndCheck(
        TokenTypes memory collateralType,
        TokenTypes memory borrowType,
        uint256 amount,
        address user
    ) public returns (DynamicData[] memory dynamicDataBefore, address[] memory aTokens) {
        skip(10 days);

        deal(address(collateralType.token), address(this), 2 * amount);
        uint256 maxValToBorrow =
            fixture_getMaxValueToBorrow(collateralType.token, borrowType.token, amount);
        deal(address(borrowType.token), user, 2 * maxValToBorrow);

        fixture_depositAndBorrow(collateralType, borrowType, user, address(this), amount);

        /* Checks */
        (,, aTokens,) = deployedContracts.cod3xLendDataProvider.getAllLpTokens();
        dynamicDataBefore = new DynamicData[](aTokens.length);
        for (uint8 idx; idx < aTokens.length; idx++) {
            console.log(
                "%s (%s)",
                AToken(aTokens[idx]).UNDERLYING_ASSET_ADDRESS(),
                ERC20(AToken(aTokens[idx]).UNDERLYING_ASSET_ADDRESS()).symbol()
            );
            dynamicDataBefore[idx] = deployedContracts.cod3xLendDataProvider.getLpReserveDynamicData(
                AToken(aTokens[idx]).UNDERLYING_ASSET_ADDRESS(), true
            );
            console.log(
                "availableLiquidity: %s\n  totalVariableDebt: %s\n",
                dynamicDataBefore[idx].availableLiquidity,
                dynamicDataBefore[idx].totalVariableDebt
            );
        }
    }

    function fixture_checkStorageData(
        DynamicData[] memory dynamicDataBefore,
        address[] memory aTokens
    ) public view {
        DynamicData[] memory dynamicDataAfter = new DynamicData[](aTokens.length);
        for (uint8 idx; idx < aTokens.length; idx++) {
            console.log(
                "%s (%s)",
                AToken(aTokens[idx]).UNDERLYING_ASSET_ADDRESS(),
                ERC20(AToken(aTokens[idx]).UNDERLYING_ASSET_ADDRESS()).symbol()
            );
            dynamicDataAfter[idx] = deployedContracts.cod3xLendDataProvider.getLpReserveDynamicData(
                AToken(aTokens[idx]).UNDERLYING_ASSET_ADDRESS(), true
            );
            console.log(
                "availableLiquidity: %s\n  totalVariableDebt: %s\n",
                dynamicDataAfter[idx].availableLiquidity,
                dynamicDataAfter[idx].totalVariableDebt
            );
            assertEq(
                dynamicDataBefore[idx].availableLiquidity, dynamicDataAfter[idx].availableLiquidity
            );
            assertEq(
                dynamicDataBefore[idx].totalVariableDebt, dynamicDataAfter[idx].totalVariableDebt
            );
            assertEq(dynamicDataBefore[idx].liquidityRate, dynamicDataAfter[idx].liquidityRate);
            assertEq(
                dynamicDataBefore[idx].variableBorrowRate, dynamicDataAfter[idx].variableBorrowRate
            );
            assertEq(dynamicDataBefore[idx].liquidityIndex, dynamicDataAfter[idx].liquidityIndex);
            assertEq(
                dynamicDataBefore[idx].variableBorrowIndex,
                dynamicDataAfter[idx].variableBorrowIndex
            );
            assertEq(
                dynamicDataBefore[idx].lastUpdateTimestamp,
                dynamicDataAfter[idx].lastUpdateTimestamp
            );
        }
    }

    function fixture_depositBorrowAndCheckMiniPool(
        TokenParams memory collateralParams,
        TokenParams memory borrowParams,
        uint256 amount,
        address user
    ) public returns (DynamicData[] memory dynamicDataBefore) {
        deal(address(collateralParams.token), user, 10 ** collateralParams.token.decimals() * 1_000);

        /* Deposit tests */
        fixture_miniPoolBorrow(amount, 0, 1, collateralParams, borrowParams, user);

        /* Checks */
        (, address[] memory reserves,,) =
            deployedContracts.cod3xLendDataProvider.getAllMpTokenInfo(0);
        dynamicDataBefore = new DynamicData[](reserves.length);
        for (uint8 idx; idx < reserves.length; idx++) {
            console.log("%s (%s)", reserves[idx], ERC20(reserves[idx]).symbol());
            dynamicDataBefore[idx] =
                deployedContracts.cod3xLendDataProvider.getMpReserveDynamicData(reserves[idx], 0);
            console.log(
                "availableLiquidity: %s\n  totalVariableDebt: %s\n",
                dynamicDataBefore[idx].availableLiquidity,
                dynamicDataBefore[idx].totalVariableDebt
            );
        }
    }

    function fixture_checkStorageDataMiniPool(DynamicData[] memory dynamicDataBefore) public view {
        DynamicData[] memory dynamicDataAfter = new DynamicData[](commonContracts.aTokens.length);
        for (uint8 idx; idx < commonContracts.aTokens.length; idx++) {
            console.log(
                "%s (%s)",
                AToken(commonContracts.aTokens[idx]).UNDERLYING_ASSET_ADDRESS(),
                ERC20(AToken(commonContracts.aTokens[idx]).UNDERLYING_ASSET_ADDRESS()).symbol()
            );
            dynamicDataAfter[idx] = deployedContracts.cod3xLendDataProvider.getMpReserveDynamicData(
                AToken(commonContracts.aTokens[idx]).UNDERLYING_ASSET_ADDRESS(), 0
            );
            console.log(
                "availableLiquidity: %s\n  totalVariableDebt: %s\n",
                dynamicDataAfter[idx].availableLiquidity,
                dynamicDataAfter[idx].totalVariableDebt
            );
            assertEq(
                dynamicDataBefore[idx].availableLiquidity, dynamicDataAfter[idx].availableLiquidity
            );
            assertEq(
                dynamicDataBefore[idx].totalVariableDebt, dynamicDataAfter[idx].totalVariableDebt
            );
            assertEq(dynamicDataBefore[idx].liquidityRate, dynamicDataAfter[idx].liquidityRate);
            assertEq(
                dynamicDataBefore[idx].variableBorrowRate, dynamicDataAfter[idx].variableBorrowRate
            );
            assertEq(dynamicDataBefore[idx].liquidityIndex, dynamicDataAfter[idx].liquidityIndex);
            assertEq(
                dynamicDataBefore[idx].variableBorrowIndex,
                dynamicDataAfter[idx].variableBorrowIndex
            );
            assertEq(
                dynamicDataBefore[idx].lastUpdateTimestamp,
                dynamicDataAfter[idx].lastUpdateTimestamp
            );
        }
    }

    function setUp() public override {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();

        configLpAddresses = ConfigAddresses(
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
            configLpAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        commonContracts.mockedVaults =
            fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));
        (miniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            miniPoolContracts
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] =
                    address(commonContracts.aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        configLpAddresses.cod3xLendDataProvider =
            address(miniPoolContracts.miniPoolAddressesProvider);
        configLpAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configLpAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configLpAddresses, miniPoolContracts, 0);
        vm.label(miniPool, "MiniPool");

        /* --- --- General Settings --- ---*/
        // uint256 offset;
        uint256 amount;
        address user = makeAddr("user");

        /* --- Lending Pool deposit --- */
        console.log("Lending Pool deposit");

        /* Fuzz vector creation */
        // offset = bound(offset, 0, tokens.length - 1);
        TokenTypes memory collateralType = TokenTypes({
            token: erc20Tokens[USDC_OFFSET],
            aToken: commonContracts.aTokens[USDC_OFFSET],
            debtToken: commonContracts.variableDebtTokens[USDC_OFFSET]
        });

        TokenTypes memory borrowType = TokenTypes({
            token: erc20Tokens[WBTC_OFFSET],
            aToken: commonContracts.aTokens[WBTC_OFFSET],
            debtToken: commonContracts.variableDebtTokens[WBTC_OFFSET]
        });

        amount = bound(
            amount,
            10 ** collateralType.token.decimals() / 100,
            collateralType.token.balanceOf(address(this)) / 2
        );

        deal(address(collateralType.token), address(this), 2 * amount);
        uint256 maxValToBorrow =
            fixture_getMaxValueToBorrow(collateralType.token, borrowType.token, amount);
        deal(address(borrowType.token), user, 2 * maxValToBorrow);

        fixture_depositAndBorrow(collateralType, borrowType, user, address(this), amount);

        /* --- Mini Pool deposit --- */
        console.log("Mini Pool deposit");

        /* Fuzz vector creation */
        // offset = bound(offset, 0, tokens.length - 1);
        Oracle oracle = Oracle(miniPoolContracts.miniPoolAddressesProvider.getPriceOracle());
        TokenParams memory collateralParams = TokenParams(
            erc20Tokens[USDC_OFFSET],
            commonContracts.aTokensWrapper[USDC_OFFSET],
            oracle.getAssetPrice(address(erc20Tokens[USDC_OFFSET]))
        );
        TokenParams memory borrowParams = TokenParams(
            erc20Tokens[WBTC_OFFSET],
            commonContracts.aTokensWrapper[WBTC_OFFSET],
            oracle.getAssetPrice(address(erc20Tokens[WBTC_OFFSET]))
        );
        amount = bound(
            amount,
            10 ** collateralParams.token.decimals() / 100,
            10 ** collateralParams.token.decimals() * 1_000
        );

        deal(address(collateralParams.token), user, 10 ** collateralParams.token.decimals() * 1_000);

        /* Deposit tests */
        fixture_miniPoolBorrow(amount, 0, 1, collateralParams, borrowParams, user);
    }

    /**
     * Preconditions:
     * 1. LendingPool Configured
     * 2. LendingPool has already borrowed tokens - some debt and interest rates accrued
     * Test Scenario:
     * 1. Admin upgrades lending pool
     * 2. Check if the dynamic data doesn't change after update
     * 3. Deposit and borrow again
     * Invariants:
     * 1. Storage data shouldn't be affected by the upgrade
     * 2. All action shall be possible to do after upgrade
     */
    function testUpgradeOfLendingPool() public {
        // uint256 offset;
        uint256 amount;
        address user = makeAddr("user");

        console.log("Second Lending Pool deposit");

        TokenTypes memory collateralType = TokenTypes({
            token: erc20Tokens[USDC_OFFSET],
            aToken: commonContracts.aTokens[USDC_OFFSET],
            debtToken: commonContracts.variableDebtTokens[USDC_OFFSET]
        });

        TokenTypes memory borrowType = TokenTypes({
            token: erc20Tokens[WBTC_OFFSET],
            aToken: commonContracts.aTokens[WBTC_OFFSET],
            debtToken: commonContracts.variableDebtTokens[WBTC_OFFSET]
        });

        amount = bound(
            amount,
            10 ** collateralType.token.decimals() / 100,
            10 ** collateralType.token.decimals() * 1_000
        );

        (DynamicData[] memory dynamicDataBefore, address[] memory aTokens) =
            fixture_depositBorrowAndCheck(collateralType, borrowType, amount, user);

        {
            LendingPoolV2 lpv2 = new LendingPoolV2();

            address lendingPoolProxy =
                address(deployedContracts.lendingPoolAddressesProvider.getLendingPool());

            vm.prank(address(deployedContracts.lendingPoolAddressesProvider));
            address previousPoolImpl = InitializableImmutableAdminUpgradeabilityProxy(
                payable(lendingPoolProxy)
            ).implementation();

            lpv2.initialize(
                ILendingPoolAddressesProvider(deployedContracts.lendingPoolAddressesProvider)
            );
            deployedContracts.lendingPoolAddressesProvider.setLendingPoolImpl(address(lpv2));
            lendingPoolProxy =
                address(deployedContracts.lendingPoolAddressesProvider.getLendingPool());

            /* Check if addresses are updated */
            deployedContracts.lendingPool = LendingPool(lendingPoolProxy);
            vm.startPrank(address(deployedContracts.lendingPoolAddressesProvider));
            // console.log(
            //     "Impl: ",
            //     InitializableImmutableAdminUpgradeabilityProxy(payable(address(lendingPoolProxy)))
            //         .implementation()
            // );
            assertNotEq(
                previousPoolImpl,
                InitializableImmutableAdminUpgradeabilityProxy(payable(lendingPoolProxy))
                    .implementation()
            );
            vm.stopPrank();
        }
        /* 1. Storage data shouldn't be affected by the upgrade */
        fixture_checkStorageData(dynamicDataBefore, aTokens);

        /* 2. Actions shall be possible to do after upgrade */
        deal(address(collateralType.token), address(this), 2 * amount);
        uint256 maxValToBorrow =
            fixture_getMaxValueToBorrow(collateralType.token, borrowType.token, amount);
        deal(address(borrowType.token), user, 2 * maxValToBorrow);
        fixture_depositAndBorrow(collateralType, borrowType, user, address(this), amount);
    }

    /**
     * Preconditions:
     * 1. MiniPool Configured
     * 2. MiniPool has already borrowed tokens - some debt and interest rates accrued
     * Test Scenario:
     * 1. Admin upgrades mini pool
     * 2. Check if the dynamic data doesn't change after update
     * 3. Deposit and borrow again
     * Invariants:
     * 1. Storage data shouldn't be affected by the upgrade
     * 2. All action shall be possible to do after upgrade
     */
    function testUpgradeOfMiniPool() public {
        skip(10 days);

        uint256 amount;
        address user = makeAddr("user");

        console.log("Second Mini Pool deposit");

        /* Fuzz vector creation */
        // offset = bound(offset, 0, tokens.length - 1);
        Oracle oracle = Oracle(miniPoolContracts.miniPoolAddressesProvider.getPriceOracle());
        TokenParams memory collateralParams = TokenParams(
            erc20Tokens[USDC_OFFSET],
            commonContracts.aTokensWrapper[USDC_OFFSET],
            oracle.getAssetPrice(address(erc20Tokens[USDC_OFFSET]))
        );
        TokenParams memory borrowParams = TokenParams(
            erc20Tokens[WBTC_OFFSET],
            commonContracts.aTokensWrapper[WBTC_OFFSET],
            oracle.getAssetPrice(address(erc20Tokens[WBTC_OFFSET]))
        );
        amount = bound(
            amount,
            10 ** collateralParams.token.decimals() / 100,
            10 ** collateralParams.token.decimals() * 1_000
        );

        DynamicData[] memory dynamicDataBefore =
            fixture_depositBorrowAndCheckMiniPool(collateralParams, borrowParams, amount, user);

        {
            MiniPoolV2 mpv2 = new MiniPoolV2();
            ATokenERC6909V2 erc6909v2 = new ATokenERC6909V2();
            vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider));
            address previousMiniPoolImpl = InitializableImmutableAdminUpgradeabilityProxy(
                payable(miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0))
            ).implementation();
            address previousAErc6909Impl = InitializableImmutableAdminUpgradeabilityProxy(
                payable(miniPoolContracts.miniPoolAddressesProvider.getAToken6909(0))
            ).implementation();
            vm.stopPrank();
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(address(mpv2), 0);
            miniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(address(erc6909v2), 0);
            miniPoolContracts.miniPoolImpl = MiniPool(address(mpv2));

            /* Check if addresses are updated */
            vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider));
            assertNotEq(
                InitializableImmutableAdminUpgradeabilityProxy(
                    payable(miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0))
                ).implementation(),
                previousMiniPoolImpl
            );
            assertNotEq(
                InitializableImmutableAdminUpgradeabilityProxy(
                    payable(miniPoolContracts.miniPoolAddressesProvider.getAToken6909(0))
                ).implementation(),
                previousAErc6909Impl
            );
            vm.stopPrank();
        }

        /* 1. Storage data shouldn't be affected by the upgrade */
        fixture_checkStorageDataMiniPool(dynamicDataBefore);

        amount = bound(
            amount,
            10 ** collateralParams.token.decimals() / 100,
            10 ** collateralParams.token.decimals() * 1_000
        );

        /* 2. All action shall be possible to do after upgrade */
        deal(address(collateralParams.token), user, 10 ** collateralParams.token.decimals() * 1_000);

        /* Deposit tests */
        fixture_miniPoolBorrow(amount, 0, 1, collateralParams, borrowParams, user);
    }

    function testUpdateATokenInput() public {
        uint256 amount;
        address user = makeAddr("user");

        console.log("Second Lending Pool deposit");

        TokenTypes memory collateralType = TokenTypes({
            token: erc20Tokens[USDC_OFFSET],
            aToken: commonContracts.aTokens[USDC_OFFSET],
            debtToken: commonContracts.variableDebtTokens[USDC_OFFSET]
        });

        TokenTypes memory borrowType = TokenTypes({
            token: erc20Tokens[WBTC_OFFSET],
            aToken: commonContracts.aTokens[WBTC_OFFSET],
            debtToken: commonContracts.variableDebtTokens[WBTC_OFFSET]
        });

        amount = bound(
            amount,
            10 ** collateralType.token.decimals() / 100,
            10 ** collateralType.token.decimals() * 1_000
        );

        (DynamicData[] memory dynamicDataBefore, address[] memory aTokens) =
            fixture_depositBorrowAndCheck(collateralType, borrowType, amount, user);

        {
            ATokenV2 aTokenV2 = new ATokenV2();

            console.log("aTokenV2 Impl: ", address(aTokenV2));

            console.log("1.aTokenV1 ", address(commonContracts.aTokens[USDC_OFFSET]));
            console.log("1. aTokenV1 Impl: ", address(commonContracts.aToken));

            (address previousPoolImpl,) = deployedContracts.cod3xLendDataProvider.getLpTokens(
                address(collateralType.token), true
            );
            console.log("2.aTokenV1 ", previousPoolImpl);

            vm.prank(address(deployedContracts.lendingPoolConfigurator));
            previousPoolImpl = InitializableImmutableAdminUpgradeabilityProxy(
                payable(previousPoolImpl)
            ).implementation();
            console.log("2.aTokenV1 Impl", previousPoolImpl);

            string memory tmpSymbol = collateralType.token.symbol();
            ILendingPoolConfigurator.UpdateATokenInput memory input = ILendingPoolConfigurator
                .UpdateATokenInput({
                asset: address(collateralType.token),
                reserveType: true,
                treasury: address(deployedContracts.treasury),
                incentivesController: address(deployedContracts.rewarder),
                name: string.concat("Cod3x Lend ", tmpSymbol),
                symbol: string.concat("cl", tmpSymbol),
                implementation: address(aTokenV2),
                params: "0x10"
            });
            // vm.prank(address(deployedContracts.lendingPoolAddressesProvider));
            vm.prank(admin); //pool admin
            deployedContracts.lendingPoolConfigurator.updateAToken(input);

            (address currentImpl,) = deployedContracts.cod3xLendDataProvider.getLpTokens(
                address(collateralType.token), true
            );

            vm.prank(address(deployedContracts.lendingPoolConfigurator));
            currentImpl = InitializableImmutableAdminUpgradeabilityProxy(payable(currentImpl))
                .implementation();
            assertNotEq(previousPoolImpl, currentImpl, "Implementations are equal after update");
        }
        /* 1. Storage data shouldn't be affected by the upgrade */
        fixture_checkStorageData(dynamicDataBefore, aTokens);

        /* 2. Actions shall be possible to do after upgrade */
        deal(address(collateralType.token), address(this), 2 * amount);
        uint256 maxValToBorrow =
            fixture_getMaxValueToBorrow(collateralType.token, borrowType.token, amount);
        deal(address(borrowType.token), user, 2 * maxValToBorrow);

        fixture_depositAndBorrow(collateralType, borrowType, user, address(this), amount);
    }

    function testUpdateDebtTokenInput() public {
        uint256 amount;
        address user = makeAddr("user");

        console.log("Second Lending Pool deposit");

        TokenTypes memory collateralType = TokenTypes({
            token: erc20Tokens[USDC_OFFSET],
            aToken: commonContracts.aTokens[USDC_OFFSET],
            debtToken: commonContracts.variableDebtTokens[USDC_OFFSET]
        });

        TokenTypes memory borrowType = TokenTypes({
            token: erc20Tokens[WBTC_OFFSET],
            aToken: commonContracts.aTokens[WBTC_OFFSET],
            debtToken: commonContracts.variableDebtTokens[WBTC_OFFSET]
        });

        amount = bound(
            amount,
            10 ** collateralType.token.decimals() / 100,
            10 ** collateralType.token.decimals() * 1_000
        );

        (DynamicData[] memory dynamicDataBefore, address[] memory aTokens) =
            fixture_depositBorrowAndCheck(collateralType, borrowType, amount, user);

        {
            VariableDebtTokenV2 variableDebtTokenV2 = new VariableDebtTokenV2();

            (, address previousPoolImpl) = deployedContracts.cod3xLendDataProvider.getLpTokens(
                address(collateralType.token), true
            );
            console.log("2.aTokenV1 ", previousPoolImpl);

            vm.prank(address(deployedContracts.lendingPoolConfigurator));
            previousPoolImpl = InitializableImmutableAdminUpgradeabilityProxy(
                payable(previousPoolImpl)
            ).implementation();
            console.log("2.aTokenV1 Impl", previousPoolImpl);

            string memory tmpSymbol = collateralType.token.symbol();
            ILendingPoolConfigurator.UpdateDebtTokenInput memory input = ILendingPoolConfigurator
                .UpdateDebtTokenInput({
                asset: address(collateralType.token),
                reserveType: true,
                incentivesController: address(deployedContracts.rewarder),
                name: string.concat("Cod3x Lend Debt", tmpSymbol),
                symbol: string.concat("debt", tmpSymbol),
                implementation: address(variableDebtTokenV2),
                params: "0x10"
            });
            // vm.prank(address(deployedContracts.lendingPoolAddressesProvider));
            vm.prank(admin); //pool admin
            deployedContracts.lendingPoolConfigurator.updateVariableDebtToken(input);

            (, address currentImpl) = deployedContracts.cod3xLendDataProvider.getLpTokens(
                address(collateralType.token), true
            );

            vm.prank(address(deployedContracts.lendingPoolConfigurator));
            currentImpl = InitializableImmutableAdminUpgradeabilityProxy(payable(currentImpl))
                .implementation();
            assertNotEq(previousPoolImpl, currentImpl, "Implementations are equal after update");
        }
        /* 1. Storage data shouldn't be affected by the upgrade */
        fixture_checkStorageData(dynamicDataBefore, aTokens);

        /* 2. Actions shall be possible to do after upgrade */
        deal(address(collateralType.token), address(this), 2 * amount);
        uint256 maxValToBorrow =
            fixture_getMaxValueToBorrow(collateralType.token, borrowType.token, amount);
        deal(address(borrowType.token), user, 2 * maxValToBorrow);

        fixture_depositAndBorrow(collateralType, borrowType, user, address(this), amount);
    }
}
