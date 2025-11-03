// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AsteraDataProvider2, UserReserveData} from "contracts/misc/AsteraDataProvider2.sol";
import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IERC20Detailed} from "contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
// import {MiniPoolV2} from "contracts/protocol/core/minipool/MiniPoolV2.sol";
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

contract TestBeforeAndAfterAttack is Test {
    address constant DATA_PROVIDER = 0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e;

    address constant LENDING_POOL_CONFIGURATOR = 0x5af0d031A3dA7c2D3b1fA9F00683004F176c28d0;
    address constant ADMIN = 0x7D66a2e916d79c0988D41F1E50a1429074ec53a4;
    address constant EMERGENCY = 0xDa77d6C0281fCb3e41BD966aC393502a1C524224;

    address constant LENDING_POOL_ADDRESSES_PROVIDER = 0x9a460e7BD6D5aFCEafbE795e05C48455738fB119;
    address constant LENDING_POOL_PROXY = 0x17d8a5305A37fe93E13a28f09c46db5bE24E1B9E;

    address constant MINI_POOL_ADDRESS_PROVIDER = 0x9399aF805e673295610B17615C65b9d0cE1Ed306;

    address constant USDC = 0x176211869cA2b568f2A7D4EE941E073a821EE1ff;
    address constant WETH = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;
    address constant USDT = 0xA219439258ca9da29E9Cc4cE5596924745e12B93;
    address constant WBTC = 0x3aAB2285ddcDdaD8edf438C1bAB47e1a9D05a9b4;
    address constant ASUSD = 0xa500000000e482752f032eA387390b6025a2377b;
    address constant MUSD = 0xacA92E438df0B2401fF60dA7E4337B687a2435DA;
    address constant LINEA = 0x1789e0043623282D5DCc7F213d703C6D8BAfBB04;
    address constant REX33 = 0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4;

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

    mapping(address => uint256[]) miniPoolToBalances;

    function setUp() public {
        // LINEA setup
        string memory lineaRpc = vm.envString("LINEA_RPC_URL");
        uint256 lineaFork = vm.createSelectFork(lineaRpc);
        assertEq(vm.activeFork(), lineaFork);
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
