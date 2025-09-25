// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

// import {ITwapOracle} from "contracts/interfaces/ITwapOracle.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IEtherexPair} from "contracts/interfaces/IEtherexPair.sol";
import {IChainlinkAggregator} from "contracts/interfaces/base/IChainlinkAggregator.sol";

/**
 * @title Oracle using Etherex TWAP oracle as data source
 * @author xRave110
 * @notice The oracle contract that provides the current price to purchase the asset for astera.
 * Uses Etherex TWAP oracle as data source, and then applies a lower bound.
 */
contract EtherexTwap is IChainlinkAggregator, Ownable {
    /* Errors */
    error EtherexTwap__InvalidAddress();
    error EtherexTwap__InvalidWindow();
    error EtherexTwap__BelowMinPrice();
    error EtherexTwap__WrongAsset();
    error EtherexTwap_InvalidParams();
    error EtherexTwap__StablePairsUnsupported();
    error EtherexTwap__ServiceNotAvailable();
    error EtherexTwap_WrongPriceFeedDecimals();
    error EtherexTwap__Overflow();

    /* Events */
    event SetParams(uint128 minPrice);
    event SetTimeWindow(uint256 timeWindow);

    uint256 internal constant MIN_TIME_WINDOW = 20 minutes;
    uint256 internal constant WAD = 1e18;

    /**
     * @notice The Etherex TWAP oracle contract (pair pool with oracle support)
     */
    IEtherexPair public immutable etherexPair;

    /**
     * @notice The size of the window to take the TWAP value over in seconds.
     */
    uint56 public timeWindow;

    /**
     * @notice The minimum value returned by getAssetPrice(). Maintains a floor for the
     * price to mitigate potential attacks on the TWAP oracle.
     */
    uint128 public minPrice;

    /**
     * @notice Token for which the price is given
     */
    address public token;

    /**
     * @notice Whether the price should be returned in terms of token0.
     * If false, the price is returned in terms of token1.
     */
    bool public isToken0;

    IChainlinkAggregator public priceFeed;

    constructor(
        IEtherexPair _etherexPair,
        address _owner,
        uint56 _timeWindow,
        uint128 _minPrice,
        address _priceFeed,
        address _token
    ) Ownable(_owner) {
        /* Checks */
        if (address(_etherexPair) == address(0) || _priceFeed == address(0) || _token == address(0))
        {
            revert EtherexTwap__InvalidAddress();
        }
        if (_timeWindow < MIN_TIME_WINDOW) {
            revert EtherexTwap__InvalidWindow();
        }
        if (_etherexPair.stable()) revert EtherexTwap__StablePairsUnsupported();
        if (
            ERC20(_etherexPair.token0()).decimals() != 18
                || ERC20(_etherexPair.token1()).decimals() != 18
        ) revert EtherexTwap_InvalidParams();

        if (IChainlinkAggregator(_priceFeed).decimals() != 8) {
            revert EtherexTwap_WrongPriceFeedDecimals();
        }
        /* Assignment */
        timeWindow = _timeWindow;
        etherexPair = _etherexPair;
        minPrice = _minPrice;
        isToken0 = _etherexPair.token0() == _token;
        priceFeed = IChainlinkAggregator(_priceFeed);
        token = _token;

        emit SetParams(_minPrice);
        emit SetTimeWindow(_timeWindow);
    }

    /* ---- Inherited --- */

    /**
     * @inheritdoc IChainlinkAggregator
     */
    function latestAnswer() external view returns (int256) {
        uint256 twapPrice = _getTwapPrice();
        int256 answer = priceFeed.latestAnswer();
        answer = int256(uint256(answer) * twapPrice / WAD); // 8 decimals;
        return answer;
    }

    /**
     * @inheritdoc IChainlinkAggregator
     */
    function latestTimestamp() external view returns (uint256) {
        uint256 lastestTimestamp = priceFeed.latestTimestamp();
        return lastestTimestamp;
    }

    /**
     * @inheritdoc IChainlinkAggregator
     */
    function latestRound() external view returns (uint256 roundId) {
        uint256 lastestTimestamp = priceFeed.latestRound();
        return lastestTimestamp;
    }

    /**
     * @inheritdoc IChainlinkAggregator
     */
    function getAnswer(uint256 roundId) external pure returns (int256) {
        revert EtherexTwap__ServiceNotAvailable();
    }

    /**
     * @inheritdoc IChainlinkAggregator
     */
    function getTimestamp(uint256 roundId) external pure returns (uint256) {
        revert EtherexTwap__ServiceNotAvailable();
    }

    /**
     * @inheritdoc IChainlinkAggregator
     */
    function getRoundData(uint80 _roundId)
        external
        pure
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        revert EtherexTwap__ServiceNotAvailable();
    }

    /**
     * @inheritdoc IChainlinkAggregator
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        uint256 twapPrice = _getTwapPrice();
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed.latestRoundData();
        answer = int256(uint256(answer) * twapPrice / WAD); // 8 decimals;
    }

    /**
     * @inheritdoc IChainlinkAggregator
     */
    function decimals() external pure returns (uint8) {
        return 8;
    }

    /* --- Additional getters --- */
    /**
     * @notice Returns the underlying token addresses of the Etherex pair.
     * @dev Fetches token0 and token1 from the EtherexPair contract.
     * @return token0 The address of token0.
     * @return token1 The address of token1.
     */
    function getTokens() external view returns (address token0, address token1) {
        if (isToken0) {
            return (etherexPair.token1(), etherexPair.token0());
        } else {
            return (etherexPair.token0(), etherexPair.token1());
        }
    }

    /**
     * @notice Returns the address of the associated Etherex pair contract.
     * @dev This is the actual pair contract address used for pricing and reserves.
     * @return The address of the EtherexPair contract.
     */
    function getPairAddress() external view returns (address) {
        return address(etherexPair);
    }

    /**
     * @notice Gets the current spot price from the Etherex pair in 8 decimals precision.
     * @dev The price is scaled by the Chainlink price feed and normalized to 8 decimals.
     * @return Spot price as an int256 value (8 decimals).
     */
    function getSpotPrice() external view returns (int256) {
        uint256 spotPrice = _getSpotPrice();
        int256 answer = priceFeed.latestAnswer();
        answer = int256(uint256(answer) * spotPrice / WAD); // 8 decimals;
        return answer;
    }

    /* --- Private --- */

    /**
     * @notice Internal spot price calculation from current reserves.
     * @return price The raw spot price (scaled by WAD).
     */
    function _getSpotPrice() private view returns (uint256 price) {
        (uint112 _reserve0, uint112 _reserve1,) = etherexPair.getReserves();
        if (!isToken0) {
            price = uint256(_reserve0) * WAD / (_reserve1);
        } else {
            price = uint256(_reserve1) * WAD / (_reserve0);
        }
    }

    /**
     * @notice Calculates the Time-Weighted Average Price (TWAP) for the configured time window.
     * @dev Fetches observations, handles edge case if timeElapsed is insufficient,
     *      and calculates the twap price with chain-specific decimals.
     * @return TWAP value as a uint256 (scaled by WAD).
     */
    function _getTwapPrice() private view returns (uint256) {
        IEtherexPair.Observation memory _observation = etherexPair.lastObservation();
        (uint256 reserve0Cumulative, uint256 reserve1Cumulative,) =
            etherexPair.currentCumulativePrices();
        uint256 timeElapsed = block.timestamp - _observation.timestamp;
        if (timeElapsed < timeWindow) {
            _observation = etherexPair.observations(etherexPair.observationLength() - 2);
            timeElapsed = block.timestamp - _observation.timestamp;
        }
        uint112 _reserve0 =
            safe112((reserve0Cumulative - _observation.reserve0Cumulative) / timeElapsed);
        uint112 _reserve1 =
            safe112((reserve1Cumulative - _observation.reserve1Cumulative) / timeElapsed);
        uint256 twapPrice;
        if (!isToken0) {
            twapPrice = uint256(_reserve0) * WAD / (_reserve1);
        } else {
            twapPrice = uint256(_reserve1) * WAD / (_reserve0);
        }
        if (twapPrice < minPrice) revert EtherexTwap__BelowMinPrice();
        return twapPrice;
    }

    /**
     * @notice Updates the oracle parameters. Only callable by the owner.
     * @param _minPrice The minimum value returned by getAssetPrice(). Maintains a floor for the
     * price to mitigate potential attacks on the TWAP oracle.
     */
    function setMinPrice(uint128 _minPrice) external onlyOwner {
        minPrice = _minPrice;
        emit SetParams(_minPrice);
    }

    /**
     * @notice Updates the oracle parameters. Only callable by the owner.
     * @param _timeWindow new time window to set
     */
    function setTimeWindow(uint56 _timeWindow) external onlyOwner {
        if (_timeWindow < MIN_TIME_WINDOW) revert EtherexTwap__InvalidWindow();
        timeWindow = _timeWindow;
        emit SetTimeWindow(timeWindow);
    }

    function safe112(uint256 n) internal pure returns (uint112) {
        if (n >= 2 ** 112) revert EtherexTwap__Overflow();
        return uint112(n);
    }
}
