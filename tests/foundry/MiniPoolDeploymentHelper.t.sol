// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {
    MiniPoolDeploymentHelper,
    IMiniPoolConfigurator,
    AsteraDataProvider2
} from "contracts/deployments/MiniPoolDeploymentHelper.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AggregatedMiniPoolReservesData} from "contracts/interfaces/IAsteraDataProvider2.sol";

// Tests all the functions in MiniPoolDeploymentHelper
contract MiniPoolDeploymentHelperTest is Test {
    address constant ORACLE = 0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87;
    address constant MINI_POOL_ADDRESS_PROVIDER = 0x9399aF805e673295610B17615C65b9d0cE1Ed306;
    address constant MINI_POOL_CONFIGURATOR = 0x41296B58279a81E20aF1c05D32b4f132b72b1B01;
    address constant DATA_PROVIDER = 0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e;
    MiniPoolDeploymentHelper helper;

    address constant MINI_POOL = 0x52280eA8979d52033E14df086F4dF555a258bEb4;
    address constant ADMIN = 0x7D66a2e916d79c0988D41F1E50a1429074ec53a4;

    function setUp() public {
        // LINEA setup
        uint256 opFork = vm.createSelectFork(
            "https://linea-mainnet.infura.io/v3/f47a8617e11b481fbf52c08d4e9ecf0d"
        );
        assertEq(vm.activeFork(), opFork);
        helper = new MiniPoolDeploymentHelper(
            ORACLE, MINI_POOL_ADDRESS_PROVIDER, MINI_POOL_CONFIGURATOR, DATA_PROVIDER
        );
    }

    function testCurrentDeployments() public view {
        MiniPoolDeploymentHelper.HelperPoolReserversConfig[] memory desiredReserves =
            new MiniPoolDeploymentHelper.HelperPoolReserversConfig[](6);
        desiredReserves[0] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0x2fDdcaA16cE32dEe94bAb649cfF007d949688695,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 1,
            tokenAddress: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b
        });
        desiredReserves[1] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0xddD8e5DabEAFa69c4717710072692F041b081f0a,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A
        });

        desiredReserves[2] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x3D20691a0BF115Ae4134f6D2ecf1BA2c5C77484f,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944
        });
        desiredReserves[3] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0xE27da48971de86167e78519aD1120cF315E82E93,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x1579072d23FB3f545016Ac67E072D37e1281624C
        });
        desiredReserves[4] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x07C8b3B605C29bAD6e7fDD2b5912Dfa506a6806c,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xa500000000e482752f032eA387390b6025a2377b
        });
        desiredReserves[5] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0xa91e6190dDde5E4D501ABf9611d6640d9092b32d,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xacA92E438df0B2401fF60dA7E4337B687a2435DA
        });
        (uint256 errCode, uint8 idx) = helper.checkDeploymentParams(MINI_POOL, desiredReserves);
        console2.log("Err code: %s idx: %s", errCode, idx);
        assertEq(errCode, 0);
    }

    function testDeployNewMiniPoolInitAndConfigure() public view {
        IMiniPoolConfigurator.InitReserveInput[] memory _initInputParams =
            new IMiniPoolConfigurator.InitReserveInput[](4);
        _initInputParams[0] = IMiniPoolConfigurator.InitReserveInput({
            underlyingAssetDecimals: 8,
            interestRateStrategyAddress: 0x47968bf518FB5A3f4360DE36B67497e11b6C0872,
            underlyingAsset: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b,
            underlyingAssetName: "Wrapped Astera WBTC",
            underlyingAssetSymbol: "was-WBTC"
        });

        _initInputParams[1] = IMiniPoolConfigurator.InitReserveInput({
            underlyingAssetDecimals: 18,
            interestRateStrategyAddress: 0xE27379F420990791a56159D54F9bad8864F217b8,
            underlyingAsset: 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A,
            underlyingAssetName: "Wrapped Astera WETH",
            underlyingAssetSymbol: "was-WETH"
        });

        _initInputParams[2] = IMiniPoolConfigurator.InitReserveInput({
            underlyingAssetDecimals: 6,
            interestRateStrategyAddress: 0x488D8e33f20bDc1C698632617331e68647128311,
            underlyingAsset: 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944,
            underlyingAssetName: "Wrapped Astera USDC",
            underlyingAssetSymbol: "was-USDC"
        });

        _initInputParams[3] = IMiniPoolConfigurator.InitReserveInput({
            underlyingAssetDecimals: 6,
            interestRateStrategyAddress: 0x6c24D7aF724E1F73CE2D26c6c6b4044f4a9d0a43,
            underlyingAsset: 0x1579072d23FB3f545016Ac67E072D37e1281624C,
            underlyingAssetName: "Wrapped Astera USDT",
            underlyingAssetSymbol: "was-USDT"
        });

        MiniPoolDeploymentHelper.HelperPoolReserversConfig[] memory _reservesConfig =
            new MiniPoolDeploymentHelper.HelperPoolReserversConfig[](4);
        _reservesConfig[0] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0x47968bf518FB5A3f4360DE36B67497e11b6C0872,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 1,
            tokenAddress: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b
        });
        // helper.deployNewMiniPoolInitAndConfigure(
        //     0xfe3eA78Ec5E8D04d8992c84e43aaF508dE484646,
        //     0xD3dEe63342D0b2Ba5b508271008A81ac0114241C,
        //     0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f,
        //     _initInputParams,
        //     _reservesConfig
        // );
    }

    function test_SetReserveFactorForAssets() public {
        address[] memory assets = new address[](2);
        uint256[] memory reserveFactors = new uint256[](2);
        assets[0] = 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b;
        assets[1] = 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A;
        // assets[2] = 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944;
        // assets[3] = 0x1579072d23FB3f545016Ac67E072D37e1281624C;

        reserveFactors[0] = 1000;
        reserveFactors[1] = 2001;
        // reserveFactors[2] = 3000;
        // reserveFactors[3] = 4000;

        AggregatedMiniPoolReservesData[] memory data =
            AsteraDataProvider2(DATA_PROVIDER).getMiniPoolReservesData(MINI_POOL);

        console2.log("Data length", data.length);

        uint256[] memory previousReserveFactor = new uint256[](2);
        for (uint256 idx = 0; idx < data.length; idx++) {
            for (uint256 i = 0; i < assets.length; i++) {
                if (data[idx].aTokenNonRebasingAddress == assets[i]) {
                    previousReserveFactor[idx] = data[idx].asteraReserveFactor;
                    break;
                }
            }
        }

        vm.prank(ADMIN);
        helper.setReserveFactorsForAssets(assets, reserveFactors, MINI_POOL);

        data = AsteraDataProvider2(DATA_PROVIDER).getMiniPoolReservesData(MINI_POOL);

        console2.log("Data length", data.length);
        console2.log("Assets length", assets.length);

        for (uint256 idx = 0; idx < data.length; idx++) {
            for (uint256 i = 0; i < assets.length; i++) {
                console2.log(
                    "data[idx].underlyingAsset %s, assets[i] %s",
                    data[idx].aTokenNonRebasingAddress,
                    assets[i]
                );
                if (data[idx].aTokenNonRebasingAddress == assets[i]) {
                    console2.log(
                        "previousReserveFactor[idx] %s vs data[idx].asteraReserveFactor %s",
                        previousReserveFactor[idx],
                        data[idx].asteraReserveFactor
                    );
                    assertNotEq(
                        previousReserveFactor[idx],
                        data[idx].asteraReserveFactor,
                        "Reserve factor didn't change"
                    );
                    break;
                }
            }
        }
        assert(false);
    }
}
