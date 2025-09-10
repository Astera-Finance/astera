// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.0;

// import {
//     MiniPoolDeploymentHelper,
//     IMiniPoolConfigurator
// } from "contracts/deployments/MiniPoolDeploymentHelper.sol";
// import {Test} from "forge-std/Test.sol";
// import {console2} from "forge-std/console2.sol";

// // Tests all the functions in MiniPoolDeploymentHelper
// contract MiniPoolDeploymentHelperTest is Test {
//     address constant ORACLE = 0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87;
//     address constant MINI_POOL_ADDRESS_PROVIDER = 0x9399aF805e673295610B17615C65b9d0cE1Ed306;
//     address constant MINI_POOL_CONFIGURATOR = 0x41296B58279a81E20aF1c05D32b4f132b72b1B01;
//     address constant DATA_PROVIDER = 0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e;
//     MiniPoolDeploymentHelper helper;

//     function setUp() public {
//         // LINEA setup
//         uint256 opFork = vm.createSelectFork(
//             "https://linea-mainnet.infura.io/v3/f47a8617e11b481fbf52c08d4e9ecf0d"
//         );
//         assertEq(vm.activeFork(), opFork);
//         helper = new MiniPoolDeploymentHelper(
//             ORACLE, MINI_POOL_ADDRESS_PROVIDER, MINI_POOL_CONFIGURATOR, DATA_PROVIDER
//         );
//     }

//     function testCurrentDeployments() public view {
//         MiniPoolDeploymentHelper.HelperPoolReserversConfig[] memory desiredReserves =
//             new MiniPoolDeploymentHelper.HelperPoolReserversConfig[](6);
//         desiredReserves[0] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
//             baseLtv: 7500,
//             borrowingEnabled: true,
//             interestStrat: 0x47968bf518FB5A3f4360DE36B67497e11b6C0872,
//             liquidationBonus: 10800,
//             liquidationThreshold: 8000,
//             miniPoolOwnerFee: 0,
//             reserveFactor: 2000,
//             depositCap: 1,
//             tokenAddress: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b
//         });
//         desiredReserves[1] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
//             baseLtv: 7500,
//             borrowingEnabled: true,
//             interestStrat: 0xE27379F420990791a56159D54F9bad8864F217b8,
//             liquidationBonus: 10800,
//             liquidationThreshold: 8000,
//             miniPoolOwnerFee: 0,
//             reserveFactor: 2000,
//             depositCap: 0,
//             tokenAddress: 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A
//         });
//         desiredReserves[2] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
//             baseLtv: 8500,
//             borrowingEnabled: true,
//             interestStrat: 0x499685b9A2438D0aBc36EBedaf966A2c9B18C3c0,
//             liquidationBonus: 10800,
//             liquidationThreshold: 9000,
//             miniPoolOwnerFee: 0,
//             reserveFactor: 2000,
//             depositCap: 0,
//             tokenAddress: 0xa500000000e482752f032eA387390b6025a2377b
//         });
//         desiredReserves[3] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
//             baseLtv: 5000,
//             borrowingEnabled: true,
//             interestStrat: 0xc3012640D1d6cE061632f4cea7f52360d50cbeD4,
//             liquidationBonus: 11500,
//             liquidationThreshold: 6500,
//             miniPoolOwnerFee: 0,
//             reserveFactor: 2000,
//             depositCap: 2500000,
//             tokenAddress: 0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4
//         });
//         desiredReserves[4] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
//             baseLtv: 8500,
//             borrowingEnabled: true,
//             interestStrat: 0x488D8e33f20bDc1C698632617331e68647128311,
//             liquidationBonus: 10800,
//             liquidationThreshold: 9000,
//             miniPoolOwnerFee: 0,
//             reserveFactor: 2000,
//             depositCap: 0,
//             tokenAddress: 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944
//         });
//         desiredReserves[5] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
//             baseLtv: 8500,
//             borrowingEnabled: true,
//             interestStrat: 0x6c24D7aF724E1F73CE2D26c6c6b4044f4a9d0a43,
//             liquidationBonus: 10800,
//             liquidationThreshold: 9000,
//             miniPoolOwnerFee: 0,
//             reserveFactor: 2000,
//             depositCap: 0,
//             tokenAddress: 0x1579072d23FB3f545016Ac67E072D37e1281624C
//         });
//         (uint256 errCode, uint8 idx) = helper.checkDeploymentParams(
//             0x65559abECD1227Cc1779F500453Da1f9fcADd928, desiredReserves
//         );
//         console2.log("Err code: %s idx: %s", errCode, idx);
//         assertEq(errCode, 0);
//     }

//     function testDeployNewMiniPoolInitAndConfigure() public view {
//         IMiniPoolConfigurator.InitReserveInput[] memory _initInputParams =
//             new IMiniPoolConfigurator.InitReserveInput[](4);
//         _initInputParams[0] = IMiniPoolConfigurator.InitReserveInput({
//             underlyingAssetDecimals: 8,
//             interestRateStrategyAddress: 0x47968bf518FB5A3f4360DE36B67497e11b6C0872,
//             underlyingAsset: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b,
//             underlyingAssetName: "Wrapped Astera WBTC",
//             underlyingAssetSymbol: "was-WBTC"
//         });

//         _initInputParams[1] = IMiniPoolConfigurator.InitReserveInput({
//             underlyingAssetDecimals: 18,
//             interestRateStrategyAddress: 0xE27379F420990791a56159D54F9bad8864F217b8,
//             underlyingAsset: 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A,
//             underlyingAssetName: "Wrapped Astera WETH",
//             underlyingAssetSymbol: "was-WETH"
//         });

//         _initInputParams[2] = IMiniPoolConfigurator.InitReserveInput({
//             underlyingAssetDecimals: 6,
//             interestRateStrategyAddress: 0x488D8e33f20bDc1C698632617331e68647128311,
//             underlyingAsset: 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944,
//             underlyingAssetName: "Wrapped Astera USDC",
//             underlyingAssetSymbol: "was-USDC"
//         });

//         _initInputParams[3] = IMiniPoolConfigurator.InitReserveInput({
//             underlyingAssetDecimals: 6,
//             interestRateStrategyAddress: 0x6c24D7aF724E1F73CE2D26c6c6b4044f4a9d0a43,
//             underlyingAsset: 0x1579072d23FB3f545016Ac67E072D37e1281624C,
//             underlyingAssetName: "Wrapped Astera USDT",
//             underlyingAssetSymbol: "was-USDT"
//         });

//         MiniPoolDeploymentHelper.HelperPoolReserversConfig[] memory _reservesConfig =
//             new MiniPoolDeploymentHelper.HelperPoolReserversConfig[](4);
//         _reservesConfig[0] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
//             baseLtv: 7500,
//             borrowingEnabled: true,
//             interestStrat: 0x47968bf518FB5A3f4360DE36B67497e11b6C0872,
//             liquidationBonus: 10800,
//             liquidationThreshold: 8000,
//             miniPoolOwnerFee: 0,
//             reserveFactor: 2000,
//             depositCap: 1,
//             tokenAddress: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b
//         });
//         // helper.deployNewMiniPoolInitAndConfigure(
//         //     0xfe3eA78Ec5E8D04d8992c84e43aaF508dE484646,
//         //     0xD3dEe63342D0b2Ba5b508271008A81ac0114241C,
//         //     0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f,
//         //     _initInputParams,
//         //     _reservesConfig
//         // );
//     }
// }
