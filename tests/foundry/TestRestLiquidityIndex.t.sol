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

contract TestResetLiquidityIndexTest is Test {
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

    uint128 constant NEW_LQUIDITY_INDEX = 1001883043396551183923396494; //24320598

    mapping(address => uint256[]) miniPoolToBalances;

    function setUp() public {
        // LINEA setup
        string memory lineaRpc = vm.envString("LINEA_RPC_URL");
        uint256 lineaFork = vm.createSelectFork(lineaRpc);
        assertEq(vm.activeFork(), lineaFork);
    }

    function testResetLiquidiyIndex() public {
        LendingPoolV2 newLendingPool = LendingPoolV2(0x94494e217bd6bd5f618CfB528a922Df47Fa8f469);
        LendingPoolV3 newLendingPoolV3 = LendingPoolV3(0xDf7c0D19dB5790D41cdb2aD4E95ABC9AD0C93Fe3);

        // Upgrade pool impl
        vm.startPrank(ADMIN);
        ILendingPoolAddressesProvider(LENDING_POOL_ADDRESSES_PROVIDER).setLendingPoolImpl(
            address(newLendingPool)
        );
        vm.stopPrank();

        uint256 initialUsdtAdminBalance = IERC20Detailed(USDT).balanceOf(ADMIN);
        uint256 asTokenUsdtBalance = IERC20Detailed(USDT).balanceOf(ASUSDT);

        // Initial admin as-USDT balance
        console2.log("Initial admin as-USDT balance: ", asTokenUsdtBalance);
        // Initial USDT balance
        console2.log("Initial admin USDT balance: ", initialUsdtAdminBalance);
        // Initial total supply
        console2.log("Initial total supply: ", IAToken(ASUSDT).totalSupply());
        // Initial asToken balance
        console2.log("Initial asToken USDT balance: ", asTokenUsdtBalance);
        // Initial variable debt toota supply
        console2.log(
            "Initial variable debt total supply: ", IVariableDebtToken(VDUSDT).totalSupply()
        );
        // Initial liquidity index
        console2.log("Initial liquidity index: ", IAToken(ASUSDT).convertToAssets(1e27));

        // Update index
        vm.startPrank(ADMIN);
        LendingPoolV2(LENDING_POOL_PROXY).setIndexUsdt(NEW_LQUIDITY_INDEX);

        // Mint as-USDT
        LendingPoolV2(LENDING_POOL_PROXY).mintDonatedAmountToTreasury(USDT, true);

        ILendingPoolAddressesProvider(LENDING_POOL_ADDRESSES_PROVIDER).setLendingPoolImpl(
            address(newLendingPoolV3)
        );
        vm.stopPrank();

        console2.log(
            "Lending pool revision:", LendingPoolV3(LENDING_POOL_PROXY).LENDINGPOOL_REVISION()
        );

        // Unpause pool
        vm.startPrank(EMERGENCY);
        ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setPoolPause(false);
        vm.stopPrank();

        vm.prank(ADMIN);
        // Withdraw USDT
        LendingPoolV3(LENDING_POOL_PROXY).withdraw(USDT, true, type(uint256).max, ADMIN);

        // Final admin as-USDT balance
        console2.log("Final admin as-USDT balance: ", IAToken(ASUSDT).balanceOf(ADMIN));
        // Final USDT balance
        console2.log("Final admin USDT balance: ", IERC20Detailed(USDT).balanceOf(ADMIN));
        // Final total supply
        console2.log("Final total supply: ", IAToken(ASUSDT).totalSupply());
        // Final asToken balance
        console2.log("Final asToken USDT balance: ", IERC20Detailed(USDT).balanceOf(ASUSDT));
        // Final variable debt toota supply
        console2.log("Final variable debt total supply: ", IVariableDebtToken(VDUSDT).totalSupply());
        // Final liquidity index
        console2.log("Final liquidity index: ", IAToken(ASUSDT).convertToAssets(1e27));

        assertEq(IAToken(ASUSDT).convertToAssets(1e27), NEW_LQUIDITY_INDEX);
        assertEq(
            IAToken(ASUSDT).totalSupply(),
            IERC20Detailed(USDT).balanceOf(ASUSDT) + IVariableDebtToken(VDUSDT).totalSupply()
        );
        assertEq(
            IERC20Detailed(USDT).balanceOf(ADMIN),
            initialUsdtAdminBalance
                + (
                    asTokenUsdtBalance + IVariableDebtToken(VDUSDT).totalSupply()
                        - IAToken(ASUSDT).totalSupply()
                )
        );

        uint256 totalSupplyOfUsdt = IAToken(ASUSDT).totalSupply();

        // vm.startPrank(EMERGENCY);
        // IMiniPoolConfigurator(0x41296B58279a81E20aF1c05D32b4f132b72b1B01).setPoolPause(
        //     false, IMiniPool(0x52280eA8979d52033E14df086F4dF555a258bEb4)
        // );
        // vm.stopPrank();

        // console2.log(
        //     "Pool paused: ", IMiniPool(0x52280eA8979d52033E14df086F4dF555a258bEb4).paused()
        // );
        // console2.log(
        //     "Pool paused: ", IMiniPool(0x65559abECD1227Cc1779F500453Da1f9fcADd928).paused()
        // );
        // console2.log(
        //     "Pool paused: ", IMiniPool(0x0baFB30B72925e6d53F4d0A089bE1CeFbB5e3401).paused()
        // );

        // console2.log("Core Pool paused: ", ILendingPool(LENDING_POOL_PROXY).paused());

        // vm.startPrank(ADMIN);
        // IERC20Detailed(0xa500000000e482752f032eA387390b6025a2377b).approve(
        //     0x52280eA8979d52033E14df086F4dF555a258bEb4, 1e18
        // );
        // IMiniPool(0x52280eA8979d52033E14df086F4dF555a258bEb4).liquidationCall(
        //     0x9A4cA144F38963007cFAC645d77049a1Dd4b209A,
        //     true,
        //     0xa500000000e482752f032eA387390b6025a2377b,
        //     false,
        //     0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4,
        //     1e18,
        //     false
        // );
        // vm.stopPrank();

        deal(USDT, 0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f, 1e10);

        vm.startPrank(0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f);
        IERC20Detailed(USDT).approve(LENDING_POOL_PROXY, 1e10);
        LendingPoolV3(LENDING_POOL_PROXY).repay(
            USDT, true, type(uint256).max, 0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f
        );
        LendingPoolV3(LENDING_POOL_PROXY).repay(
            USDT,
            true,
            IVariableDebtToken(VDUSDT).balanceOf(0xbeb15caee71001d82F430E4deda80e16dDf438Db),
            0xbeb15caee71001d82F430E4deda80e16dDf438Db
        );
        LendingPoolV3(LENDING_POOL_PROXY).withdraw(USDT, true, type(uint256).max, address(this));
        vm.stopPrank();
        vm.prank(0x5Fb9EBDD9bcBa3FB615CD07981aa5F4650BbD90D);
        LendingPoolV3(LENDING_POOL_PROXY).withdraw(USDT, true, type(uint256).max, address(this));
        vm.prank(0xbeb15caee71001d82F430E4deda80e16dDf438Db);
        LendingPoolV3(LENDING_POOL_PROXY).withdraw(USDT, true, type(uint256).max, address(this));
        vm.prank(0x24d61C71855d62d8C7630e5E91E1EF8482E32aE0);
        LendingPoolV3(LENDING_POOL_PROXY).withdraw(USDT, true, type(uint256).max, address(this));
        vm.startPrank(0x1ac686c047283D7EF65345475A2633b6904ECa4d);
        deal(WBTC, 0x1ac686c047283D7EF65345475A2633b6904ECa4d, 1e9);
        IERC20Detailed(WBTC).approve(LENDING_POOL_PROXY, 1e9);
        LendingPoolV3(LENDING_POOL_PROXY).repay(
            WBTC, true, type(uint256).max, 0x1ac686c047283D7EF65345475A2633b6904ECa4d
        );
        LendingPoolV3(LENDING_POOL_PROXY).withdraw(USDT, true, type(uint256).max, address(this));
        vm.stopPrank();
        vm.prank(0xc596AeF495cC08ac642A616919A8ee6213f533bb);
        LendingPoolV3(LENDING_POOL_PROXY).withdraw(USDT, true, type(uint256).max, address(this));
        vm.prank(0x1C1002aB527289dDda9a41bd49140B978d3B6303);
        LendingPoolV3(LENDING_POOL_PROXY).withdraw(USDT, true, type(uint256).max, address(this));

        assertEq(IERC20Detailed(USDT).balanceOf(address(this)), totalSupplyOfUsdt);
        assertEq(IAToken(ASUSDT).totalSupply(), 0);
    }

    function testMintToOthers() public {
        LendingPoolV2 newLendingPool = new LendingPoolV2();

        // Upgrade pool impl
        vm.startPrank(ADMIN);
        ILendingPoolAddressesProvider(LENDING_POOL_ADDRESSES_PROVIDER).setLendingPoolImpl(
            address(newLendingPool)
        );
        vm.stopPrank();

        // Unpause pool
        vm.startPrank(EMERGENCY);
        ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setPoolPause(false);
        vm.stopPrank();

        uint256 initialAsUsdcBalance = IERC20Detailed(ASUSDC).balanceOf(ADMIN);
        uint256 initialAsWethBalance = IERC20Detailed(ASWETH).balanceOf(ADMIN);
        uint256 initialAsWbtcBalance = IERC20Detailed(ASWBTC).balanceOf(ADMIN);
        uint256 initialAsUsdtBalance = IERC20Detailed(ASUSDT).balanceOf(ADMIN);
        uint256 initialAsAsUsdBalance = IERC20Detailed(ASASUSD).balanceOf(ADMIN);
        uint256 initialAsmUsdBalance = IERC20Detailed(ASMUSD).balanceOf(ADMIN);

        // Initial admin as-USDC and as-WETH balance
        console2.log("Initial admin as-USDC balance: ", initialAsUsdcBalance);
        console2.log("Initial admin as-WETH balance: ", initialAsWethBalance);
        console2.log("Initial admin as-WBTC balance: ", initialAsWbtcBalance);
        console2.log("Initial admin as-USDT balance: ", initialAsUsdtBalance);
        console2.log("Initial admin as-asUSD balance: ", initialAsAsUsdBalance);
        console2.log("Initial admin as-mUSD balance: ", initialAsmUsdBalance);

        console2.log("Total supply:", IAToken(ASUSDC).totalSupply());
        console2.log(
            "Balance + Debts:",
            IERC20Detailed(USDC).balanceOf(ASUSDC) + IVariableDebtToken(VDUSDC).totalSupply()
        );

        assertLe(
            IAToken(ASUSDC).totalSupply(),
            IERC20Detailed(USDC).balanceOf(ASUSDC) + IVariableDebtToken(VDUSDC).totalSupply(),
            "Total supply less for  USDC"
        );
        assertLe(
            IAToken(ASWETH).totalSupply(),
            IERC20Detailed(WETH).balanceOf(ASWETH) + IVariableDebtToken(VDWETH).totalSupply(),
            "Total supply less for  WETH"
        );
        assertLe(
            IAToken(ASWBTC).totalSupply(),
            IERC20Detailed(WBTC).balanceOf(ASWBTC) + IVariableDebtToken(VDWBTC).totalSupply(),
            "Total supply less for  WBTC"
        );
        assertLe(
            IAToken(ASASUSD).totalSupply(),
            IERC20Detailed(ASUSD).balanceOf(ASASUSD) + IVariableDebtToken(VDASUSD).totalSupply(),
            "Total supply less for  ASUSD"
        );
        assertLe(
            IAToken(ASMUSD).totalSupply(),
            IERC20Detailed(MUSD).balanceOf(ASMUSD) + IVariableDebtToken(VDMUSD).totalSupply(),
            "Total supply less for  ASMUSD"
        );
        assertLe(
            IAToken(ASUSDT).totalSupply(),
            IERC20Detailed(USDT).balanceOf(ASUSDT) + IVariableDebtToken(VDUSDT).totalSupply(),
            "Total supply less for  USDT"
        );

        // Update index
        vm.startPrank(ADMIN);
        // Mint as-USDT
        LendingPoolV2(LENDING_POOL_PROXY).mintDonatedAmountToTreasury(USDC, true);
        LendingPoolV2(LENDING_POOL_PROXY).mintDonatedAmountToTreasury(WETH, true);
        LendingPoolV2(LENDING_POOL_PROXY).mintDonatedAmountToTreasury(WBTC, true);
        LendingPoolV2(LENDING_POOL_PROXY).mintDonatedAmountToTreasury(USDT, true);
        LendingPoolV2(LENDING_POOL_PROXY).mintDonatedAmountToTreasury(ASUSD, false);
        LendingPoolV2(LENDING_POOL_PROXY).mintDonatedAmountToTreasury(MUSD, true);

        vm.stopPrank();

        // Final admin as-USDC balance
        console2.log("Final admin as-USDC balance: ", IAToken(ASUSDC).balanceOf(ADMIN));
        console2.log("Final admin as-WETH  balance: ", IAToken(ASWETH).balanceOf(ADMIN));
        console2.log("Final admin as-WBTC balance: ", IAToken(ASWBTC).balanceOf(ADMIN));
        console2.log("Final admin as-USDT  balance: ", IAToken(ASUSDT).balanceOf(ADMIN));
        console2.log("Final admin as-asUSD balance: ", IAToken(ASASUSD).balanceOf(ADMIN));
        console2.log("Final admin as-mUSD  balance: ", IAToken(ASMUSD).balanceOf(ADMIN));

        assertEq(
            IAToken(ASUSDC).totalSupply(),
            IERC20Detailed(USDC).balanceOf(ASUSDC) + IVariableDebtToken(VDUSDC).totalSupply(),
            "Wrong numbers for USDC"
        );
        assertEq(
            IAToken(ASWETH).totalSupply(),
            IERC20Detailed(WETH).balanceOf(ASWETH) + IVariableDebtToken(VDWETH).totalSupply(),
            "Wrong numbers for WETH"
        );
        assertEq(
            IAToken(ASWBTC).totalSupply(),
            IERC20Detailed(WBTC).balanceOf(ASWBTC) + IVariableDebtToken(VDWBTC).totalSupply(),
            "Wrong numbers for WBTC"
        );

        assertEq(
            IAToken(ASASUSD).totalSupply(),
            IERC20Detailed(ASUSD).balanceOf(ASASUSD) + IVariableDebtToken(VDASUSD).totalSupply(),
            "Wrong numbers for ASUSD"
        );
        assertEq(
            IAToken(ASMUSD).totalSupply(),
            IERC20Detailed(MUSD).balanceOf(ASMUSD) + IVariableDebtToken(VDMUSD).totalSupply(),
            "Wrong numbers for ASMUSD"
        );
        // assertEq(
        //     IAToken(ASUSDT).totalSupply(),
        //     IERC20Detailed(USDT).balanceOf(ASUSDT) + IVariableDebtToken(VDUSDT).totalSupply(),
        //     "Wrong numbers for USDT"
        // );
    }

    function testBalancesBeforeAndAfterHack() public {
        string memory lineaRpc = vm.envString("LINEA_RPC_URL");
        uint256 lineaFork = vm.createSelectFork(lineaRpc, 24220150);
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
}
