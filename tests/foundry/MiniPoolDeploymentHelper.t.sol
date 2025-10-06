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

    address constant AS_USD_MINI_POOL = 0xE7a2c97601076065C3178BDbb22C61933f850B03;
    address constant LST_MINI_POOL = 0x0baFB30B72925e6d53F4d0A089bE1CeFbB5e3401;
    address constant REX_MINI_POOL = 0x65559abECD1227Cc1779F500453Da1f9fcADd928;
    address constant LINEA_MINI_POOL = 0x52280eA8979d52033E14df086F4dF555a258bEb4;
    address constant ADMIN = 0x7D66a2e916d79c0988D41F1E50a1429074ec53a4;

    function setUp() public {
        // LINEA setup
        string memory lineaRpc = vm.envString("LINEA_RPC_URL");
        uint256 opFork = vm.createSelectFork(lineaRpc);
        assertEq(vm.activeFork(), opFork);
        helper = new MiniPoolDeploymentHelper(
            ORACLE, MINI_POOL_ADDRESS_PROVIDER, MINI_POOL_CONFIGURATOR, DATA_PROVIDER
        );
    }

    function testCurrentDeployments() public view {
        /* asUSD MiniPool */
        MiniPoolDeploymentHelper.HelperPoolReserversConfig[] memory desiredReserves =
            new MiniPoolDeploymentHelper.HelperPoolReserversConfig[](5);
        desiredReserves[0] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0x034eD869b60f54d1F35DD8b5CE6d266D9597c76F,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 1,
            tokenAddress: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 70e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[1] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0xa1d472d7A2D870C0E6472e9CE2fDDC89db5de65F,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 70e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });

        desiredReserves[2] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x9929e7D851d73B9A344a7DA0e9b12a3A4E3803b4,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[3] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0xdbA5Aaf071674863C39DC138605737d2D36093bf,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x1579072d23FB3f545016Ac67E072D37e1281624C,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[4] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x0886376e6f6B766ef8EF96860973233799192B3c,
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
            maxErrIAmp: 1728000
        });
        (uint256 errCode, uint8 idx) =
            helper.checkDeploymentParams(AS_USD_MINI_POOL, desiredReserves);
        console2.log("AsUsd MiniPool Err code: %s idx: %s", errCode, idx);
        assertEq(errCode, 0);

        /* LST MiniPool */
        desiredReserves = new MiniPoolDeploymentHelper.HelperPoolReserversConfig[](9);
        desiredReserves[0] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0x5B30CE761Fa647F0Ea74Ef9cb855774A1567671D,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 1,
            tokenAddress: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 70e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[1] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0x0c39595b1931083435e6d54776fdA1c264c8A1b1,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 70e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });

        desiredReserves[2] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0xb9a9323B3B33d9a2100Eb9B97D8b77dd3944Fe28,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[3] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x91072067549B88f4E0B879eC96d7700Cb7a1CBeD,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x1579072d23FB3f545016Ac67E072D37e1281624C,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[4] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0xaEc6c5dF41946dA7057f4dda28FBCf6b90CFee58,
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
            maxErrIAmp: 1728000
        });
        desiredReserves[5] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7000,
            borrowingEnabled: true,
            interestStrat: 0x10F1892909C85D71A8B4F846cDe6d5B2cBC67ce6,
            liquidationBonus: 10800,
            liquidationThreshold: 7500,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xB5beDd42000b71FddE22D3eE8a79Bd49A568fC8F,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 60e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[6] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7000,
            borrowingEnabled: true,
            interestStrat: 0x8920B92463022e4656535a2e8c763cDb8EBd3403,
            liquidationBonus: 10800,
            liquidationThreshold: 7500,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x1Bf74C010E6320bab11e2e5A532b5AC15e0b8aA6,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 60e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[7] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7000,
            borrowingEnabled: true,
            interestStrat: 0xfe98b09061e7cEb321B7535c8d1A09940d304839,
            liquidationBonus: 10800,
            liquidationThreshold: 7500,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x2416092f143378750bb29b79eD961ab195CcEea5,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 60e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[8] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0xc7cd1C6BA3b0d00438F2FdfB63e5Fe7Fe79a70Fb,
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
            maxErrIAmp: 1728000
        });
        (errCode, idx) = helper.checkDeploymentParams(LST_MINI_POOL, desiredReserves);
        console2.log("LST MiniPool Err code: %s idx: %s", errCode, idx);
        assertEq(errCode, 0);

        /* REX33 MiniPool */

        desiredReserves = new MiniPoolDeploymentHelper.HelperPoolReserversConfig[](8);
        desiredReserves[0] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0xf84BD04862e1a8181651C342001599fb67A9b505,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 1,
            tokenAddress: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 70e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[1] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0x099f499C1ED44fa79522661a2b3C90a2874b15f8,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 70e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[2] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x2fcD50C1550Dd881ae32068ce082e85E76E1B6C8,
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
            maxErrIAmp: 1728000
        });

        desiredReserves[3] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 6500,
            borrowingEnabled: false,
            interestStrat: 0xF8A36D94Bc0705eD0f49788E7Df3B19f3B5b5887,
            liquidationBonus: 11500,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 30_000_000,
            tokenAddress: 0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 30e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[4] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0xAeA7A47E61F5D01902f33507dF025198AD0894F9,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[5] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x20e44a73929263D8e752162B8c0a18430673236e,
            liquidationBonus: 10800,
            liquidationThreshold: 9000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x1579072d23FB3f545016Ac67E072D37e1281624C,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });

        desiredReserves[6] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 8500,
            borrowingEnabled: true,
            interestStrat: 0x10C45E0B2d044f00d6E735192E594cfBC0F9735C,
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
            maxErrIAmp: 1728000
        });
        desiredReserves[7] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 6500,
            borrowingEnabled: true,
            interestStrat: 0x9263519C31DD1ef2320E6168ef29b19a6c56682B,
            liquidationBonus: 11000,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x1789e0043623282D5DCc7F213d703C6D8BAfBB04,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 50e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        (errCode, idx) = helper.checkDeploymentParams(REX_MINI_POOL, desiredReserves);
        console2.log(" REX33 MiniPool Err code: %s idx: %s", errCode, idx);
        assertEq(errCode, 0);

        /* LINEA MiniPool */

        desiredReserves = new MiniPoolDeploymentHelper.HelperPoolReserversConfig[](7);
        desiredReserves[0] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 7500,
            borrowingEnabled: true,
            interestStrat: 0x2fDdcaA16cE32dEe94bAb649cfF007d949688695,
            liquidationBonus: 10800,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 1,
            tokenAddress: 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 70e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
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
            tokenAddress: 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 70e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
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
            tokenAddress: 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
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
            tokenAddress: 0x1579072d23FB3f545016Ac67E072D37e1281624C,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
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
            tokenAddress: 0xa500000000e482752f032eA387390b6025a2377b,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
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
            tokenAddress: 0xacA92E438df0B2401fF60dA7E4337B687a2435DA,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 80e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        desiredReserves[6] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
            baseLtv: 6500,
            borrowingEnabled: true,
            interestStrat: 0x412966b79fB8D33C0F33F1cf3f3c0bE2a73209F1,
            liquidationBonus: 11000,
            liquidationThreshold: 8000,
            miniPoolOwnerFee: 0,
            reserveFactor: 2000,
            depositCap: 0,
            tokenAddress: 0x1789e0043623282D5DCc7F213d703C6D8BAfBB04,
            minControllerError: -552790000000000000000000000,
            optimalUtilizationRate: 50e25,
            kp: 1e27,
            ki: 13e19,
            maxErrIAmp: 1728000
        });
        (errCode, idx) = helper.checkDeploymentParams(LINEA_MINI_POOL, desiredReserves);
        console2.log("Linea Mini Pool Err code: %s idx: %s", errCode, idx);
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

    //     MiniPoolDeploymentHelper.HelperPoolReserversConfig[] memory _reservesConfig =
    //         new MiniPoolDeploymentHelper.HelperPoolReserversConfig[](4);
    //     _reservesConfig[0] = MiniPoolDeploymentHelper.HelperPoolReserversConfig({
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
