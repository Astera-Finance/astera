// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IEtherexPair} from "contracts/interfaces/IEtherexPair.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {EtherexVolatileTwap} from "contracts/protocol/core/twaps/EtherexVolatileTwap.sol";
import {EtherexVolatileTwapOld} from "contracts/protocol/core/twaps/EtherexVolatileTwapOld.sol";
import {IRouter} from "contracts/interfaces/IRouter.sol";

import {console2} from "forge-std/console2.sol";

contract TwapLineaTest is Test {
    ERC20 constant ASUSD = ERC20(0xa500000000e482752f032eA387390b6025a2377b);
    ERC20 constant USDC = ERC20(0x176211869cA2b568f2A7D4EE941E073a821EE1ff);
    ERC20 constant REX33 = ERC20(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4);
    IEtherexPair constant ASUSD_USDC_PAIR = IEtherexPair(0x7b930713103A964c12E8b808c83F57E40d9ad495);
    IEtherexPair constant REX33_USDC_PAIR = IEtherexPair(0xeacD56565aB642FB0Dc2820b51547fE416EE8697);
    uint256 constant TIME_WINDOW = 120 minutes;
    uint256 constant LOG_WINDOW = 7 days;
    uint256 constant MIN_PRICE = 0;
    EtherexVolatileTwap asUsdEtherexVolatileTwap;
    EtherexVolatileTwap rex33EtherexVolatileTwap;
    bool constant USE_QUOTE = true;

    address constant ETHEREX_ROUTER = 0x32dB39c56C171b4c96e974dDeDe8E42498929c54;

    function setUp() public {
        // LINEA setup
        uint256 opFork = vm.createSelectFork(
            "https://linea-mainnet.infura.io/v3/f47a8617e11b481fbf52c08d4e9ecf0d"
        );
        assertEq(vm.activeFork(), opFork);
        asUsdEtherexVolatileTwap = new EtherexVolatileTwap(
            ASUSD_USDC_PAIR, address(this), uint56(TIME_WINDOW), uint128(MIN_PRICE)
        );

        rex33EtherexVolatileTwap = new EtherexVolatileTwap(
            REX33_USDC_PAIR, address(this), uint56(TIME_WINDOW), uint128(MIN_PRICE)
        );
    }

    function testAssetPriceAfterSwaps() public {
        console2.log(
            "The USDC price current: ", asUsdEtherexVolatileTwap.getAssetPrice(address(ASUSD))
        );
        console2.log(
            "The USDC price quote: ",
            asUsdEtherexVolatileTwap.getAssetPriceWithQuote(address(ASUSD))
        );
        console2.log(
            "The USDC price sampleWindow: ",
            asUsdEtherexVolatileTwap.getAssetPriceWithSampleWindow(address(ASUSD))
        );

        console2.log(
            "The REX33 price current: ", rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
        );
        console2.log(
            "The REX33 price quote: ",
            rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33))
        );
        console2.log(
            "The REX33 price sampleWindow: ",
            rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33))
        );
    }

    function testCompabilityWithOracle() public {}

    function test_singleBlockManipulation() public {
        address manipulator = makeAddr("manipulator");
        deal(address(REX33), manipulator, 1000000 ether);

        // register initial oracle price
        uint256 price_1 = rex33EtherexVolatileTwap.getAssetPrice(address(REX33));
        uint256 price_2 = rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33));
        uint256 price_3 = rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33));

        // perform a large swap
        vm.startPrank(manipulator);
        REX33.approve(ETHEREX_ROUTER, 1000000 ether);

        IRouter.route[] memory swapRoute = new IRouter.route[](1);
        swapRoute[0] = IRouter.route({from: address(REX33), to: address(USDC), stable: false});
        (uint256 reserve0, uint256 reserve1,) = REX33_USDC_PAIR.getReserves();
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            (address(REX33) == REX33_USDC_PAIR.token0() ? reserve0 : reserve1) / 10,
            0,
            swapRoute,
            manipulator,
            type(uint32).max
        );
        vm.stopPrank();

        // price should not have changed
        assertEq(
            rex33EtherexVolatileTwap.getAssetPrice(address(REX33)),
            price_1,
            "single block price variation"
        );
        assertEq(
            rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33)),
            price_2,
            "single block price variation"
        );
        assertEq(
            rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33)),
            price_3,
            "single block price variation"
        );
    }

    function test_priceManipulation(uint256 skipTime) public {
        skipTime = 30 minutes;

        // clean twap for test
        skip(1 hours);
        REX33_USDC_PAIR.sync();
        skip(1 hours);
        REX33_USDC_PAIR.sync();
        skip(1 hours);

        uint256 price_1 = rex33EtherexVolatileTwap.getAssetPrice(address(REX33));
        uint256 price_2 = rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33));
        uint256 price_3 = rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33));

        // perform a large swap
        address manipulator = makeAddr("manipulator");
        deal(address(REX33), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (uint256 reserve0, uint256 reserve1,) = REX33_USDC_PAIR.getReserves();
        uint256 amountIn = (address(REX33) == REX33_USDC_PAIR.token0() ? reserve0 : reserve1) / 4;
        REX33.approve(ETHEREX_ROUTER, amountIn);

        IRouter.route[] memory swapRoute = new IRouter.route[](1);
        swapRoute[0] = IRouter.route({from: address(REX33), to: address(USDC), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        skip(skipTime);

        console2.log(
            "price_1: %s vs The REX33 price current: %s",
            price_1,
            rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
        );
        console2.log(
            "price_2: %s The REX33 price quote: %s",
            price_2,
            rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33))
        );
        console2.log(
            "price_3: %s The REX33 price sampleWindow: %s",
            price_3,
            rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33))
        );
        // assert(false);
    }

    function test_PriceManipulationWithLoop() public {
        // string memory path = "oracleSim.txt";

        uint256 granuality = 10 minutes;
        uint256 period = (TIME_WINDOW + 2 * granuality) / granuality;
        uint256 skipTime;

        // clean twap for test
        skip(1 hours);
        rex33EtherexVolatileTwap.etherexPair().sync();
        skip(1 hours);
        rex33EtherexVolatileTwap.etherexPair().sync();
        skip(1 hours);

        // register initial oracle price

        uint256 price_1 = rex33EtherexVolatileTwap.getAssetPrice(address(REX33));
        uint256 price_2 = rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33));
        uint256 price_3 = rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33));
        console.log("1.Initial price after stabilization: %s", price_1);
        console.log("2.Initial price after stabilization: %s", price_2);
        console.log("3.Initial price after stabilization: %s", price_3);

        // perform a large swap
        address manipulator = makeAddr("manipulator");
        deal(address(REX33), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (uint256 reserve0, uint256 reserve1,) = REX33_USDC_PAIR.getReserves();
        uint256 amountIn = (address(REX33) == REX33_USDC_PAIR.token0() ? reserve0 : reserve1) / 4;
        REX33.approve(ETHEREX_ROUTER, amountIn);

        IRouter.route[] memory swapRoute = new IRouter.route[](1);
        swapRoute[0] = IRouter.route({from: address(REX33), to: address(USDC), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        skip(skipTime);

        console2.log(
            "price_1: %s vs The REX33 price current: %s",
            price_1,
            rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
        );
        console2.log(
            "price_2: %s The REX33 price quote: %s",
            price_2,
            rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33))
        );
        console2.log(
            "price_3: %s The REX33 price sampleWindow: %s",
            price_3,
            rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33))
        );
        deal(address(REX33), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (reserve0, reserve1,) = REX33_USDC_PAIR.getReserves();
        amountIn = (address(REX33) == REX33_USDC_PAIR.token0() ? reserve0 : reserve1) / 40;
        REX33.approve(ETHEREX_ROUTER, amountIn);

        swapRoute = new IRouter.route[](1);
        swapRoute[0] = IRouter.route({from: address(REX33), to: address(USDC), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        // wait
        uint256 timeElapsed = 0;
        for (uint256 idx = 0; idx < period; idx++) {
            skip(granuality);
            timeElapsed += granuality;
            //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));
            if (USE_QUOTE) {
                console.log(
                    "Time: %s, Twap1: %s, Spot: %s",
                    timeElapsed / 1 minutes,
                    rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33)),
                    rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
                );
            } else {
                console2.log(
                    "Time: %s, Twap2: %s, Spot: %s",
                    timeElapsed / 1 minutes,
                    rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33)),
                    rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
                );
            }

            // vm.writeFile(path, data);
        }
        assert(false);
    }

    function test_MultiplePriceManipulationWithLoop() public {
        uint256 granuality = 10 minutes;
        uint256 period = TIME_WINDOW / granuality;
        uint256 skipTime;

        // clean twap for test
        skip(1 hours);
        rex33EtherexVolatileTwap.etherexPair().sync();
        skip(1 hours);
        rex33EtherexVolatileTwap.etherexPair().sync();
        skip(1 hours);

        // register initial oracle price

        uint256 price_1 = rex33EtherexVolatileTwap.getAssetPrice(address(REX33));
        uint256 price_2 = rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33));
        uint256 price_3 = rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33));
        console.log("1.Initial price after stabilization: %s", price_1);
        console.log("2.Initial price after stabilization: %s", price_2);
        console.log("3.Initial price after stabilization: %s", price_3);

        // perform a large swap
        address manipulator = makeAddr("manipulator");
        deal(address(REX33), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (uint256 reserve0, uint256 reserve1,) = REX33_USDC_PAIR.getReserves();
        uint256 amountIn = (address(REX33) == REX33_USDC_PAIR.token0() ? reserve0 : reserve1) / 4;
        REX33.approve(ETHEREX_ROUTER, amountIn);

        IRouter.route[] memory swapRoute = new IRouter.route[](1);
        swapRoute[0] = IRouter.route({from: address(REX33), to: address(USDC), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        skip(skipTime);

        console2.log(
            "price_1: %s vs The REX33 price current: %s",
            price_1,
            rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
        );
        console2.log(
            "price_2: %s The REX33 price quote: %s",
            price_2,
            rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33))
        );
        console2.log(
            "price_3: %s The REX33 price sampleWindow: %s",
            price_3,
            rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33))
        );

        // wait
        uint256 timeElapsed = 0;
        for (uint256 idx = 0; idx < period; idx++) {
            skip(granuality);
            timeElapsed += granuality;
            //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));
            if (USE_QUOTE) {
                console.log(
                    "Time: %s, Twap1: %s, Spot: %s",
                    timeElapsed / 1 minutes,
                    rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33)),
                    rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
                );
            } else {
                console2.log(
                    "Time: %s, Twap2: %s, Spot: %s",
                    timeElapsed / 1 minutes,
                    rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33)),
                    rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
                );
            }
        }

        // perform a large swap
        deal(address(USDC), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (reserve0, reserve1,) = REX33_USDC_PAIR.getReserves();
        amountIn = (address(USDC) == REX33_USDC_PAIR.token0() ? reserve0 : reserve1) / 4;
        USDC.approve(ETHEREX_ROUTER, amountIn);

        swapRoute[0] = IRouter.route({from: address(USDC), to: address(REX33), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        for (uint256 idx = 0; idx < period; idx++) {
            skip(granuality);
            timeElapsed += granuality;
            //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));
            if (USE_QUOTE) {
                console.log(
                    "Time: %s, Twap1: %s, Spot: %s",
                    timeElapsed / 1 minutes,
                    rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33)),
                    rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
                );
            } else {
                console2.log(
                    "Time: %s, Twap2: %s, Spot: %s",
                    timeElapsed / 1 minutes,
                    rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33)),
                    rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
                );
            }
        }

        // perform a large swap
        manipulator = makeAddr("manipulator");
        deal(address(REX33), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (reserve0, reserve1,) = REX33_USDC_PAIR.getReserves();
        amountIn = (address(REX33) == REX33_USDC_PAIR.token0() ? reserve0 : reserve1) / 10;
        REX33.approve(ETHEREX_ROUTER, amountIn);

        swapRoute[0] = IRouter.route({from: address(REX33), to: address(USDC), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        for (uint256 idx = 0; idx < period; idx++) {
            skip(granuality);
            timeElapsed += granuality;
            //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));
            if (USE_QUOTE) {
                console.log(
                    "Time: %s, Twap1: %s, Spot: %s",
                    timeElapsed / 1 minutes,
                    rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33)),
                    rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
                );
            } else {
                console2.log(
                    "Time: %s, Twap2: %s, Spot: %s",
                    timeElapsed / 1 minutes,
                    rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33)),
                    rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
                );
            }
        }

        // perform a large swap
        deal(address(USDC), manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (reserve0, reserve1,) = REX33_USDC_PAIR.getReserves();
        amountIn = (address(USDC) == REX33_USDC_PAIR.token0() ? reserve0 : reserve1) / 4;
        USDC.approve(ETHEREX_ROUTER, amountIn);

        swapRoute[0] = IRouter.route({from: address(USDC), to: address(REX33), stable: false});
        IRouter(ETHEREX_ROUTER).swapExactTokensForTokens(
            amountIn, 0, swapRoute, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        for (uint256 idx = 0; idx < period; idx++) {
            skip(granuality);
            timeElapsed += granuality;
            //console.log("Price after %s min: %s vs spot: %s", timeElapsed / 1 minutes, oracle.getPrice(), getSpotPrice(_default.pair, _default.token));
            if (USE_QUOTE) {
                console.log(
                    "Time: %s, Twap1: %s, Spot: %s",
                    timeElapsed / 1 minutes,
                    rex33EtherexVolatileTwap.getAssetPriceWithQuote(address(REX33)),
                    rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
                );
            } else {
                console2.log(
                    "Time: %s, Twap2: %s, Spot: %s",
                    timeElapsed / 1 minutes,
                    rex33EtherexVolatileTwap.getAssetPriceWithSampleWindow(address(REX33)),
                    rex33EtherexVolatileTwap.getAssetPrice(address(REX33))
                );
            }
        }

        assert(false);
    }
}
