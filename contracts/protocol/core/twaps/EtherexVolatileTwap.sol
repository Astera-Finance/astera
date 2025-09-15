// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ITwapOracle} from "contracts/interfaces/ITwapOracle.sol";
import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IEtherexPair} from "contracts/interfaces/IEtherexPair.sol";

import "forge-std/console2.sol";

/// @title Oracle using Thena TWAP oracle as data source
/// @author xRave110
/// @notice The oracle contract that provides the current price to purchase
/// the underlying token while exercising options. Uses Thena TWAP oracle
/// as data source, and then applies a lower bound.
contract EtherexVolatileTwap is ITwapOracle, Ownable {
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

    event SetParams(uint128 maxPrice, uint128 minPrice);

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
    uint56 public timeWindow;

    /// @notice The minimum value returned by getPrice(). Maintains a floor for the
    /// price to mitigate potential attacks on the TWAP oracle.
    uint128 public minPrice;
    uint128 public maxPrice;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(IEtherexPair _etherexPair, address _owner, uint56 _timeWindow, uint128 _minPrice)
        Ownable(_owner)
    {
        if (_timeWindow < MIN_SECS) revert ThenaOracle__InvalidWindow();
        timeWindow = _timeWindow;
        etherexPair = _etherexPair;
        minPrice = _minPrice;

        emit SetParams(_timeWindow, _minPrice);
    }

    /// -----------------------------------------------------------------------
    /// IOracle
    /// -----------------------------------------------------------------------

    /// @inheritdoc ITwapOracle
    function getAssetPrice(address _asset) external view override returns (uint256 price) {
        price = etherexPair.current(_asset, 10 ** ERC20(_asset).decimals());

        if (price < minPrice) revert ThenaOracle__BelowMinPrice();
    }

    /* add only assets in the pool ! */
    function getAssetPriceWithQuote(address _asset) external view returns (uint256 price) {
        uint256 granuality = 1;
        uint256 _timeWindow = timeWindow;
        uint256 timeElapsed = 0;
        uint256 length = etherexPair.observationLength();
        for (; timeElapsed < _timeWindow; granuality++) {
            timeElapsed = block.timestamp - etherexPair.observations(length - granuality).timestamp;
            console2.log("Time elapsed: %s vs timeWindow %s", timeElapsed, timeWindow);
        }

        console2.log("Granuality: ", granuality);
        price = etherexPair.quote(_asset, 10 ** ERC20(_asset).decimals(), granuality);

        if (price < minPrice) revert ThenaOracle__BelowMinPrice();
    }

    function getAssetPriceWithSampleWindow(address _asset) external view returns (uint256 price) {
        uint256 granuality = 1;
        uint256 _timeWindow = timeWindow;
        uint256 timeElapsed = 0;
        uint256 length = etherexPair.observationLength();
        for (; timeElapsed < _timeWindow; granuality++) {
            timeElapsed = block.timestamp - etherexPair.observations(length - granuality).timestamp;
            console2.log("Time elapsed: %s vs timeWindow %s", timeElapsed, timeWindow);
        }

        console2.log("Granuality: ", granuality);
        price = etherexPair.sample(_asset, 10 ** ERC20(_asset).decimals(), 1, granuality)[0];

        if (price < minPrice) revert ThenaOracle__BelowMinPrice();
    }

    /// @inheritdoc ITwapOracle
    function getTokens() external view override returns (address token0, address token1) {
        return (etherexPair.token0(), etherexPair.token1());
    }

    /// -----------------------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------------------

    /// @notice Updates the oracle parameters. Only callable by the owner.
    /// @param _maxPrice The maximum value returned by getAssetPrice().
    /// @param _minPrice The minimum value returned by getAssetPrice(). Maintains a floor for the
    /// price to mitigate potential attacks on the TWAP oracle.
    function setMinMaxPrice(uint128 _maxPrice, uint128 _minPrice) external onlyOwner {
        maxPrice = _maxPrice;
        minPrice = _minPrice;
        emit SetParams(_maxPrice, _minPrice);
    }

    function settimeWindow(uint56 _timeWindow) external onlyOwner {
        if (_timeWindow < MIN_SECS) revert ThenaOracle__InvalidWindow();
        timeWindow = _timeWindow;
    }
}
