// // SPDX-License-Identifier: AGPL-3.0
// pragma solidity ^0.8.13;

// import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
// import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";
// import {ITwapOracle} from "contracts/interfaces/ITwapOracle.sol";
// import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
// import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
// // import {TickMath} from "v3-core/libraries/TickMath.sol";
// import {FullMath} from "v3-core/libraries/FullMath.sol";

// /// @title Oracle using Uniswap TWAP oracle as data source
// /// @author zefram.eth & lookeey
// /// @notice The oracle contract that provides the current price to purchase
// /// the underlying token while exercising options. Uses UniswapV3 TWAP oracle
// /// as data source, and then applies a multiplier & lower bound.
// contract EtherexClTwap is ITwapOracle, Ownable {
//     /// -----------------------------------------------------------------------
//     /// Library usage
//     /// -----------------------------------------------------------------------

//     using FixedPointMathLib for uint256;

//     /// -----------------------------------------------------------------------
//     /// Errors
//     /// -----------------------------------------------------------------------

//     error UniswapOracle__InvalidParams();
//     error UniswapOracle__InvalidWindow();
//     error UniswapOracle__BelowMinPrice();

//     /// -----------------------------------------------------------------------
//     /// Events
//     /// -----------------------------------------------------------------------

//     event SetParams(uint56 secs, uint56 ago, uint128 minPrice);

//     /// -----------------------------------------------------------------------
//     /// Immutable parameters
//     /// -----------------------------------------------------------------------

//     uint256 internal constant MIN_SECS = 20 minutes;

//     /// @notice The UniswapV3 Pool contract (provides the oracle)
//     IUniswapV3Pool public immutable uniswapPool;

//     /// -----------------------------------------------------------------------
//     /// Storage variables
//     /// -----------------------------------------------------------------------

//     /// @notice The size of the window to take the TWAP value over in seconds.
//     uint32 public secs;

//     /// @notice The number of seconds in the past to take the TWAP from. The window
//     /// would be (block.timestamp - secs - ago, block.timestamp - ago].
//     uint32 public ago;

//     /// @notice The minimum value returned by getPrice(). Maintains a floor for the
//     /// price to mitigate potential attacks on the TWAP oracle.
//     uint128 public minPrice;

//     /// @notice Whether the price of token0 should be returned (in units of token1).
//     /// If false, the price is returned in units of token0.
//     bool public isToken0;

//     /// -----------------------------------------------------------------------
//     /// Constructor
//     /// -----------------------------------------------------------------------

//     constructor(
//         IUniswapV3Pool uniswapPool_,
//         address token,
//         address owner_,
//         uint32 secs_,
//         uint32 ago_,
//         uint128 minPrice_
//     ) Ownable(owner_) {
//         if (
//             ERC20(uniswapPool_.token0()).decimals() != 18
//                 || ERC20(uniswapPool_.token1()).decimals() != 18
//         ) revert UniswapOracle__InvalidParams(); //|| ERC20(uniswapPool_.token1()).decimals() != 18
//         if (uniswapPool_.token0() != token && uniswapPool_.token1() != token) {
//             revert UniswapOracle__InvalidParams();
//         }
//         if (secs_ < MIN_SECS) revert UniswapOracle__InvalidWindow();
//         uniswapPool = uniswapPool_;
//         isToken0 = token == uniswapPool_.token0();
//         secs = secs_;
//         ago = ago_;
//         minPrice = minPrice_;

//         emit SetParams(secs_, ago_, minPrice_);
//     }

//     /// -----------------------------------------------------------------------
//     /// IOracle
//     /// -----------------------------------------------------------------------

//     /// @inheritdoc ITwapOracle
//     function getAssetPrice(address _asset) external view override returns (uint256 price) {
//         /// -----------------------------------------------------------------------
//         /// Validation
//         /// -----------------------------------------------------------------------

//         // The UniswapV3 pool reverts on invalid TWAP queries, so we don't need to

//         /// -----------------------------------------------------------------------
//         /// Computation
//         /// -----------------------------------------------------------------------

//         // query Uniswap oracle to get TWAP tick
//         {
//             uint32 _twapDuration = secs;
//             uint32 _twapAgo = ago;
//             uint32[] memory secondsAgo = new uint32[](2);
//             secondsAgo[0] = _twapDuration + _twapAgo;
//             secondsAgo[1] = _twapAgo;

//             (int56[] memory tickCumulatives,) = uniswapPool.observe(secondsAgo);
//             int24 tick =
//                 int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(_twapDuration)));

//             uint256 decimalPrecision = 1e18;

//             // from https://optimistic.etherscan.io/address/0xB210CE856631EeEB767eFa666EC7C1C57738d438#code#F5#L49
//             uint160 sqrtRatioX96 = getSqrtRatioAtTick(tick);

//             // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
//             if (sqrtRatioX96 <= type(uint128).max) {
//                 uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
//                 price = isToken0
//                     ? FullMath.mulDiv(ratioX192, decimalPrecision, 1 << 192)
//                     : FullMath.mulDiv(1 << 192, decimalPrecision, ratioX192);
//             } else {
//                 uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
//                 price = isToken0
//                     ? FullMath.mulDiv(ratioX128, decimalPrecision, 1 << 128)
//                     : FullMath.mulDiv(1 << 128, decimalPrecision, ratioX128);
//             }
//         }

//         // apply minimum price
//         if (price < minPrice) revert UniswapOracle__BelowMinPrice();
//     }

//     /// @inheritdoc ITwapOracle
//     function getTokens()
//         external
//         view
//         override
//         returns (address paymentToken, address underlyingToken)
//     {
//         if (isToken0) {
//             return (uniswapPool.token1(), uniswapPool.token0());
//         } else {
//             return (uniswapPool.token0(), uniswapPool.token1());
//         }
//     }

//     /// -----------------------------------------------------------------------
//     /// Owner functions
//     /// -----------------------------------------------------------------------

//     /// @notice Updates the oracle parameters. Only callable by the owner.
//     /// @param secs_ The size of the window to take the TWAP value over in seconds.
//     /// @param ago_ The number of seconds in the past to take the TWAP from. The window
//     /// would be (block.timestamp - secs - ago, block.timestamp - ago].
//     /// @param minPrice_ The minimum value returned by getPrice(). Maintains a floor for the
//     /// price to mitigate potential attacks on the TWAP oracle.
//     function setParams(uint32 secs_, uint32 ago_, uint128 minPrice_) external onlyOwner {
//         if (secs_ < MIN_SECS) revert UniswapOracle__InvalidWindow();
//         secs = secs_;
//         ago = ago_;
//         minPrice = minPrice_;
//         emit SetParams(secs_, ago_, minPrice_);
//     }

//     function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
//         uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
//         require(absTick <= uint256(887272), "T");

//         uint256 ratio = absTick & 0x1 != 0
//             ? 0xfffcb933bd6fad37aa2d162d1a594001
//             : 0x100000000000000000000000000000000;
//         if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
//         if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
//         if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
//         if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
//         if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
//         if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
//         if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
//         if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
//         if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
//         if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
//         if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
//         if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
//         if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
//         if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
//         if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
//         if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
//         if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
//         if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
//         if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

//         if (tick > 0) ratio = type(uint256).max / ratio;

//         // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
//         // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
//         // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
//         sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
//     }
// }
