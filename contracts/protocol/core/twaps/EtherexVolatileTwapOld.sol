// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ITwapOracle} from "contracts/interfaces/ITwapOracle.sol";
import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IEtherexPair} from "contracts/interfaces/IEtherexPair.sol";

/// @title Oracle using Thena TWAP oracle as data source
/// @author zefram.eth/lookee/Eidolon
/// @notice The oracle contract that provides the current price to purchase
/// the underlying token while exercising options. Uses Thena TWAP oracle
/// as data source, and then applies a lower bound.
contract EtherexVolatileTwapOld is ITwapOracle, Ownable {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error ThenaOracle__InvalidParams();
    error ThenaOracle__InvalidWindow();
    error ThenaOracle__StablePairsUnsupported();
    error ThenaOracle__Overflow();
    error ThenaOracle__BelowMinPrice();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event SetParams(uint56 secs, uint128 minPrice);

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MIN_SECS = 20 minutes;

    /// @notice The Thena TWAP oracle contract (usually a pool with oracle support)
    IEtherexPair public immutable etherexPair;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice The size of the window to take the TWAP value over in seconds.
    uint56 public secs;

    /// @notice The minimum value returned by getPrice(). Maintains a floor for the
    /// price to mitigate potential attacks on the TWAP oracle.
    uint128 public minPrice;

    /// @notice Whether the price should be returned in terms of token0.
    /// If false, the price is returned in terms of token1.
    bool public isToken0;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        IEtherexPair etherexPair_,
        address token,
        address owner_,
        uint56 secs_,
        uint128 minPrice_
    ) Ownable(owner_) {
        if (
            ERC20(etherexPair_.token0()).decimals() != 18
                || ERC20(etherexPair_.token1()).decimals() != 18
        ) revert ThenaOracle__InvalidParams();
        if (etherexPair_.stable()) revert ThenaOracle__StablePairsUnsupported();
        if (etherexPair_.token0() != token && etherexPair_.token1() != token) {
            revert ThenaOracle__InvalidParams();
        }
        if (secs_ < MIN_SECS) revert ThenaOracle__InvalidWindow();

        etherexPair = etherexPair_;
        isToken0 = etherexPair_.token0() == token;
        secs = secs_;
        minPrice = minPrice_;

        emit SetParams(secs_, minPrice_);
    }

    /// -----------------------------------------------------------------------
    /// IOracle
    /// -----------------------------------------------------------------------

    /// @inheritdoc ITwapOracle
    function getAssetPrice(address _asset) external view override returns (uint256 price) {
        if (
            (isToken0 && _asset != etherexPair.token0())
                && (!isToken0 && _asset != etherexPair.token1())
        ) {
            revert ThenaOracle__InvalidParams();
        }
        /// -----------------------------------------------------------------------
        /// Storage loads
        /// -----------------------------------------------------------------------

        uint256 secs_ = secs;

        /// -----------------------------------------------------------------------
        /// Computation
        /// -----------------------------------------------------------------------

        // query Thena oracle to get TWAP value
        {
            (
                uint256 reserve0CumulativeCurrent,
                uint256 reserve1CumulativeCurrent,
                uint256 blockTimestampCurrent
            ) = etherexPair.currentCumulativePrices();
            uint256 observationLength = etherexPair.observationLength();
            IEtherexPair.Observation memory lastObs = etherexPair.lastObservation();

            uint32 T = uint32(blockTimestampCurrent - lastObs.timestamp);
            if (T < secs_) {
                lastObs = etherexPair.observations(observationLength - 2);
                T = uint32(blockTimestampCurrent - lastObs.timestamp);
            }
            uint112 reserve0 = safe112((reserve0CumulativeCurrent - lastObs.reserve0Cumulative) / T);
            uint112 reserve1 = safe112((reserve1CumulativeCurrent - lastObs.reserve1Cumulative) / T);

            if (!isToken0) {
                price = uint256(reserve0) * WAD / (reserve1);
            } else {
                price = uint256(reserve1) * WAD / (reserve0);
            }
        }

        if (price < minPrice) revert ThenaOracle__BelowMinPrice();
    }

    /// @inheritdoc ITwapOracle
    function getTokens()
        external
        view
        override
        returns (address paymentToken, address underlyingToken)
    {
        if (isToken0) {
            return (etherexPair.token1(), etherexPair.token0());
        } else {
            return (etherexPair.token0(), etherexPair.token1());
        }
    }

    /// -----------------------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------------------

    /// @notice Updates the oracle parameters. Only callable by the owner.
    /// @param secs_ The size of the window to take the TWAP value over in seconds.
    /// @param minPrice_ The minimum value returned by getPrice(). Maintains a floor for the
    /// price to mitigate potential attacks on the TWAP oracle.
    function setParams(uint56 secs_, uint128 minPrice_) external onlyOwner {
        if (secs_ < MIN_SECS) revert ThenaOracle__InvalidWindow();
        secs = secs_;
        minPrice = minPrice_;
        emit SetParams(secs_, minPrice_);
    }

    /// -----------------------------------------------------------------------
    /// Util functions
    /// -----------------------------------------------------------------------

    function safe112(uint256 n) internal pure returns (uint112) {
        if (n >= 2 ** 112) revert ThenaOracle__Overflow();
        return uint112(n);
    }
}
