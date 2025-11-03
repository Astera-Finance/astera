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
import {Liquidator} from "contracts/misc/Liquidator.sol";

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

    mapping(address => uint256) public assetSum;

    address[] public lineaUsers = [
        0x04B062a9047A22C1413c9b7f206cfb402372A40B,
        0x04E1aeC5FA92D2c8Fc5F4F584BC9e9471f45Ec93,
        0x08Ec41FDcb5F9cD49a2a9d76bBEEf952A5d5739d,
        0x0A24d129a4CcF1f9874Dbea795a96d8d705e46DC,
        0x0C3f8DE0761D67FC8F3343279AD1B4dFc4Ee10DE,
        0x112513AEC425C87e0f94f28d2A5aa4Cb6d88A6a4,
        0x1ac686c047283D7EF65345475A2633b6904ECa4d,
        0x1C1795bffeDa25De01A7C21c88b49D9592B0598D,
        0x1D7f204Ca9Fcc11733fe6F465EfaCA071c05D50a,
        0x25464e5765fFa8A2bfFB25B6347EaF3FF8F555dB,
        0x2C21DC4fe422fBAdd7DC1edA8AC4D10a8D9fFa2e,
        0x2E4C9C2BB198A76Cb3d5a39991aF2B71716ff94a,
        0x381081364ce6F2D66D5a59E4AC5FC16C171f8503,
        0x3aF849172D1e12c3D91e70197568B929c42FC1d7,
        0x420D8DB9647262bb3312BE9eEe510D44E9689c3F,
        0x429a65e517088Db3e0fe60a629Def3F603d006A7,
        0x435b7D470767Cb121F37dD296B2AC7913fDF5427,
        0x43B2D03C55418c7CAf4Bd137B115f0eeB15B6D4c,
        0x4596E8fA7DFb9740B4a69a33a28bc5c65f8Dcb00,
        0x4697F17dc804f5916f3a41C6D522b489468E2B87,
        0x49D8d8a61A7807a8cC78b42A34FA223014518863,
        0x4d1de98D67b3dfae5B6919dA25B0EA7fE9Ff1006,
        0x4FfD0A59a26cB2Aa76D403215e4cC2845C053994,
        0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec,
        0x529407C4e9584701253D93DDa4686a630Ada00e5,
        0x52b4af394C7DC271C9716084A46203ad8431e1B9,
        0x54d765404f9D4FF2bD6334a395Ef4CC042912c87,
        0x595d12D50662D134dE871063F1a52aB6Ef227f43,
        0x607E73C236983D56Bdfc52753016932Bf0eAd90E,
        0x63dbCfF5D4F831E8a48E249A72773f32b97eb99E,
        0x689E994D0e4FcD7F5771DE774Bc83e4126e468F4,
        0x68f861D975594e3a36281bfb5E5e6A9BE67C3359,
        0x758dDab0f1D345b6d01333fD72946CA23bE3214C,
        0x75D7c741Bb242632593a42B141Cf7B8A3c84ECC2,
        0x7890fF0d468b169AcC30081e229dB4BEa65621dd,
        0x7D66a2e916d79c0988D41F1E50a1429074ec53a4,
        0x7F54285a9c022fC5F528045cbD63Bf9a7c51aFD8,
        0x843C5A361F3Fb9aA52c88529633FD9DBaE69c91d,
        0x89A1fDb575933ac14B5cbF3E612e7F87b5872DBf,
        0x923208A2A79D2EE5A0f65EA2BE7E1d0a05bEa55d,
        0x94F3bBb4533dfAe938E98F614bD574D6213dEb29,
        0xa12f0E781972Eda58c99beD6581f22a37D57E316,
        0xA2c21c71a86Aa9ed0252cEC5e0b2070CC119E8ec,
        0xA7B729c880512A177c4B92Ab632E70988fb47462,
        0xA839B3Fa0635aA63f2EAaafBE09F3caCf914fA42,
        0xb564AD33EDb3BD1b789C117E9c22624c0EfF1271,
        0xb79185Aa49426D57fF9e9F96c276E559549AA732,
        0xb9a50279173e65E7735d9e351bC32361a1236166,
        0xbcb23CAeDAAAE24AeFe4549e7058e25f3f714d9f,
        0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4,
        0xD2f8e30b6Ef8FaD692C3C1A11258c1bDc65Ae2EC,
        0xD92a7F3E6e8F7731f3DC6BE3FB39E745Ec1C6482,
        0xD9e4C45C4471F63420E434756C5026286D28fbdb,
        0xE229d80fdda6008ABb6aCc880556032c757F966d,
        0xE3666187c7Fbd30ea514a00747f27BeF2Df27d69,
        0xE89e8fe8936eb33e34E7A8277DD53788ADE79650,
        0xEdeA7aAF2036686b01a5c1D1Fd09a86042BB4189,
        0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f,
        0xf2Bc825FB466136d00571B496E6EB1a601679919,
        0xFa0a1973413C626439C36110f960c38620d5FC18
    ];

    address[] public rex33Users = [
        0x001A794b0973AA5384ae9B7140A767782c038af8,
        0x031F72dEB03C509af42624ddcD1f63fce5eCb220,
        0x098fFf7E82dAd4488f94d7Dbe1415dd913066355,
        0x0A83985E4A6E8Dae2B67beD4f2d9268f6806Ce00,
        0x0CeCc8F202CDd0bA7efA81F5f9518927D31B36d1,
        0x1014A66402Ff5b51d86a527da1dbe96343Bd9D95,
        0x126FF8faBeC84EF8a96F25dD0C2668fB9b7E7088,
        0x19Fa956048DF9A0024d4E65dAB6422f99eDb125F,
        0x1B5db5c065d7507DBF65032a1835e4a7B633E67b,
        0x1C1795bffeDa25De01A7C21c88b49D9592B0598D,
        0x1e7e4b0dDbf3406b9D3362D2901dc20D63814d84,
        0x1eC8F94b0ef0Dc6a9Ff923dfdf2523f4456CdFfD,
        0x2E11092aFafce07F68A2579b76139233b1ba6Caf,
        0x329CfE850FF4CF637aa2353ef2D3672156E54d6C,
        0x35fE83086417ac7EA4e9E80D1D3369C455c17005,
        0x3C4524481a34551fc5Aa239250F07A986Ed2c2E1,
        0x3Da8cADa0F3801D13eb0748ab4f5f6eE0F450690,
        0x43B2D03C55418c7CAf4Bd137B115f0eeB15B6D4c,
        0x472Bf5Ff7b96033BD203b360403A0649A908DBE4,
        0x477dE3668C728adb0045f0BBe06eE9d0230c1564,
        0x4A219402d71BF58114F1b699654aCF388E2dA672,
        0x4C92Ab257222BCd47E299aDdF268D696Bb3B00d7,
        0x4dAf8ce9D729ca4F121381ec4B22123627C1C004,
        0x505BDde1984E5b76F6455D533D0D116Af4d061bc,
        0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec,
        0x553A7130D1b84651327865e0c623e21B9E97D447,
        0x57F6F77da955C8FA89f3CF7973a1fB8054B56204,
        0x5CB97ec856d779cF7b130408D18CC802824ccf5F,
        0x607E73C236983D56Bdfc52753016932Bf0eAd90E,
        0x61e91944Afbd67C79429935BEDBB762eBB04caD7,
        0x6270df891fC56b3f4D75361185A31194b29AFD5D,
        0x655301eB3992fA35fF6fec91567240310a9756A6,
        0x6649449f075A8F6Aa56Efe43ab5c45B8ca0dFe2C,
        0x68f861D975594e3a36281bfb5E5e6A9BE67C3359,
        0x72727d612CD162c30f84B579662a9bDe34481aE7,
        0x789498eE77215b80d201A814228fA7f248c3be18,
        0x7BFEe91193d9Df2Ac0bFe90191D40F23c773C060,
        0x7D66a2e916d79c0988D41F1E50a1429074ec53a4,
        0x8011d0c9DB37CBCF7cA781918B4AD0cB50A177D4,
        0x82B97FE157c390fD334C1AaeBC767113CaFA2154,
        0x82F9C16D5ADA0C406aA432b4B79A15F6F7725Ae5,
        0x8a81DAFbFA575C9992eb649bA3F370197F7De9b9,
        0x908Fd947485FA2501273c81CB4b639eE17045468,
        0x997eEb18CFCE93dDec94062d13d565b966aC8249,
        0x9e3aE00085e9f5c302bEfEC347d6a0560DE72C6E,
        0xa7AB43295A9bddE0d185049c45ED5FfA1758c190,
        0xA7B729c880512A177c4B92Ab632E70988fb47462,
        0xA84fE466486223FA9BbA2dD3ecFb5C1100311711,
        0xAC1c487f78564dfFB2c94D6f28EdF04E18843004,
        0xAe0CFc332dAF84453452f4049700CFe708fe4624,
        0xaF0114811527B29E07B374EcA3114dBE20992c79,
        0xb11903Ec9E1036F1a3FaFe5815E84D8c1f62e254,
        0xb794A8aa430907390B13C24932fe5C982B894DAA,
        0xbeb15caee71001d82F430E4deda80e16dDf438Db,
        0xBeC88d61cd94Da3Ee08F844c536140C1D10095c5,
        0xC050cc9dB67E9ACf087a95bD3fcAB510F055f9E3,
        0xC2Fa91EFdE9fd71b3AC5912f7c7A48D4680847ec,
        0xc7F354b172e53c0dfFA8Db17b028F634CD2EFCBF,
        0xc8B19839ae371bd541F20B15c3A3CB82BFB6A6C6,
        0xC8CaEc7aE8B36676c5C60D11423C6dAC8343EB19,
        0xc9C384a9E7e28f7Ef55903eb90947fe3ce71D475,
        0xC9EEF46E1AB9C4eEdC7B7cBd36Dc37C1A0EB1f75,
        0xcaFa3E48Ad50120358072Befe591e00c7118d1B9,
        0xCb15DcfdEe8a7a2BeC8561d33625B4FF7968baB4,
        0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4,
        0xd52929B69680A6f74D2eB9c8F1ef482f37b1b32B,
        0xdB1db4C8fCf4dAd76F66e3061B984308e5F22789,
        0xDD0c16db6ED4f670BB4dC7235ab6b7C100773b88,
        0xDD0CDF8D98d9Ad3ADfaa49AaECD444Bfa01d9C9a,
        0xDEAdF06F9Cd85CBc94Ffd9af05db9C24e32B7820,
        0xdEe517bFc5DB0122e56FfDD605286F87b81b83dE,
        0xe0A86AFB73c0922A50D4A985A25507EcDA8a9B51,
        0xE3bB042f9Cc751AFAF7C14FC0b2848FAE17CB08a,
        0xE87FEd3a150FBcD6d77a3313ffDf6fE268baF289,
        0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f,
        0xf2Bc825FB466136d00571B496E6EB1a601679919,
        0xF2Cf9d7513A2F6EAAe9d82b95B3c40D0efebE33B,
        0xfae5Ba0a469179C88366EC33202e7bF24C649b01,
        0xFb9Cbb2FEDEc281B80AeF79Cc1f39d547EFB956e
    ];

    address[] private lstUsers = [
        0x14b35EA598a18e171a8f1e724c356F83fB4A0F18,
        0x1ac686c047283D7EF65345475A2633b6904ECa4d,
        0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec,
        0x7D66a2e916d79c0988D41F1E50a1429074ec53a4,
        0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1,
        0x97D37E8B619cF4C6145da456766CA4FA157292D3,
        0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4,
        0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f,
        0xFb9Cbb2FEDEc281B80AeF79Cc1f39d547EFB956e
    ];

    address[] private asteraUsers = [
        0x1ac686c047283D7EF65345475A2633b6904ECa4d,
        0xbeb15caee71001d82F430E4deda80e16dDf438Db,
        0xd52929B69680A6f74D2eB9c8F1ef482f37b1b32B,
        0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f
    ];

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

    function testBadDebtLineaMiniPool() public {
        uint256 badDebt = 0;
        uint256 badDebtExcludingHacker = 0;
        address[] memory users = lineaUsers;
        address miniPool = 0x52280eA8979d52033E14df086F4dF555a258bEb4;
        for (uint256 idx = 0; idx < users.length; idx++) {
            Liquidator.UsdCollateralAndDebt memory usdCollateralAndDebt =
                liquidator.calculateUserCollateraAndDebtInUsd(users[idx], miniPool);
            if (
                users[idx] != 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
                    && users[idx] != 0x9520C9040338bE61005590cC1BD15caa10a6613c
                    && users[idx] != 0x1D0A98B5daB763FaC9dd4d3d0FE7ada18DBb3535
                    && users[idx] != 0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec
                    && users[idx] != 0xA27eBF925Ec2D1db0cB6b5CAbDab108F71fa6b53
                    && users[idx] != 0x08ef8C80eBcFCb6a3D1460657c55042cEd5F45D3
                    && users[idx] != 0x76F844359ffBe267F4c02ffD76184e27b1AeBE6B
                    && users[idx] != 0x9B3020F0cABc4bA0346cce5FC02e7Cf681E0e227
                    && users[idx] != 0x9c57F65aB8c45E52128ea6630615f54E3038a4bd
            ) {
                console2.log("User: ", users[idx]);
            } else {
                console2.log("->>> HACKER: ", users[idx]);
            }
            console2.log("  USD Collateral: %8e", usdCollateralAndDebt.userUsdCollateral);
            console2.log("  USD Debt: %8e", usdCollateralAndDebt.userUsdDebt);

            if (usdCollateralAndDebt.userUsdDebt > usdCollateralAndDebt.userUsdCollateral) {
                console2.log(
                    "  Bad Debt: %8e",
                    (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral)
                );
                badDebt +=
                    (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral);
                console2.log("    - Borrowed tokens: ");
                for (
                    uint256 i = 0;
                    usdCollateralAndDebt.debtTokens[i] != address(0)
                        && i < usdCollateralAndDebt.debtTokens.length;
                    i++
                ) {
                    console2.log(
                        "      * %s: %8e",
                        IERC20Detailed(usdCollateralAndDebt.debtTokens[i]).symbol(),
                        usdCollateralAndDebt.debtAmount[i] * 1e8
                            / 10 ** IERC20Detailed(usdCollateralAndDebt.debtTokens[i]).decimals()
                    );
                    if (
                        users[idx] != 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
                            && users[idx] != 0x9520C9040338bE61005590cC1BD15caa10a6613c
                            && users[idx] != 0x1D0A98B5daB763FaC9dd4d3d0FE7ada18DBb3535
                            && users[idx] != 0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec
                            && users[idx] != 0xA27eBF925Ec2D1db0cB6b5CAbDab108F71fa6b53
                            && users[idx] != 0x08ef8C80eBcFCb6a3D1460657c55042cEd5F45D3
                            && users[idx] != 0x76F844359ffBe267F4c02ffD76184e27b1AeBE6B
                            && users[idx] != 0x9B3020F0cABc4bA0346cce5FC02e7Cf681E0e227
                            && users[idx] != 0x9c57F65aB8c45E52128ea6630615f54E3038a4bd
                    ) {
                        assetSum[usdCollateralAndDebt.debtTokens[i]] +=
                            usdCollateralAndDebt.debtAmount[i];
                    }
                }
                if (
                    users[idx] != 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
                        && users[idx] != 0x9520C9040338bE61005590cC1BD15caa10a6613c
                        && users[idx] != 0x1D0A98B5daB763FaC9dd4d3d0FE7ada18DBb3535
                        && users[idx] != 0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec
                        && users[idx] != 0xA27eBF925Ec2D1db0cB6b5CAbDab108F71fa6b53
                        && users[idx] != 0x08ef8C80eBcFCb6a3D1460657c55042cEd5F45D3
                        && users[idx] != 0x76F844359ffBe267F4c02ffD76184e27b1AeBE6B
                        && users[idx] != 0x9B3020F0cABc4bA0346cce5FC02e7Cf681E0e227
                        && users[idx] != 0x9c57F65aB8c45E52128ea6630615f54E3038a4bd
                ) {
                    badDebtExcludingHacker +=
                        (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral);
                }
            } else {
                console2.log("  Bad Debt: 0");
            }
        }

        console2.log("FINAL BAD DEBT: %8e", badDebt);
        console2.log("FINAL BAD DEBT excluding hacker: %8e", badDebtExcludingHacker);
        console2.log("---------------------------------------");
        (address[] memory reserveList,) = IMiniPool(miniPool).getReservesList();
        IAERC6909 erc6909 = IAERC6909(
            IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).getMiniPoolToAERC6909(miniPool)
        );
        for (uint256 idx = 0; idx < reserveList.length; idx++) {
            (,, bool isTranched) = erc6909.getIdForUnderlying(reserveList[idx]);
            if (isTranched) {
                console2.log(
                    "Total borrowed (excluding hacker) for %s : %8e",
                    IERC20Detailed(IAToken(reserveList[idx]).UNDERLYING_ASSET_ADDRESS()).symbol(),
                    assetSum[IAToken(reserveList[idx]).UNDERLYING_ASSET_ADDRESS()] * 1e8
                        / 10
                            ** IERC20Detailed(IAToken(reserveList[idx]).UNDERLYING_ASSET_ADDRESS()).decimals(
                            )
                );
            } else {
                console2.log(
                    "Total borrowed (excluding hacker) for %s : %8e",
                    IERC20Detailed(reserveList[idx]).symbol(),
                    assetSum[reserveList[idx]] * 1e8
                        / 10 ** IERC20Detailed(reserveList[idx]).decimals()
                );
            }
        }
        console2.log("---------------------------------------");
    }

    function testBadDebtRex33MiniPool() public {
        uint256 badDebt = 0;
        uint256 badDebtExcludingHacker = 0;
        address[] memory users = rex33Users;
        address miniPool = 0x65559abECD1227Cc1779F500453Da1f9fcADd928;
        for (uint256 idx = 0; idx < users.length; idx++) {
            Liquidator.UsdCollateralAndDebt memory usdCollateralAndDebt =
                liquidator.calculateUserCollateraAndDebtInUsd(users[idx], miniPool);
            if (
                users[idx] != 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
                    && users[idx] != 0x9520C9040338bE61005590cC1BD15caa10a6613c
                    && users[idx] != 0x1D0A98B5daB763FaC9dd4d3d0FE7ada18DBb3535
                    && users[idx] != 0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec
                    && users[idx] != 0xA27eBF925Ec2D1db0cB6b5CAbDab108F71fa6b53
                    && users[idx] != 0x08ef8C80eBcFCb6a3D1460657c55042cEd5F45D3
                    && users[idx] != 0x76F844359ffBe267F4c02ffD76184e27b1AeBE6B
                    && users[idx] != 0x9B3020F0cABc4bA0346cce5FC02e7Cf681E0e227
                    && users[idx] != 0x9c57F65aB8c45E52128ea6630615f54E3038a4bd
            ) {
                console2.log("User: ", users[idx]);
            } else {
                console2.log("->>> HACKER: ", users[idx]);
            }
            console2.log("  USD Collateral: %8e", usdCollateralAndDebt.userUsdCollateral);
            console2.log("  USD Debt: %8e", usdCollateralAndDebt.userUsdDebt);

            if (usdCollateralAndDebt.userUsdDebt > usdCollateralAndDebt.userUsdCollateral) {
                console2.log(
                    "  Bad Debt: %8e",
                    (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral)
                );
                badDebt +=
                    (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral);
                console2.log("    - Borrowed tokens: ");
                for (
                    uint256 i = 0;
                    usdCollateralAndDebt.debtTokens[i] != address(0)
                        && i < usdCollateralAndDebt.debtTokens.length;
                    i++
                ) {
                    console2.log(
                        "      * %s: %8e",
                        IERC20Detailed(usdCollateralAndDebt.debtTokens[i]).symbol(),
                        usdCollateralAndDebt.debtAmount[i] * 1e8
                            / 10 ** IERC20Detailed(usdCollateralAndDebt.debtTokens[i]).decimals()
                    );
                    if (
                        users[idx] != 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
                            && users[idx] != 0x9520C9040338bE61005590cC1BD15caa10a6613c
                            && users[idx] != 0x1D0A98B5daB763FaC9dd4d3d0FE7ada18DBb3535
                            && users[idx] != 0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec
                            && users[idx] != 0xA27eBF925Ec2D1db0cB6b5CAbDab108F71fa6b53
                            && users[idx] != 0x08ef8C80eBcFCb6a3D1460657c55042cEd5F45D3
                            && users[idx] != 0x76F844359ffBe267F4c02ffD76184e27b1AeBE6B
                            && users[idx] != 0x9B3020F0cABc4bA0346cce5FC02e7Cf681E0e227
                            && users[idx] != 0x9c57F65aB8c45E52128ea6630615f54E3038a4bd
                    ) {
                        assetSum[usdCollateralAndDebt.debtTokens[i]] +=
                            usdCollateralAndDebt.debtAmount[i];
                    }
                }
                if (
                    users[idx] != 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
                        && users[idx] != 0x9520C9040338bE61005590cC1BD15caa10a6613c
                        && users[idx] != 0x1D0A98B5daB763FaC9dd4d3d0FE7ada18DBb3535
                        && users[idx] != 0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec
                        && users[idx] != 0xA27eBF925Ec2D1db0cB6b5CAbDab108F71fa6b53
                        && users[idx] != 0x08ef8C80eBcFCb6a3D1460657c55042cEd5F45D3
                        && users[idx] != 0x76F844359ffBe267F4c02ffD76184e27b1AeBE6B
                        && users[idx] != 0x9B3020F0cABc4bA0346cce5FC02e7Cf681E0e227
                        && users[idx] != 0x9c57F65aB8c45E52128ea6630615f54E3038a4bd
                ) {
                    badDebtExcludingHacker +=
                        (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral);
                }
            } else {
                console2.log("  Bad Debt: 0");
            }
        }

        console2.log("FINAL BAD DEBT: %8e", badDebt);
        console2.log("FINAL BAD DEBT excluding hacker: %8e", badDebtExcludingHacker);
        console2.log("---------------------------------------");
        (address[] memory reserveList,) = IMiniPool(miniPool).getReservesList();
        IAERC6909 erc6909 = IAERC6909(
            IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).getMiniPoolToAERC6909(miniPool)
        );
        for (uint256 idx = 0; idx < reserveList.length; idx++) {
            (,, bool isTranched) = erc6909.getIdForUnderlying(reserveList[idx]);
            if (isTranched) {
                console2.log(
                    "Total borrowed (excluding hacker) for %s : %8e",
                    IERC20Detailed(IAToken(reserveList[idx]).UNDERLYING_ASSET_ADDRESS()).symbol(),
                    assetSum[IAToken(reserveList[idx]).UNDERLYING_ASSET_ADDRESS()] * 1e8
                        / 10
                            ** IERC20Detailed(IAToken(reserveList[idx]).UNDERLYING_ASSET_ADDRESS()).decimals(
                            )
                );
            } else {
                console2.log(
                    "Total borrowed (excluding hacker) for %s : %8e",
                    IERC20Detailed(reserveList[idx]).symbol(),
                    assetSum[reserveList[idx]] * 1e8
                        / 10 ** IERC20Detailed(reserveList[idx]).decimals()
                );
            }
        }
        console2.log("---------------------------------------");
    }

    function testBadDebtLstMiniPool() public view {
        uint256 badDebt = 0;
        uint256 badDebtExcludingHacker = 0;
        address[] memory users = lstUsers;
        for (uint256 idx = 0; idx < users.length; idx++) {
            Liquidator.UsdCollateralAndDebt memory usdCollateralAndDebt = liquidator
                .calculateUserCollateraAndDebtInUsd(
                users[idx], 0x0baFB30B72925e6d53F4d0A089bE1CeFbB5e3401
            );
            if (
                users[idx] != 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
                    && users[idx] != 0x9520C9040338bE61005590cC1BD15caa10a6613c
                    && users[idx] != 0x1D0A98B5daB763FaC9dd4d3d0FE7ada18DBb3535
                    && users[idx] != 0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec
                    && users[idx] != 0xA27eBF925Ec2D1db0cB6b5CAbDab108F71fa6b53
                    && users[idx] != 0x08ef8C80eBcFCb6a3D1460657c55042cEd5F45D3
                    && users[idx] != 0x76F844359ffBe267F4c02ffD76184e27b1AeBE6B
                    && users[idx] != 0x9B3020F0cABc4bA0346cce5FC02e7Cf681E0e227
                    && users[idx] != 0x9c57F65aB8c45E52128ea6630615f54E3038a4bd
            ) {
                console2.log("User: ", users[idx]);
            } else {
                console2.log("->>> HACKER: ", users[idx]);
            }
            console2.log("  USD Collateral: %8e", usdCollateralAndDebt.userUsdCollateral);
            console2.log("  USD Debt: %8e", usdCollateralAndDebt.userUsdDebt);

            if (usdCollateralAndDebt.userUsdDebt > usdCollateralAndDebt.userUsdCollateral) {
                console2.log(
                    "  Bad Debt: %8e",
                    (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral)
                );
                badDebt +=
                    (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral);
                console2.log("    - Borrowed tokens: ");
                for (
                    uint256 i = 0;
                    usdCollateralAndDebt.debtTokens[i] != address(0)
                        && i < usdCollateralAndDebt.debtTokens.length;
                    i++
                ) {
                    console2.log(
                        "      * %s: %8e",
                        IERC20Detailed(usdCollateralAndDebt.debtTokens[i]).symbol(),
                        usdCollateralAndDebt.debtAmount[i] * 1e8
                            / 10 ** IERC20Detailed(usdCollateralAndDebt.debtTokens[i]).decimals()
                    );
                }
                if (
                    users[idx] != 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
                        && users[idx] != 0x9520C9040338bE61005590cC1BD15caa10a6613c
                        && users[idx] != 0x1D0A98B5daB763FaC9dd4d3d0FE7ada18DBb3535
                        && users[idx] != 0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec
                        && users[idx] != 0xA27eBF925Ec2D1db0cB6b5CAbDab108F71fa6b53
                        && users[idx] != 0x08ef8C80eBcFCb6a3D1460657c55042cEd5F45D3
                        && users[idx] != 0x76F844359ffBe267F4c02ffD76184e27b1AeBE6B
                        && users[idx] != 0x9B3020F0cABc4bA0346cce5FC02e7Cf681E0e227
                        && users[idx] != 0x9c57F65aB8c45E52128ea6630615f54E3038a4bd
                ) {
                    badDebtExcludingHacker +=
                        (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral);
                }
            } else {
                console2.log("  Bad Debt: 0");
            }
        }

        console2.log("FINAL BAD DEBT: %8e", badDebt);
        console2.log("FINAL BAD DEBT excluding hacker: %8e", badDebtExcludingHacker);
    }

    function testBadDebtAsteraMiniPool() public view {
        uint256 badDebt = 0;
        uint256 badDebtExcludingHacker = 0;
        address[] memory users = lstUsers;
        for (uint256 idx = 0; idx < users.length; idx++) {
            Liquidator.UsdCollateralAndDebt memory usdCollateralAndDebt = liquidator
                .calculateUserCollateraAndDebtInUsd(
                users[idx], 0xE7a2c97601076065C3178BDbb22C61933f850B03
            );
            if (
                users[idx] != 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
                    && users[idx] != 0x9520C9040338bE61005590cC1BD15caa10a6613c
                    && users[idx] != 0x1D0A98B5daB763FaC9dd4d3d0FE7ada18DBb3535
                    && users[idx] != 0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec
                    && users[idx] != 0xA27eBF925Ec2D1db0cB6b5CAbDab108F71fa6b53
                    && users[idx] != 0x08ef8C80eBcFCb6a3D1460657c55042cEd5F45D3
                    && users[idx] != 0x76F844359ffBe267F4c02ffD76184e27b1AeBE6B
                    && users[idx] != 0x9B3020F0cABc4bA0346cce5FC02e7Cf681E0e227
                    && users[idx] != 0x9c57F65aB8c45E52128ea6630615f54E3038a4bd
            ) {
                console2.log("User: ", users[idx]);
            } else {
                console2.log("->>> HACKER: ", users[idx]);
            }
            console2.log("  USD Collateral: %8e", usdCollateralAndDebt.userUsdCollateral);
            console2.log("  USD Debt: %8e", usdCollateralAndDebt.userUsdDebt);

            if (usdCollateralAndDebt.userUsdDebt > usdCollateralAndDebt.userUsdCollateral) {
                console2.log(
                    "  Bad Debt: %8e",
                    (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral)
                );
                badDebt +=
                    (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral);
                console2.log("    - Borrowed tokens: ");
                for (
                    uint256 i = 0;
                    usdCollateralAndDebt.debtTokens[i] != address(0)
                        && i < usdCollateralAndDebt.debtTokens.length;
                    i++
                ) {
                    console2.log(
                        "      * %s: %8e",
                        IERC20Detailed(usdCollateralAndDebt.debtTokens[i]).symbol(),
                        usdCollateralAndDebt.debtAmount[i] * 1e8
                            / 10 ** IERC20Detailed(usdCollateralAndDebt.debtTokens[i]).decimals()
                    );
                }
                if (
                    users[idx] != 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
                        && users[idx] != 0x9520C9040338bE61005590cC1BD15caa10a6613c
                        && users[idx] != 0x1D0A98B5daB763FaC9dd4d3d0FE7ada18DBb3535
                        && users[idx] != 0x510A269A93736B5B5E3C2133e8f2e7D829ca3Fec
                        && users[idx] != 0xA27eBF925Ec2D1db0cB6b5CAbDab108F71fa6b53
                        && users[idx] != 0x08ef8C80eBcFCb6a3D1460657c55042cEd5F45D3
                        && users[idx] != 0x76F844359ffBe267F4c02ffD76184e27b1AeBE6B
                        && users[idx] != 0x9B3020F0cABc4bA0346cce5FC02e7Cf681E0e227
                        && users[idx] != 0x9c57F65aB8c45E52128ea6630615f54E3038a4bd
                ) {
                    badDebtExcludingHacker +=
                        (usdCollateralAndDebt.userUsdDebt - usdCollateralAndDebt.userUsdCollateral);
                }
            } else {
                console2.log("  Bad Debt: 0");
            }
        }

        console2.log("FINAL BAD DEBT: %8e", badDebt);
        console2.log("FINAL BAD DEBT excluding hacker: %8e", badDebtExcludingHacker);
    }

    function testLiquidation() public {}
}
