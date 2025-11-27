// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AsteraDataProvider2, UserReserveData} from "contracts/misc/AsteraDataProvider2.sol";
import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";
import {
    ILendingPoolAddressesProvider
} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IERC20Detailed} from "contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {MiniPoolV3} from "contracts/protocol/core/minipool/MiniPoolV3.sol";
import {LendingPoolV2} from "contracts/protocol/core/lendingpool/LendingPoolV2.sol";
import {LendingPoolV3} from "contracts/protocol/core/lendingpool/LendingPoolV3.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "contracts/interfaces/IVariableDebtToken.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";
import {IAERC6909} from "contracts/interfaces/IAERC6909.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";
import {IMiniPoolConfigurator} from "contracts/interfaces/IMiniPoolConfigurator.sol";
import {AggregatedMiniPoolReservesData} from "contracts/interfaces/IAsteraDataProvider2.sol";
import {Liquidator} from "contracts/misc/Liquidator.sol";
import {IRouter} from "tests/foundry/interfaces/IRouter.sol";

import {IPair} from "tests/foundry/interfaces/IPair.sol";

import {IOracle} from "contracts/interfaces/IOracle.sol";

import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";

import {
    ReserveConfiguration
} from "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

contract TestBeforeAndAfterAttack is Test {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    address constant DATA_PROVIDER = 0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e;

    address constant LENDING_POOL_CONFIGURATOR = 0x5af0d031A3dA7c2D3b1fA9F00683004F176c28d0;
    address constant ADMIN = 0x7D66a2e916d79c0988D41F1E50a1429074ec53a4;
    address constant EMERGENCY = 0xDa77d6C0281fCb3e41BD966aC393502a1C524224;
    address constant LIQUIDATOR = 0x71C4ebBa016Df7C4B4b23Cf7e8Cc13ef36ddA3a8;

    address constant LENDING_POOL_ADDRESSES_PROVIDER = 0x9a460e7BD6D5aFCEafbE795e05C48455738fB119;
    address constant LENDING_POOL_PROXY = 0x17d8a5305A37fe93E13a28f09c46db5bE24E1B9E;

    address constant MINI_POOL_ADDRESS_PROVIDER = 0x9399aF805e673295610B17615C65b9d0cE1Ed306;
    address constant MINI_POOL_CONFIGURATOR = 0x41296B58279a81E20aF1c05D32b4f132b72b1B01;

    address constant ORACLE = 0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87;

    address constant USDC = 0x176211869cA2b568f2A7D4EE941E073a821EE1ff;
    address constant WETH = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;
    address constant USDT = 0xA219439258ca9da29E9Cc4cE5596924745e12B93;
    address constant WBTC = 0x3aAB2285ddcDdaD8edf438C1bAB47e1a9D05a9b4;
    address constant ASUSD = 0xa500000000e482752f032eA387390b6025a2377b;
    address constant MUSD = 0xacA92E438df0B2401fF60dA7E4337B687a2435DA;
    address constant LINEA = 0x1789e0043623282D5DCc7F213d703C6D8BAfBB04;
    address constant REX33 = 0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4;

    address constant WSTETH = 0xB5beDd42000b71FddE22D3eE8a79Bd49A568fC8F;
    address constant WEETH = 0x1Bf74C010E6320bab11e2e5A532b5AC15e0b8aA6;
    address constant EZETH = 0x2416092f143378750bb29b79eD961ab195CcEea5;

    address constant ASUSDC = 0xcb338D6b4547479F5D11A68572F89A4F3cCa7347;
    address constant ASWETH = 0x78469e135ac38437cD4DfBf096b83f100EcF3260;
    address constant ASUSDT = 0xD66aD16105B0805e18DdAb6bF7792c4704568827;
    address constant ASWBTC = 0x4Ee17d24fBd633c128Fb5068d450e16D0Ff45108;
    address constant ASASUSD = 0x2a81FD13C0e101FCb96cB6fD996258e2b20d91d1;
    address constant ASMUSD = 0xb38064EF885551ef996c885Eb8Ea80Da5cC1c9f2;

    address constant VDUSDC = 0x026152F78c6b716DA19C2BFfF474d0F9e2D2fBE9;
    address constant VDWETH = 0x2694FcCadf98621e5dA7a8946a545BBce2d51693;
    address constant VDWBTC = 0xF4167Af603fBA02623950223383b41061731EcEF;
    address constant VDUSDT = 0x1Cc0D772B187693Ebf20107E44aC7F1029578e1F;
    address constant VDASUSD = 0xa04C8b74C9B1319DB240157cFe14504844debDf2;
    address constant VDMUSD = 0x20d2312769D6d9eAADBb57a3eEA44592440cd6C9;

    address constant wasWBTC = 0x7dfd2F6d984CA9A2d2ffAb7350E6948E4315047b;
    address constant wasWETH = 0x9A4cA144F38963007cFAC645d77049a1Dd4b209A;
    address constant wasUSDC = 0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944;
    address constant wasUSDT = 0x1579072d23FB3f545016Ac67E072D37e1281624C;

    mapping(address => uint256) public collateralAssetSum;
    mapping(address => uint256) public debtAssetSum;

    mapping(address => uint256[]) miniPoolToBalances;
    Liquidator liquidator;

    function setUp() public {
        // LINEA setup
        string memory lineaRpc = vm.envString("LINEA_RPC_URL");
        uint256 lineaFork = vm.createSelectFork(lineaRpc);
        assertEq(vm.activeFork(), lineaFork);
        liquidator = new Liquidator();
    }

    function testBalancesBeforeAndAfterHack() public {
        string memory lineaRpc = vm.envString("LINEA_RPC_URL");
        uint256 lineaFork = vm.createSelectFork(lineaRpc, 24320158);
        assertEq(vm.activeFork(), lineaFork);

        uint256 initialAsUsdcBalance = IERC20Detailed(USDC).balanceOf(ASUSDC);
        uint256 initialAsWethBalance = IERC20Detailed(WETH).balanceOf(ASWETH);
        uint256 initialAsWbtcBalance = IERC20Detailed(WBTC).balanceOf(ASWBTC);
        uint256 initialAsUsdtBalance = IERC20Detailed(USDT).balanceOf(ASUSDT);
        uint256 initialAsAsUsdBalance = IERC20Detailed(ASUSD).balanceOf(ASASUSD);
        uint256 initialAsmUsdBalance = IERC20Detailed(MUSD).balanceOf(ASMUSD);

        console2.log("--------------------BEFORE-------------------------");

        console2.log("initialAsWbtcBalance: ", initialAsWbtcBalance);
        console2.log("initialAsWethBalance: ", initialAsWethBalance);
        console2.log("initialAsUsdcBalance: ", initialAsUsdcBalance);
        console2.log("initialAsUsdtBalance: ", initialAsUsdtBalance);
        console2.log("initialAsAsUsdBalance: ", initialAsAsUsdBalance);
        console2.log("initialAsmUsdBalance: ", initialAsmUsdBalance);

        for (uint256 i = 0; i < 4; i++) {
            address erc6909 =
                (IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).getMiniPoolToAERC6909(i));
            IMiniPool miniPool =
                IMiniPool(IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).getMiniPool(i));
            (address[] memory reserves,) = miniPool.getReservesList();
            miniPoolToBalances[erc6909] = new uint256[](reserves.length);
            for (uint256 idx = 0; idx < reserves.length; idx++) {
                miniPoolToBalances[erc6909][idx] = IERC20Detailed(reserves[idx]).balanceOf(erc6909);
                console2.log(
                    "Initial balance for %s in MiniPool %s: %s",
                    IERC20Detailed(reserves[idx]).symbol(),
                    i,
                    IERC20Detailed(reserves[idx]).balanceOf(erc6909)
                );
            }
        }

        console2.log("--------------------AFTER-------------------------");
        lineaFork = vm.createSelectFork(lineaRpc, 24322904);

        assertEq(vm.activeFork(), lineaFork);
        console2.log("finalAsWbtcBalance: ", IERC20Detailed(WBTC).balanceOf(ASWBTC));
        console2.log("finalAsWethBalance: ", IERC20Detailed(WETH).balanceOf(ASWETH));
        console2.log("finalAsUsdcBalance: ", IERC20Detailed(USDC).balanceOf(ASUSDC));
        console2.log("finalAsUsdtBalance: ", IERC20Detailed(USDT).balanceOf(ASUSDT));
        console2.log("finalAsAsUsdBalance: ", IERC20Detailed(ASUSD).balanceOf(ASASUSD));
        console2.log("finalAsmUsdBalance: ", IERC20Detailed(MUSD).balanceOf(ASMUSD));

        console2.log(
            "Diff finalAsWbtcBalance: ",
            int256(initialAsWbtcBalance) - int256(IERC20Detailed(WBTC).balanceOf(ASWBTC))
        );
        console2.log(
            "Diff finalAsWethBalance: ",
            int256(initialAsWethBalance) - int256(IERC20Detailed(WETH).balanceOf(ASWETH))
        );
        console2.log(
            "Diff finalAsUsdcBalance: ",
            int256(initialAsUsdcBalance) - int256(IERC20Detailed(USDC).balanceOf(ASUSDC))
        );
        console2.log(
            "Diff finalAsUsdtBalance: ",
            int256(initialAsUsdtBalance) - int256(IERC20Detailed(USDT).balanceOf(ASUSDT))
        );
        console2.log(
            "Diff finalAsAsUsdBalance: ",
            int256(initialAsAsUsdBalance) - int256(IERC20Detailed(ASUSD).balanceOf(ASASUSD))
        );
        console2.log(
            "Diff finalAsmUsdBalance: ",
            int256(initialAsmUsdBalance) - int256(IERC20Detailed(MUSD).balanceOf(ASMUSD))
        );

        for (uint256 i = 0; i < 4; i++) {
            address erc6909 =
                (IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).getMiniPoolToAERC6909(i));
            IMiniPool miniPool =
                IMiniPool(IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).getMiniPool(i));
            (address[] memory reserves,) = miniPool.getReservesList();
            for (uint256 idx = 0; idx < reserves.length; idx++) {
                console2.log(
                    "Final balance for %s in MiniPool %s: %s",
                    IERC20Detailed(reserves[idx]).symbol(),
                    i,
                    IERC20Detailed(reserves[idx]).balanceOf(erc6909)
                );
                // console2.log(
                //     "Diff balance for %s in MiniPool %s: ",
                //     IERC20Detailed(reserves[idx]).symbol(),
                //     i
                // );
                // console2.log(
                //     int256(miniPoolToBalances[erc6909][idx])
                //         - int256(IERC20Detailed(reserves[idx]).balanceOf(erc6909))
                // );
            }
        }
    }

    function testMiniPoolParamsBeforeAttack() public {
        address token = 0xacA92E438df0B2401fF60dA7E4337B687a2435DA;
        address miniPool = 0x0baFB30B72925e6d53F4d0A089bE1CeFbB5e3401;
        string memory lineaRpc = vm.envString("LINEA_RPC_URL");
        uint256 lineaFork = vm.createSelectFork(lineaRpc, 24096677); //24096677, 24320598
        assertEq(vm.activeFork(), lineaFork);
        console2.log("---------------------------- BEFORE: --------------------------------------");
        AggregatedMiniPoolReservesData memory data =
            AsteraDataProvider2(DATA_PROVIDER).getReserveDataForAssetAtMiniPool(token, miniPool);
        logAggregatedMiniPoolReservesData(data);
        lineaFork = vm.createSelectFork(lineaRpc);
        assertEq(vm.activeFork(), lineaFork);
        console2.log("------------------ AFTER: -------------------------");
        data = AsteraDataProvider2(DATA_PROVIDER).getReserveDataForAssetAtMiniPool(token, miniPool);
        logAggregatedMiniPoolReservesData(data);
    }

    function testRepayLeftovers() public {
        vm.startPrank(IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).getMainPoolAdmin());
        // IMiniPoolConfigurator(MINI_POOL_CONFIGURATOR).setMinDebtThreshold(
        //     0, IMiniPool(0xE7a2c97601076065C3178BDbb22C61933f850B03)
        // );
        // IMiniPoolConfigurator(MINI_POOL_CONFIGURATOR).setMinDebtThreshold(
        //     0, IMiniPool(0x0baFB30B72925e6d53F4d0A089bE1CeFbB5e3401)
        // );
        // IMiniPoolConfigurator(MINI_POOL_CONFIGURATOR).setMinDebtThreshold(
        //     0, IMiniPool(0x65559abECD1227Cc1779F500453Da1f9fcADd928)
        // );
        // IMiniPoolConfigurator(MINI_POOL_CONFIGURATOR).setMinDebtThreshold(
        //     0, IMiniPool(0x52280eA8979d52033E14df086F4dF555a258bEb4)
        // );
        vm.stopPrank();

        deal(WBTC, 0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f, 1 ether);
        deal(MUSD, 0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f, 1 ether);

        vm.startPrank(0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f);
        // IERC20Detailed(WBTC).approve(
        //     0xE7a2c97601076065C3178BDbb22C61933f850B03,
        //     IERC20Detailed(WBTC).balanceOf(0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f)
        // );
        // console2.log(
        //     "Repaying debt: ",
        //     IAERC6909(0x24d61C71855d62d8C7630e5E91E1EF8482E32aE0).balanceOf(
        //         0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f, 2000
        //     )
        // );
        // IMiniPool(0xE7a2c97601076065C3178BDbb22C61933f850B03).repay(
        //     wasWBTC,
        //     true,
        //     IAERC6909(0x24d61C71855d62d8C7630e5E91E1EF8482E32aE0).balanceOf(
        //         0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f, 2000
        //     ),
        //     0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f
        // );

        // IERC20Detailed(WBTC).approve(
        //     0x0baFB30B72925e6d53F4d0A089bE1CeFbB5e3401,
        //     IERC20Detailed(WBTC).balanceOf(0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f)
        // );
        // console2.log(
        //     "Repaying debt: ",
        //     IAERC6909(0x5Fb9EBDD9bcBa3FB615CD07981aa5F4650BbD90D).balanceOf(
        //         0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f, 2000
        //     )
        // );
        // IMiniPool(0x0baFB30B72925e6d53F4d0A089bE1CeFbB5e3401).repay(
        //     wasWBTC,
        //     true,
        //     IAERC6909(0x5Fb9EBDD9bcBa3FB615CD07981aa5F4650BbD90D).balanceOf(
        //         0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f, 2000
        //     ),
        //     0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f
        // );

        IERC20Detailed(MUSD)
            .approve(
                0x52280eA8979d52033E14df086F4dF555a258bEb4,
                IERC20Detailed(MUSD).balanceOf(0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f)
            );
        console2.log(
            "Repaying debt: ",
            IAERC6909(0xc596AeF495cC08ac642A616919A8ee6213f533bb)
                .balanceOf(0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f, 2129)
        );
        IMiniPool(0x52280eA8979d52033E14df086F4dF555a258bEb4)
            .repay(
                MUSD,
                true,
                IAERC6909(0xc596AeF495cC08ac642A616919A8ee6213f533bb)
                    .balanceOf(0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f, 2129),
                0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f
            );
        vm.stopPrank();
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
