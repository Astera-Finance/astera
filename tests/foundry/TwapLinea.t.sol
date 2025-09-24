// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IEtherexPair} from "contracts/interfaces/IEtherexPair.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {EtherexTwap} from "contracts/protocol/core/twaps/EtherexTwap.sol";
import {EtherexVolatileTwap} from "contracts/protocol/core/twaps/EtherexVolatileTwap.sol";
import {EtherexVolatileTwapOld} from "contracts/protocol/core/twaps/EtherexVolatileTwapOld.sol";
import {IRouter} from "contracts/interfaces/IRouter.sol";
import {ITwapOracle} from "contracts/interfaces/ITwapOracle.sol";
import {IOracle} from "contracts/interfaces/IOracle.sol";
import {console2} from "forge-std/console2.sol";

contract TwapLineaTest is Test {
    ERC20 constant REX = ERC20(0xEfD81eeC32B9A8222D1842ec3d99c7532C31e348);
    ERC20 constant WSTETH = ERC20(0xB5beDd42000b71FddE22D3eE8a79Bd49A568fC8F);
    ERC20 constant ASUSD = ERC20(0xa500000000e482752f032eA387390b6025a2377b);
    ERC20 constant USDC = ERC20(0x176211869cA2b568f2A7D4EE941E073a821EE1ff);
    ERC20 constant REX33 = ERC20(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4);
    IEtherexPair constant ASUSD_USDC_PAIR = IEtherexPair(0x7b930713103A964c12E8b808c83F57E40d9ad495);
    IEtherexPair constant REX33_USDC_PAIR = IEtherexPair(0xeacD56565aB642FB0Dc2820b51547fE416EE8697);
    IEtherexPair constant REX_WSTETH_PAIR = IEtherexPair(0x97a51bAEF69335b6248AFEfEBD95E90399D37b0a);
    uint256 constant TIME_WINDOW = 30 minutes;
    uint256 constant LOG_WINDOW = 7 days;
    uint256 constant MIN_PRICE = 0;
    address WSTETH_USDC_PRICE_FEED = 0x8eCE1AbA32716FdDe8D6482bfd88E9a0ee01f565;
    EtherexVolatileTwap asUsdEtherexVolatileTwap;
    EtherexVolatileTwap rex33EtherexVolatileTwap;
    EtherexTwap wstEthRexTwap;
    bool constant USE_QUOTE = false;

    IOracle oracle = IOracle(0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87);
    address constant ETHEREX_ROUTER = 0x32dB39c56C171b4c96e974dDeDe8E42498929c54;

    function setUp() public {
        // LINEA setup
        uint256 opFork = vm.createSelectFork(
            "https://linea-mainnet.infura.io/v3/f47a8617e11b481fbf52c08d4e9ecf0d", 23687274
        );
        assertEq(vm.activeFork(), opFork);
        asUsdEtherexVolatileTwap = new EtherexVolatileTwap(
            ASUSD_USDC_PAIR, address(this), uint56(TIME_WINDOW), uint128(MIN_PRICE)
        );

        rex33EtherexVolatileTwap = new EtherexVolatileTwap(
            REX33_USDC_PAIR, address(this), uint56(TIME_WINDOW), uint128(MIN_PRICE)
        );

        wstEthRexTwap = new EtherexTwap(
            REX_WSTETH_PAIR,
            address(this),
            uint56(TIME_WINDOW),
            0,
            WSTETH_USDC_PRICE_FEED,
            address(REX)
        );
        address[] memory assets = new address[](1);
        assets[0] = address(REX);
        address[] memory sources = new address[](1);
        sources[0] = address(wstEthRexTwap);
        uint256[] memory timeouts = new uint256[](1);
        timeouts[0] = 86400;
        vm.prank(0x7D66a2e916d79c0988D41F1E50a1429074ec53a4);
        oracle.setAssetSources(assets, sources, timeouts);
    }

    function testAssetPriceAfterSwaps() public {
        console2.log(
            "The USDC price current: ", asUsdEtherexVolatileTwap.getAssetPrice(address(ASUSD))
        );
        console2.log(
            "The USDC price quote: ",
            asUsdEtherexVolatileTwap.getAssetPriceWithSample(address(ASUSD))
        );
        console2.log(
            "The USDC price sampleWindow: ",
            asUsdEtherexVolatileTwap.getAssetPriceOriginal(address(ASUSD))
        );

        console2.log(
            "The REX33 price current: ", rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
        );
        console2.log(
            "The REX33 price quote: ",
            rex33EtherexVolatileTwap.getAssetPriceWithSample(address(REX33))
        );
        console2.log(
            "The REX33 price sampleWindow: ",
            rex33EtherexVolatileTwap.getAssetPriceOriginal(address(REX33))
        );
    }

    function testCompabilityWithOracle() public {
        console.log(oracle.getAssetPrice(address(REX)));
    }

    function test_singleBlockManipulation() public {
        address manipulator = makeAddr("manipulator");
        deal(address(REX), manipulator, 1000000 ether);

        // register initial oracle price
        int256 price_1 = wstEthRexTwap.latestAnswer();
        (, int256 price_2,,,) = wstEthRexTwap.latestRoundData();

        // perform a large swap
        vm.startPrank(manipulator);
        REX.approve(ETHEREX_ROUTER, 1000000 ether);

        IRouter.route[] memory swapRoute = new IRouter.route[](1);
        swapRoute[0] = IRouter.route({from: address(REX), to: address(WSTETH), stable: false});
        (uint256 reserve0, uint256 reserve1,) = wstEthRexTwap.etherexPair().getReserves();
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            (address(REX) == wstEthRexTwap.etherexPair().token0() ? reserve0 : reserve1) / 10,
            0,
            swapRoute,
            manipulator,
            type(uint32).max
        );
        vm.stopPrank();
        (, int256 tmpAnswer,,,) = wstEthRexTwap.latestRoundData();
        // price should not have changed
        assertEq(wstEthRexTwap.latestAnswer(), price_1, "single block price variation");
        assertEq(tmpAnswer, price_2, "single block price variation");
        assertEq(price_1, price_2);
    }

    function test_priceManipulation(uint256 skipTime) public {
        skipTime = bound(skipTime, 20 minutes, 70 minutes);

        // clean twap for test
        skip(1 hours);
        REX33_USDC_PAIR.sync();
        skip(1 hours);
        REX33_USDC_PAIR.sync();
        skip(1 hours);

        int256 price_1 = wstEthRexTwap.latestAnswer();
        (, int256 price_2,,,) = wstEthRexTwap.latestRoundData();

        // perform a large swap
        address manipulator = makeAddr("manipulator");
        vm.startPrank(manipulator);
        REX.approve(ETHEREX_ROUTER, 1000000 ether);

        IRouter.route[] memory swapRoute = new IRouter.route[](1);
        swapRoute[0] = IRouter.route({from: address(REX), to: address(WSTETH), stable: false});
        (uint256 reserve0, uint256 reserve1,) = wstEthRexTwap.etherexPair().getReserves();
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            (address(REX) == wstEthRexTwap.etherexPair().token0() ? reserve0 : reserve1) / 10,
            0,
            swapRoute,
            manipulator,
            type(uint32).max
        );
        vm.stopPrank();

        // wait
        skip(skipTime);

        (, int256 tmpAnswer,,,) = wstEthRexTwap.latestRoundData();
        // price should not have changed
        assertGt(wstEthRexTwap.latestAnswer(), price_1, "single block price variation");
        assertGt(tmpAnswer, price_2, "single block price variation");
        assertEq(price_1, price_2);
        // assert(false);
    }

    function test_EtherexTwapMultiplePriceManipulationsAll18Decimals() public {
        multiplePriceManipulationWithLoopChainlink(5 minutes, wstEthRexTwap);
        assert(false);
    }

    function multiplePriceManipulationWithLoopChainlink(uint256 granuality, EtherexTwap twap)
        internal
    {
        uint256 period = 2 * TIME_WINDOW / granuality;

        IEtherexPair etherexPair = IEtherexPair(twap.getPairAddress());

        // clean twap for test
        skip(1 hours);
        etherexPair.sync();
        skip(1 hours);
        etherexPair.sync();
        skip(1 hours);

        ERC20 token0 = ERC20(etherexPair.token0());
        ERC20 token1 = ERC20(etherexPair.token1());

        // perform a large swap
        address manipulator = makeAddr("manipulator");
        deal(address(token0), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (uint256 reserve0, uint256 reserve1,) = etherexPair.getReserves();
        uint256 amountIn = (address(token0) == etherexPair.token0() ? reserve0 : reserve1) / 4;
        token0.approve(ETHEREX_ROUTER, amountIn);

        uint256 timeElapsed = 0;

        console.log(
            "Time: %s, Twap1: %s, Spot: %s",
            timeElapsed / 1 minutes,
            uint256(twap.latestAnswer()),
            uint256(twap.getSpotPrice())
        );

        IRouter.route[] memory swapRoute = new IRouter.route[](1);
        swapRoute[0] = IRouter.route({from: address(token0), to: address(token1), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        for (uint256 idx = 0; idx < period; idx++) {
            skip(granuality);
            etherexPair.sync();
            timeElapsed += granuality;
            //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));

            console.log(
                "Time: %s, Twap1: %s, Spot: %s",
                timeElapsed / 1 minutes,
                uint256(twap.latestAnswer()),
                uint256(twap.getSpotPrice())
            );
        }

        // perform a large swap
        deal(address(token1), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (reserve0, reserve1,) = etherexPair.getReserves();
        amountIn = (address(token1) == etherexPair.token0() ? reserve0 : reserve1) / 4;
        token1.approve(ETHEREX_ROUTER, amountIn);

        swapRoute[0] = IRouter.route({from: address(token1), to: address(token0), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        for (uint256 idx = 0; idx < period; idx++) {
            skip(granuality);
            timeElapsed += granuality;
            etherexPair.sync();
            //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));

            console.log(
                "Time: %s, Twap1: %s, Spot: %s",
                timeElapsed / 1 minutes,
                uint256(twap.latestAnswer()),
                uint256(twap.getSpotPrice())
            );
        }

        // perform a large swap
        manipulator = makeAddr("manipulator");
        deal(address(token0), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (reserve0, reserve1,) = etherexPair.getReserves();
        amountIn = (address(token0) == etherexPair.token0() ? reserve0 : reserve1) / 10;
        token0.approve(ETHEREX_ROUTER, amountIn);

        swapRoute[0] = IRouter.route({from: address(token0), to: address(token1), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        for (uint256 idx = 0; idx < period; idx++) {
            skip(granuality);
            etherexPair.sync();
            timeElapsed += granuality;
            //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));

            console.log(
                "Time: %s, Twap1: %s, Spot: %s",
                timeElapsed / 1 minutes,
                uint256(twap.latestAnswer()),
                uint256(twap.getSpotPrice())
            );
        }

        // perform a large swap
        deal(address(token1), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (reserve0, reserve1,) = etherexPair.getReserves();
        amountIn = (address(token1) == etherexPair.token0() ? reserve0 : reserve1) / 4;
        token1.approve(ETHEREX_ROUTER, amountIn);

        swapRoute[0] = IRouter.route({from: address(token1), to: address(token0), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        for (uint256 idx = 0; idx < period; idx++) {
            skip(granuality);
            etherexPair.sync();
            timeElapsed += granuality;
            //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));

            console.log(
                "Time: %s, Twap1: %s, Spot: %s",
                timeElapsed / 1 minutes,
                uint256(twap.latestAnswer()),
                uint256(twap.getSpotPrice())
            );
        }
    }

    // function test_EtherexTwapMultiplePriceManipulations6Decimals() public {
    //     address twap = address(
    //         new EtherexTwap(address(REX33_USDC_PAIR), address(this), uint56(TIME_WINDOW), 0)
    //     );
    //     multiplePriceManipulationWithLoop(5 minutes, ITwapOracle(twap));
    //     assert(false);
    // }

    // function test_EtherexTwapMultiplePriceManipulationsOld() public {
    //     address twap = address(
    //         new EtherexVolatileTwapOld(
    //             REX_WSTETH_PAIR, address(WSTETH), address(this), uint56(TIME_WINDOW), 0
    //         )
    //     );
    //     multiplePriceManipulationWithLoop(5 minutes, ITwapOracle(twap));
    //     assert(false);
    // }

    // function test_EtherexTwapMultiplePriceManipulationsExperiment() public {
    //     address twap =
    //         address(new EtherexVolatileTwap(REX_WSTETH_PAIR, address(this), uint56(TIME_WINDOW), 0));
    //     multiplePriceManipulationWithLoop(5 minutes, ITwapOracle(twap));
    //     assert(false);
    // }

    // function test_PriceManipulationWithLoop() public {
    //     // string memory path = "oracleSim.txt";

    //     uint256 granuality = 5 minutes;
    //     uint256 period = (2 * TIME_WINDOW) / granuality;
    //     uint256 skipTime = 1 hours;

    //     // clean twap for test
    //     skip(skipTime);
    //     rex33EtherexVolatileTwap.etherexPair().sync();
    //     skip(skipTime);
    //     rex33EtherexVolatileTwap.etherexPair().sync();
    //     skip(skipTime);

    //     // register initial oracle price

    //     uint256 price_1 = rex33EtherexVolatileTwap.getAssetPrice(address(REX33));
    //     uint256 price_2 = rex33EtherexVolatileTwap.getAssetPriceWithSample(address(REX33));
    //     uint256 price_3 = rex33EtherexVolatileTwap.getAssetPriceOriginal(address(REX33));
    //     console.log("1.Initial price after stabilization: %s", price_1);
    //     console.log("2.Initial price after stabilization: %s", price_2);
    //     console.log("3.Initial price after stabilization: %s", price_3);

    //     uint256 timeElapsed = 0;
    //     if (USE_QUOTE) {
    //         console.log(
    //             "0.Time: %s, Twap1: %s, Spot: %s",
    //             timeElapsed / 1 minutes,
    //             rex33EtherexVolatileTwap.getAssetPrice(address(REX33)),
    //             rex33EtherexVolatileTwap.getSpotPrice(address(REX33))
    //         );
    //     } else {
    //         console2.log(
    //             "0.Time: %s, Twap2: %s, Spot: %s",
    //             timeElapsed / 1 minutes,
    //             rex33EtherexVolatileTwap.getAssetPriceOriginal(address(REX33)),
    //             rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
    //         );
    //     }

    //     // perform a large swap
    //     address manipulator = makeAddr("manipulator");
    //     deal(address(REX33), manipulator, 2 ** 128);
    //     vm.startPrank(manipulator);
    //     (uint256 reserve0, uint256 reserve1,) = REX33_USDC_PAIR.getReserves();
    //     uint256 amountIn = (address(REX33) == REX33_USDC_PAIR.token0() ? reserve0 : reserve1) / 4;
    //     REX33.approve(ETHEREX_ROUTER, amountIn);

    //     IRouter.route[] memory swapRoute = new IRouter.route[](1);
    //     swapRoute[0] = IRouter.route({from: address(REX33), to: address(USDC), stable: false});
    //     IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
    //         amountIn, 0, swapRoute, manipulator, type(uint32).max
    //     );
    //     vm.stopPrank();

    //     // wait
    //     for (uint256 idx = 0; idx < period; idx++) {
    //         skip(granuality);
    //         timeElapsed += granuality;
    //         rex33EtherexVolatileTwap.etherexPair().sync();
    //         //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));
    //         if (USE_QUOTE) {
    //             console.log(
    //                 "1. Time: %s, Twap1: %s, Spot: %s",
    //                 timeElapsed / 1 minutes,
    //                 rex33EtherexVolatileTwap.getAssetPrice(address(REX33)),
    //                 rex33EtherexVolatileTwap.getSpotPrice(address(REX33))
    //             );
    //         } else {
    //             console2.log(
    //                 "1.Time: %s, Twap2: %s, Spot: %s",
    //                 timeElapsed / 1 minutes,
    //                 rex33EtherexVolatileTwap.getAssetPriceOriginal(address(REX33)),
    //                 rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
    //             );
    //         }

    //         // vm.writeFile(path, data);
    //     }
    //     deal(address(REX33), manipulator, 2 ** 128);
    //     vm.startPrank(manipulator);
    //     (reserve0, reserve1,) = REX33_USDC_PAIR.getReserves();
    //     amountIn = (address(REX33) == REX33_USDC_PAIR.token0() ? reserve0 : reserve1) / 40;
    //     REX33.approve(ETHEREX_ROUTER, amountIn);

    //     swapRoute = new IRouter.route[](1);
    //     swapRoute[0] = IRouter.route({from: address(REX33), to: address(USDC), stable: false});
    //     IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
    //         amountIn, 0, swapRoute, manipulator, type(uint32).max
    //     );
    //     // wait
    //     for (uint256 idx = 0; idx < period; idx++) {
    //         skip(granuality);
    //         timeElapsed += granuality;
    //         rex33EtherexVolatileTwap.etherexPair().sync();
    //         //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));
    //         if (USE_QUOTE) {
    //             console.log(
    //                 "2. Time: %s, Twap1: %s, Spot: %s",
    //                 timeElapsed / 1 minutes,
    //                 rex33EtherexVolatileTwap.getAssetPrice(address(REX33)),
    //                 rex33EtherexVolatileTwap.getSpotPrice(address(REX33))
    //             );
    //         } else {
    //             console2.log(
    //                 "2. Time: %s, Twap2: %s, Spot: %s",
    //                 timeElapsed / 1 minutes,
    //                 rex33EtherexVolatileTwap.getAssetPriceOriginal(address(REX33)),
    //                 rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
    //             );
    //         }

    //         // vm.writeFile(path, data);
    //     }
    //     assert(false);
    // }

    // function multiplePriceManipulationWithLoop(uint256 granuality, ITwapOracle twap) internal {
    //     uint256 period = 2 * TIME_WINDOW / granuality;

    //     IEtherexPair etherexPair = IEtherexPair(twap.getPairAddress());

    //     // clean twap for test
    //     skip(1 hours);
    //     etherexPair.sync();
    //     skip(1 hours);
    //     etherexPair.sync();
    //     skip(1 hours);

    //     ERC20 token0 = ERC20(etherexPair.token0());
    //     ERC20 token1 = ERC20(etherexPair.token1());

    //     // perform a large swap
    //     address manipulator = makeAddr("manipulator");
    //     deal(address(token0), manipulator, 2 ** 128);
    //     vm.startPrank(manipulator);
    //     (uint256 reserve0, uint256 reserve1,) = etherexPair.getReserves();
    //     uint256 amountIn = (address(token0) == etherexPair.token0() ? reserve0 : reserve1) / 4;
    //     token0.approve(ETHEREX_ROUTER, amountIn);

    //     uint256 timeElapsed = 0;

    //     console.log(
    //         "Time: %s, Twap1: %s, Spot: %s",
    //         timeElapsed / 1 minutes,
    //         twap.getAssetPrice(address(token1)),
    //         twap.getSpotPrice(address(token1))
    //     );

    //     IRouter.route[] memory swapRoute = new IRouter.route[](1);
    //     swapRoute[0] = IRouter.route({from: address(token0), to: address(token1), stable: false});
    //     IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
    //         amountIn, 0, swapRoute, manipulator, type(uint32).max
    //     );
    //     vm.stopPrank();

    //     // wait
    //     for (uint256 idx = 0; idx < period; idx++) {
    //         skip(granuality);
    //         etherexPair.sync();
    //         timeElapsed += granuality;
    //         //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));

    //         console.log(
    //             "Time: %s, Twap1: %s, Spot: %s",
    //             timeElapsed / 1 minutes,
    //             twap.getAssetPrice(address(token1)),
    //             twap.getSpotPrice(address(token1))
    //         );
    //     }

    //     // perform a large swap
    //     deal(address(token1), manipulator, 2 ** 128);
    //     vm.startPrank(manipulator);
    //     (reserve0, reserve1,) = etherexPair.getReserves();
    //     amountIn = (address(token1) == etherexPair.token0() ? reserve0 : reserve1) / 4;
    //     token1.approve(ETHEREX_ROUTER, amountIn);

    //     swapRoute[0] = IRouter.route({from: address(token1), to: address(token0), stable: false});
    //     IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
    //         amountIn, 0, swapRoute, manipulator, type(uint32).max
    //     );
    //     vm.stopPrank();

    //     // wait
    //     for (uint256 idx = 0; idx < period; idx++) {
    //         skip(granuality);
    //         timeElapsed += granuality;
    //         etherexPair.sync();
    //         //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));

    //         console.log(
    //             "Time: %s, Twap1: %s, Spot: %s",
    //             timeElapsed / 1 minutes,
    //             twap.getAssetPrice(address(token1)),
    //             twap.getSpotPrice(address(token1))
    //         );
    //     }

    //     // perform a large swap
    //     manipulator = makeAddr("manipulator");
    //     deal(address(token0), manipulator, 2 ** 128);
    //     vm.startPrank(manipulator);
    //     (reserve0, reserve1,) = etherexPair.getReserves();
    //     amountIn = (address(token0) == etherexPair.token0() ? reserve0 : reserve1) / 10;
    //     token0.approve(ETHEREX_ROUTER, amountIn);

    //     swapRoute[0] = IRouter.route({from: address(token0), to: address(token1), stable: false});
    //     IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
    //         amountIn, 0, swapRoute, manipulator, type(uint32).max
    //     );
    //     vm.stopPrank();

    //     // wait
    //     for (uint256 idx = 0; idx < period; idx++) {
    //         skip(granuality);
    //         etherexPair.sync();
    //         timeElapsed += granuality;
    //         //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));

    //         console.log(
    //             "Time: %s, Twap1: %s, Spot: %s",
    //             timeElapsed / 1 minutes,
    //             twap.getAssetPrice(address(token1)),
    //             twap.getSpotPrice(address(token1))
    //         );
    //     }

    //     // perform a large swap
    //     deal(address(token1), manipulator, 2 ** 128);
    //     vm.startPrank(manipulator);
    //     (reserve0, reserve1,) = etherexPair.getReserves();
    //     amountIn = (address(token1) == etherexPair.token0() ? reserve0 : reserve1) / 4;
    //     token1.approve(ETHEREX_ROUTER, amountIn);

    //     swapRoute[0] = IRouter.route({from: address(token1), to: address(token0), stable: false});
    //     IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
    //         amountIn, 0, swapRoute, manipulator, type(uint32).max
    //     );
    //     vm.stopPrank();

    //     // wait
    //     for (uint256 idx = 0; idx < period; idx++) {
    //         skip(granuality);
    //         etherexPair.sync();
    //         timeElapsed += granuality;
    //         //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));

    //         console.log(
    //             "Time: %s, Twap1: %s, Spot: %s",
    //             timeElapsed / 1 minutes,
    //             twap.getAssetPrice(address(token1)),
    //             twap.getSpotPrice(address(token1))
    //         );
    //     }
    // }
}
