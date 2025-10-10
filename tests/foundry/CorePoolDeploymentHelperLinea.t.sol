// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {
    CorePoolDeploymentHelper,
    AsteraDataProvider2,
    AggregatedMainPoolReservesData
} from "contracts/deployments/CorePoolDeploymentHelper.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AggregatedMiniPoolReservesData} from "contracts/interfaces/IAsteraDataProvider2.sol";
import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {LendingPoolV2} from "tests/foundry/helpers/LendingPoolV2.sol";
import {LendingPoolConfiguratorV2} from "tests/foundry/helpers/LendingPoolConfiguratorV2.sol";
import {FixReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/lendingpool/FixReserveInterestRateStrategy.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";

// Tests all the functions in CorePoolDeploymentHelper
contract CorePoolDeploymentHelperTest is Test {
    address constant ORACLE = 0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87;
    address constant LENDING_POOL_ADDRESS_PROVIDER = 0x9a460e7BD6D5aFCEafbE795e05C48455738fB119;
    address constant LENDING_POOL_CONFIGURATOR = 0x5af0d031A3dA7c2D3b1fA9F00683004F176c28d0;
    address constant DATA_PROVIDER = 0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e;
    CorePoolDeploymentHelper helper;

    address constant LENDING_POOL = 0x17d8a5305A37fe93E13a28f09c46db5bE24E1B9E;
    address constant ADMIN = 0x7D66a2e916d79c0988D41F1E50a1429074ec53a4;

    function setUp() public {
        // LINEA setup
        string memory lineaRpc = vm.envString("LINEA_RPC_URL");
        uint256 opFork = vm.createSelectFork(lineaRpc);
        assertEq(vm.activeFork(), opFork);
        helper = new CorePoolDeploymentHelper(
            ORACLE, LENDING_POOL_ADDRESS_PROVIDER, LENDING_POOL_CONFIGURATOR, DATA_PROVIDER
        );
    }

    function testRecoverScenario() public {
        FixReserveInterestRateStrategy fixReserveInterestRateStrategy =
            new FixReserveInterestRateStrategy(0);
        console2.log(
            "---------------------------- BEFORE STRAT CHANGE: --------------------------------------"
        );
        AggregatedMainPoolReservesData memory data = AsteraDataProvider2(DATA_PROVIDER)
            .getAggregatedMainPoolReserveData(0xA219439258ca9da29E9Cc4cE5596924745e12B93, true);
        logAggregatedMainPoolReservesData(data);
        vm.prank(0x7D66a2e916d79c0988D41F1E50a1429074ec53a4);
        ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setReserveInterestRateStrategyAddress(
            0xA219439258ca9da29E9Cc4cE5596924745e12B93,
            true,
            address(fixReserveInterestRateStrategy)
        );
        console2.log(
            "------------------ AFTER STRAT CHANGE, BEFORE INDEX CHANGE: -------------------------"
        );
        data = AsteraDataProvider2(DATA_PROVIDER).getAggregatedMainPoolReserveData(
            0xA219439258ca9da29E9Cc4cE5596924745e12B93, true
        );
        logAggregatedMainPoolReservesData(data);

        vm.startPrank(0x7D66a2e916d79c0988D41F1E50a1429074ec53a4);
        LendingPoolV2 lendingPool = new LendingPoolV2();
        lendingPool.initialize(0x9a460e7BD6D5aFCEafbE795e05C48455738fB119);
        ILendingPoolAddressesProvider(0x9a460e7BD6D5aFCEafbE795e05C48455738fB119).setLendingPoolImpl(
            address(lendingPool)
        );
        console2.log("New LendingPool impl: ", address(lendingPool));

        LendingPoolV2(LENDING_POOL).setIndexUsdt(1e27); // example value (can be value before the hack)
        vm.stopPrank();
        console2.log("------------------ AFTER INDEX CHANGE: -------------------------");
        data = AsteraDataProvider2(DATA_PROVIDER).getAggregatedMainPoolReserveData(
            0xA219439258ca9da29E9Cc4cE5596924745e12B93, true
        );
        logAggregatedMainPoolReservesData(data);

        /* After this we can update lending pool to its original impl again */
    }

    function logAggregatedMainPoolReservesData(AggregatedMainPoolReservesData memory data)
        internal
        view
    {
        console2.log("underlyingAsset: %s", data.underlyingAsset);
        console2.log("name: %s", data.name);
        console2.log("symbol: %s", data.symbol);
        console2.log("decimals: %d", data.decimals);
        console2.log("baseLTVasCollateral: %d", data.baseLTVasCollateral);
        console2.log("reserveLiquidationThreshold: %d", data.reserveLiquidationThreshold);
        console2.log("reserveLiquidationBonus: %d", data.reserveLiquidationBonus);
        console2.log("asteraReserveFactor: %d", data.asteraReserveFactor);
        console2.log("miniPoolOwnerReserveFactor: %d", data.miniPoolOwnerReserveFactor);
        console2.log("depositCap: %d", data.depositCap);
        console2.log("usageAsCollateralEnabled: %s", data.usageAsCollateralEnabled);
        console2.log("borrowingEnabled: %s", data.borrowingEnabled);
        console2.log("flashloanEnabled: %s", data.flashloanEnabled);
        console2.log("isActive: %s", data.isActive);
        console2.log("isFrozen: %s", data.isFrozen);
        console2.log("reserveType: %s", data.reserveType);
        console2.log("liquidityIndex: %d", data.liquidityIndex);
        console2.log("variableBorrowIndex: %d", data.variableBorrowIndex);
        console2.log("liquidityRate: %d", data.liquidityRate);
        console2.log("variableBorrowRate: %d", data.variableBorrowRate);
        console2.log("lastUpdateTimestamp: %d", data.lastUpdateTimestamp);
        console2.log("aTokenAddress: %s", data.aTokenAddress);
        console2.log("variableDebtTokenAddress: %s", data.variableDebtTokenAddress);
        console2.log("interestRateStrategyAddress: %s", data.interestRateStrategyAddress);
        console2.log("id: %d", data.id);
        console2.log("availableLiquidity: %d", data.availableLiquidity);
        console2.log("totalScaledVariableDebt: %d", data.totalScaledVariableDebt);
        console2.log("priceInMarketReferenceCurrency: %d", data.priceInMarketReferenceCurrency);
        console2.log("ATokenNonRebasingAddress: %s", data.ATokenNonRebasingAddress);
        console2.log("optimalUtilizationRate: %d", data.optimalUtilizationRate);
        console2.log("kp: %d", data.kp);
        console2.log("ki: %d", data.ki);
        console2.log("lastPiReserveRateStrategyUpdate: %d", data.lastPiReserveRateStrategyUpdate);
        console2.log("errI: %d", data.errI);
        console2.log("minControllerError: %d", data.minControllerError);
        console2.log("maxErrIAmp: %d", data.maxErrIAmp);
        console2.log("baseVariableBorrowRate: %d", data.baseVariableBorrowRate);
        console2.log("variableRateSlope1: %d", data.variableRateSlope1);
        console2.log("variableRateSlope2: %d", data.variableRateSlope2);
        console2.log("maxVariableBorrowRate: %d", data.maxVariableBorrowRate);
    }

    function testCoreCurrentDeployments() public {
        // ILendingPoolConfigurator.InitReserveInput[] memory reserves =
        //     new ILendingPoolConfigurator.InitReserveInput[](1);
        // reserves[0] = ILendingPoolConfigurator.InitReserveInput({
        //     aTokenImpl: 0xD9A4A543BDB78B3E3D546495b70643411aEB4231,
        //     variableDebtTokenImpl: 0xE5c7D2714C2b9B1403BF1f2db9dc8e636E0aE23e,
        //     underlyingAssetDecimals: 6,
        //     interestRateStrategyAddress: 0x2EE561275373C2be98BD5A43845C4e61947e4414,
        //     underlyingAsset: 0xacA92E438df0B2401fF60dA7E4337B687a2435DA,
        //     treasury: 0x7D66a2e916d79c0988D41F1E50a1429074ec53a4,
        //     incentivesController: 0x0000000000000000000000000000000000000000,
        //     underlyingAssetName: "MetaMask USD",
        //     reserveType: true,
        //     aTokenName: "Astera MetaMask USD",
        //     aTokenSymbol: "as-mUSD",
        //     variableDebtTokenName: "Astera variable debt bearing MetaMask USD",
        //     variableDebtTokenSymbol: "asDebt-mUSD",
        //     params: "0x10"
        // });
        // vm.startPrank(ADMIN);
        // ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).batchInitReserve(reserves);
        // ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).disableBorrowingOnReserve(
        //     0xacA92E438df0B2401fF60dA7E4337B687a2435DA, true
        // );
        // ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).configureReserveAsCollateral(
        //     0xacA92E438df0B2401fF60dA7E4337B687a2435DA, true, 8500, 9000, 10800
        // );
        // IERC20(0xacA92E438df0B2401fF60dA7E4337B687a2435DA).approve(LENDING_POOL, 50000000);
        // ILendingPool(LENDING_POOL).deposit(
        //     0xacA92E438df0B2401fF60dA7E4337B687a2435DA, true, 30000000, ADMIN
        // );
        // ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).enableBorrowingOnReserve(
        //     0xacA92E438df0B2401fF60dA7E4337B687a2435DA, true
        // );
        // ILendingPool(LENDING_POOL).borrow(
        //     0xacA92E438df0B2401fF60dA7E4337B687a2435DA, true, 20000000, ADMIN
        // );
        // ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setAsteraReserveFactor(
        //     0xacA92E438df0B2401fF60dA7E4337B687a2435DA, true, 2000
        // );

        // ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setReserveInterestRateStrategyAddress(
        //     0x3aAB2285ddcDdaD8edf438C1bAB47e1a9D05a9b4,
        //     true,
        //     0x86944729C689d157029431915d0DaD7e3141B253
        // );
        // ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setReserveInterestRateStrategyAddress(
        //     0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f,
        //     true,
        //     0xd23a965E5A908Ea74928fb7498581716d21981Bd
        // );
        // ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setReserveInterestRateStrategyAddress(
        //     0x176211869cA2b568f2A7D4EE941E073a821EE1ff,
        //     true,
        //     0x8C27EeD160F19D8A0994C3c3263BE29DAA4BC41b
        // );
        // ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setReserveInterestRateStrategyAddress(
        //     0xA219439258ca9da29E9Cc4cE5596924745e12B93,
        //     true,
        //     0x060CBbe312ddBcE76eA4d41973D081406aE0ac11
        // );
        // vm.stopPrank();

        /* LendingPool */
        CorePoolDeploymentHelper.HelperPoolReserversConfig[] memory desiredReserves =
            new CorePoolDeploymentHelper.HelperPoolReserversConfig[](6);
        /* was-WBTC */
        desiredReserves[0] = CorePoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0x86944729C689d157029431915d0DaD7e3141B253,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 1,
            tokenAddress: 0x3aAB2285ddcDdaD8edf438C1bAB47e1a9D05a9b4,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 70e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000,
            reserveType: true
        });
        /* was-WETH */
        desiredReserves[1] = CorePoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0xd23a965E5A908Ea74928fb7498581716d21981Bd,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 70e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000,
            reserveType: true
        });
        /* was-USDC */
        desiredReserves[2] = CorePoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x8C27EeD160F19D8A0994C3c3263BE29DAA4BC41b,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x176211869cA2b568f2A7D4EE941E073a821EE1ff,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000,
            reserveType: true
        });
        /* was-USDT */
        desiredReserves[3] = CorePoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x060CBbe312ddBcE76eA4d41973D081406aE0ac11,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xA219439258ca9da29E9Cc4cE5596924745e12B93,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000,
            reserveType: true
        });
        /* asUSD */
        desiredReserves[4] = CorePoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x3E3b86326b5D1cDA3Ef97Db463b9Df6f94C395DB,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xa500000000e482752f032eA387390b6025a2377b,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000,
            reserveType: false
        });
        /* mUSD */
        desiredReserves[5] = CorePoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x2EE561275373C2be98BD5A43845C4e61947e4414,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xacA92E438df0B2401fF60dA7E4337B687a2435DA,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000,
            reserveType: true
        });
        (uint256 errCode, uint8 idx) = helper.checkDeploymentParams(desiredReserves);
        console2.log("Err code: %s idx: %s", errCode, idx);
        assertEq(errCode, 0);
    }

    // function testDeployNewMiniPoolInitAndConfigure() public view {
    //     IMiniPoolConfigurator.InitReserveInput[] memory _initInputParams =
    //         new IMiniPoolConfigurator.InitReserveInput[](4);
    //     _initInputParams[0] = IMiniPoolConfigurator.InitReserveInput({
    //         underlyingAssetDecimals: 8,
    //         interestRateStrategyAddress: 0x47968bf518FB5A3f4360DE36B67497e11b6C0872,
    //         underlyingAsset: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b,
    //         underlyingAssetName: "Wrapped Astera WBTC",
    //         underlyingAssetSymbol: "was-WBTC"
    //     });

    //     _initInputParams[1] = IMiniPoolConfigurator.InitReserveInput({
    //         underlyingAssetDecimals: 18,
    //         interestRateStrategyAddress: 0xE27379F420990791a56159D54F9bad8864F217b8,
    //         underlyingAsset: 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A,
    //         underlyingAssetName: "Wrapped Astera WETH",
    //         underlyingAssetSymbol: "was-WETH"
    //     });

    //     _initInputParams[2] = IMiniPoolConfigurator.InitReserveInput({
    //         underlyingAssetDecimals: 6,
    //         interestRateStrategyAddress: 0x488D8e33f20bDc1C698632617331e68647128311,
    //         underlyingAsset: 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944,
    //         underlyingAssetName: "Wrapped Astera USDC",
    //         underlyingAssetSymbol: "was-USDC"
    //     });

    //     _initInputParams[3] = IMiniPoolConfigurator.InitReserveInput({
    //         underlyingAssetDecimals: 6,
    //         interestRateStrategyAddress: 0x6c24D7aF724E1F73CE2D26c6c6b4044f4a9d0a43,
    //         underlyingAsset: 0x1579072d23FB3f545016Ac67E072D37e1281624C,
    //         underlyingAssetName: "Wrapped Astera USDT",
    //         underlyingAssetSymbol: "was-USDT"
    //     });

    //     CorePoolDeploymentHelper.HelperPoolReserversConfig[] memory _reservesConfig =
    //         new CorePoolDeploymentHelper.HelperPoolReserversConfig[](4);
    //     _reservesConfig[0] = CorePoolDeploymentHelper.HelperPoolReserversConfig({
    //         baseLtv: 7500,
    //         borrowingEnabled: true,
    //         interestStrat: 0x47968bf518FB5A3f4360DE36B67497e11b6C0872,
    //         liquidationBonus: 10800,
    //         liquidationThreshold: 8000,
    //         miniPoolOwnerFee: 0,
    //         reserveFactor: 2000,
    //         depositCap: 1,
    //         tokenAddress: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b
    //     });
    // helper.deployNewMiniPoolInitAndConfigure(
    //     0xfe3eA78Ec5E8D04d8992c84e43aaF508dE484646,
    //     0xD3dEe63342D0b2Ba5b508271008A81ac0114241C,
    //     0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f,
    //     _initInputParams,
    //     _reservesConfig
    // );
    // }

    // function test_SetReserveFactorForAssets() public {
    //     address[] memory assets = new address[](2);
    //     uint256[] memory reserveFactors = new uint256[](2);
    //     assets[0] = 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b;
    //     assets[1] = 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A;
    //     // assets[2] = 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944;
    //     // assets[3] = 0x1579072d23FB3f545016Ac67E072D37e1281624C;

    //     reserveFactors[0] = 1000;
    //     reserveFactors[1] = 2001;
    //     // reserveFactors[2] = 3000;
    //     // reserveFactors[3] = 4000;

    //     AggregatedMiniPoolReservesData[] memory data =
    //         AsteraDataProvider2(DATA_PROVIDER).getMiniPoolReservesData(MINI_POOL);

    //     console2.log("Data length", data.length);

    //     uint256[] memory previousReserveFactor = new uint256[](2);
    //     for (uint256 idx = 0; idx < data.length; idx++) {
    //         for (uint256 i = 0; i < assets.length; i++) {
    //             if (data[idx].aTokenNonRebasingAddress == assets[i]) {
    //                 previousReserveFactor[idx] = data[idx].asteraReserveFactor;
    //                 break;
    //             }
    //         }
    //     }

    //     vm.prank(ADMIN);
    //     helper.setReserveFactorsForAssets(assets, reserveFactors, MINI_POOL);

    //     data = AsteraDataProvider2(DATA_PROVIDER).getMiniPoolReservesData(MINI_POOL);

    //     console2.log("Data length", data.length);
    //     console2.log("Assets length", assets.length);

    //     for (uint256 idx = 0; idx < data.length; idx++) {
    //         for (uint256 i = 0; i < assets.length; i++) {
    //             console2.log(
    //                 "data[idx].underlyingAsset %s, assets[i] %s",
    //                 data[idx].aTokenNonRebasingAddress,
    //                 assets[i]
    //             );
    //             if (data[idx].aTokenNonRebasingAddress == assets[i]) {
    //                 console2.log(
    //                     "previousReserveFactor[idx] %s vs data[idx].asteraReserveFactor %s",
    //                     previousReserveFactor[idx],
    //                     data[idx].asteraReserveFactor
    //                 );
    //                 assertNotEq(
    //                     previousReserveFactor[idx],
    //                     data[idx].asteraReserveFactor,
    //                     "Reserve factor didn't change"
    //                 );
    //                 break;
    //             }
    //         }
    //     }
    //     assert(false);
    // }
}
