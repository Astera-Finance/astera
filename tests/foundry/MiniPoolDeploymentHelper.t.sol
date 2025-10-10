// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

// import {
//     MiniPoolDeploymentHelper,
//     IMiniPoolConfigurator
// } from "contracts/deployments/MiniPoolDeploymentHelper.sol";
import {IMiniPoolConfigurator} from "contracts/interfaces/IMiniPoolConfigurator.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AggregatedMiniPoolReservesData} from "contracts/interfaces/IAsteraDataProvider2.sol";
import {MiniPoolDefaultReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {AsteraDataProvider2} from "contracts/misc/AsteraDataProvider2.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";

// Tests all the functions in MiniPoolDeploymentHelper
contract MiniPoolDeploymentHelperTest is Test {
    address constant ORACLE = 0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87;
    address constant MINI_POOL_ADDRESS_PROVIDER = 0x9399aF805e673295610B17615C65b9d0cE1Ed306;
    address constant MINI_POOL_CONFIGURATOR = 0x41296B58279a81E20aF1c05D32b4f132b72b1B01;
    address constant DATA_PROVIDER = 0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e;
    // MiniPoolDeploymentHelper helper;

    function setUp() public {
        // LINEA setup
        uint256 opFork = vm.createSelectFork(
            "https://linea-mainnet.infura.io/v3/f47a8617e11b481fbf52c08d4e9ecf0d"
        );
        assertEq(vm.activeFork(), opFork);
        // helper = new MiniPoolDeploymentHelper(
        //     ORACLE, MINI_POOL_ADDRESS_PROVIDER, MINI_POOL_CONFIGURATOR, DATA_PROVIDER
        // );
    }

    function testMiniPoolInterestRateStrat() public {
        MiniPoolDefaultReserveInterestRateStrategy miniPoolDefaultReserveInterestRateStrategy = new MiniPoolDefaultReserveInterestRateStrategy(
            IMiniPoolAddressesProvider(0x9399aF805e673295610B17615C65b9d0cE1Ed306), 1e27, 0, 0, 0
        );
        console2.log("---------------------------- BEFORE: --------------------------------------");
        AggregatedMiniPoolReservesData memory data = AsteraDataProvider2(DATA_PROVIDER)
            .getReserveDataForAssetAtMiniPool(
            0x1579072d23FB3f545016Ac67E072D37e1281624C, 0xE7a2c97601076065C3178BDbb22C61933f850B03
        );
        logAggregatedMiniPoolReservesData(data);
        vm.prank(0x7D66a2e916d79c0988D41F1E50a1429074ec53a4);
        IMiniPoolConfigurator(MINI_POOL_CONFIGURATOR).setReserveInterestRateStrategyAddress(
            0x1579072d23FB3f545016Ac67E072D37e1281624C,
            address(miniPoolDefaultReserveInterestRateStrategy),
            IMiniPool(0xE7a2c97601076065C3178BDbb22C61933f850B03)
        );
        console2.log("------------------ AFTER: -------------------------");
        data = AsteraDataProvider2(DATA_PROVIDER).getReserveDataForAssetAtMiniPool(
            0x1579072d23FB3f545016Ac67E072D37e1281624C, 0xE7a2c97601076065C3178BDbb22C61933f850B03
        );
        logAggregatedMiniPoolReservesData(data);
    }

    function testDecodeHexMessage() public {
        // Hex string without 0x prefix, example truncated for brevity
        string memory hexString =
            "486920e2809420746869732069732074686520417374657261205465616d2e0a5765277265207265616368696e67206f757420726567617264696e67207468652031302f30392f3230323520736563757269747920696e636964656e7420616666656374696e67204173746572612c207768657265207e243830302c30303020776572652072656d6f7665642066726f6d206f7572206d61726b6574732e0a0a4f7572207072696f72697479206973206120717569636b2c20736166652072657475726e20666f722075736572732e205765277265206f66666572696e6720796f7520612031302520776869746568617420626f756e747920696620796f752072657475726e20393025206f66207468652066756e64732077697468696e20343820686f757273206f662074686973206d657373616765206265696e67207472616e736d69747465642e0a0a496620796f7520646f20746869732c2077652077696c6c3a0a2d20416363657074207468617420796f752077696c6c2072657461696e2074686520313025206465736372696265642061626f76652061732061206665650a2d204e6f7420707572737565206675727468657220616374696f6e20746f207468652066756c6c65737420657874656e742077697468696e206f757220636f6e74726f6c2028636976696c2c206372696d696e616c2c206f7220696e7665737469676174697665292e0a0a496620796f7520616772656520746f207468657365207465726d732c20706c65617365207375626d69742034207369676e6564204552433230207472616e736665722829207472616e73616374696f6e73206f6e2d636861696e2c207265706c6163696e6720796f75722063757272656e742070656e64696e67207472616e73616374696f6e2e0a0a5468657365207472616e73666572732073686f756c642072657475726e204c494e45412c20574554482c20555344542c20616e642061735553442074616b656e20647572696e6720746865206578706c6f697420746f204173746572612773204c696e6561206d756c74697369672c206d696e75732074686520313025206665652e205b3078374436366132653931366437396330393838443431463145353061313432393037346563353361345d2e0a0a466f7220617373697374616e63652c207265616368206f757420746f20406a6263727970746f3935206f6e2074656c656772616d206f7220656d61696c20626562697340636f6e636c6176652e696f";

        bytes memory decodedBytes = hexStringToBytes(hexString);
        string memory decodedString = string(decodedBytes);

        emit log_string(decodedString);
    }

    // Convert hex string to bytes
    function hexStringToBytes(string memory s) public pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0, "hex string length must be even");
        bytes memory r = new bytes(ss.length / 2);
        for (uint256 i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(fromHexChar(uint8(ss[2 * i])) * 16 + fromHexChar(uint8(ss[2 * i + 1])));
        }
        return r;
    }

    // Helper to convert a hex character to its value
    function fromHexChar(uint8 c) public pure returns (uint8) {
        if (c >= 48 && c <= 57) {
            return c - 48;
        }
        if (c >= 65 && c <= 70) {
            return c - 55;
        }
        if (c >= 97 && c <= 102) {
            return c - 87;
        }
        revert("invalid hex char");
    }

    function logAggregatedMiniPoolReservesData(AggregatedMiniPoolReservesData memory d)
        internal
        view
    {
        console2.log("underlyingAsset:", d.underlyingAsset);
        console2.log("name:", d.name);
        console2.log("symbol:", d.symbol);
        console2.log("aTokenId:", d.aTokenId);
        console2.log("debtTokenId:", d.debtTokenId);
        console2.log("isTranche:", d.isTranche);
        console2.log("aTokenNonRebasingAddress:", d.aTokenNonRebasingAddress);
        console2.log("decimals:", d.decimals);
        console2.log("baseLTVasCollateral:", d.baseLTVasCollateral);
        console2.log("reserveLiquidationThreshold:", d.reserveLiquidationThreshold);
        console2.log("reserveLiquidationBonus:", d.reserveLiquidationBonus);
        console2.log("asteraReserveFactor:", d.asteraReserveFactor);
        console2.log("miniPoolOwnerReserveFactor:", d.miniPoolOwnerReserveFactor);
        console2.log("depositCap:", d.depositCap);
        console2.log("usageAsCollateralEnabled:", d.usageAsCollateralEnabled);
        console2.log("borrowingEnabled:", d.borrowingEnabled);
        console2.log("flashloanEnabled:", d.flashloanEnabled);
        console2.log("isActive:", d.isActive);
        console2.log("isFrozen:", d.isFrozen);
        console2.log("liquidityIndex:", d.liquidityIndex);
        console2.log("variableBorrowIndex:", d.variableBorrowIndex);
        console2.log("liquidityRate:", d.liquidityRate);
        console2.log("variableBorrowRate:", d.variableBorrowRate);
        console2.log("lastUpdateTimestamp:", d.lastUpdateTimestamp);
        console2.log("interestRateStrategyAddress:", d.interestRateStrategyAddress);
        console2.log("availableLiquidity:", d.availableLiquidity);
        console2.log("totalScaledVariableDebt:", d.totalScaledVariableDebt);
        console2.log("priceInMarketReferenceCurrency:", d.priceInMarketReferenceCurrency);
        console2.log("optimalUtilizationRate:", d.optimalUtilizationRate);
        console2.log("kp:", d.kp);
        console2.log("ki:", d.ki);
        console2.log("lastPiReserveRateStrategyUpdate:", d.lastPiReserveRateStrategyUpdate);
        console2.log("errI:", d.errI);
        console2.log("minControllerError:", d.minControllerError);
        console2.log("maxErrIAmp:", d.maxErrIAmp);
        console2.log("baseVariableBorrowRate:", d.baseVariableBorrowRate);
        console2.log("variableRateSlope1:", d.variableRateSlope1);
        console2.log("variableRateSlope2:", d.variableRateSlope2);
        console2.log("maxVariableBorrowRate:", d.maxVariableBorrowRate);
        console2.log("availableFlow:", d.availableFlow);
        console2.log("flowLimit:", d.flowLimit);
        console2.log("currentFlow:", d.currentFlow);
    }
}
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
