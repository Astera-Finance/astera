// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {Ownable} from "../../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {IERC20} from "../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IOracle} from "../../../contracts/interfaces/IOracle.sol";
import {IChainlinkAggregator} from "../../../contracts/interfaces/base/IChainlinkAggregator.sol";
import {SafeERC20} from "../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {ATokenNonRebasing} from
    "../../../contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";
import {Errors} from "../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title Oracle
 * @author Cod3x
 * @notice Proxy smart contract to get the price of an asset from a price source, with Chainlink Aggregator
 * smart contracts as primary option.
 * @dev The contract has the following features:
 * - Abstract aToken price to underlying asset price adjusted to the asset/share conversion ratio.
 * - If the returned price by a Chainlink aggregator is <= 0, the call is forwarded to a `fallbackOracle`.
 * - Owned by the Cod3x Governance system, allowed to add sources for assets, replace them
 *   and change the `fallbackOracle`.
 */
contract Oracle is IOracle, Ownable {
    using SafeERC20 for IERC20;

    /// @dev Mapping of asset addresses to their corresponding Chainlink aggregator contracts.
    mapping(address => IChainlinkAggregator) private _assetsSources;

    /// @dev Mapping of asset addresses to their corresponding Chainlink timeout values.
    mapping(address => uint256) private _assetToTimeout;

    /// @dev The fallback oracle used when Chainlink data is invalid.
    IOracle private _fallbackOracle;

    /// @dev The base currency address used for price quotes.
    address public immutable BASE_CURRENCY;

    /**
     * @notice If `USD` returns `0x0`, if `ETH` returns `WETH` address.
     * @dev The unit of the base currency used for price normalization.
     */
    uint256 public immutable BASE_CURRENCY_UNIT;

    /**
     * @notice Initializes the Oracle contract.
     * @param assets The addresses of the assets.
     * @param sources The address of the source of each asset.
     * @param timeouts The timeout values for each Chainlink price feed.
     * @param fallbackOracle The address of the fallback oracle to use if the data of an
     * aggregator is not consistent.
     * @param baseCurrency The base currency used for the price quotes. If USD is used, base currency is 0x0.
     * @param baseCurrencyUnit The unit of the base currency.
     */
    constructor(
        address[] memory assets,
        address[] memory sources,
        uint256[] memory timeouts,
        address fallbackOracle,
        address baseCurrency,
        uint256 baseCurrencyUnit
    ) Ownable(msg.sender) {
        _setFallbackOracle(fallbackOracle);
        _setAssetsSources(assets, sources, timeouts);
        BASE_CURRENCY = baseCurrency;
        BASE_CURRENCY_UNIT = baseCurrencyUnit;
        emit BaseCurrencySet(baseCurrency, baseCurrencyUnit);
    }

    /**
     * @notice External function called by the Cod3x Governance to set or replace sources of assets.
     * @param assets The addresses of the assets.
     * @param sources The address of the source of each asset.
     * @param timeouts The chainlink timeout of each asset.
     */
    function setAssetSources(
        address[] calldata assets,
        address[] calldata sources,
        uint256[] calldata timeouts
    ) external onlyOwner {
        _setAssetsSources(assets, sources, timeouts);
    }

    /**
     * @notice Sets the fallback oracle.
     * @dev Only callable by the Cod3x Governance.
     * @param fallbackOracle The address of the fallback oracle.
     */
    function setFallbackOracle(address fallbackOracle) external onlyOwner {
        _setFallbackOracle(fallbackOracle);
    }

    /**
     * @notice Internal function to set the sources for each asset.
     * @param assets The addresses of the assets.
     * @param sources The address of the source of each asset.
     * @param timeouts The chainlink timeout of each asset.
     */
    function _setAssetsSources(
        address[] memory assets,
        address[] memory sources,
        uint256[] memory timeouts
    ) internal {
        require(assets.length == sources.length, Errors.O_INCONSISTENT_PARAMS_LENGTH);
        for (uint256 i = 0; i < assets.length; i++) {
            _assetsSources[assets[i]] = IChainlinkAggregator(sources[i]);
            _assetToTimeout[assets[i]] = timeouts[i] == 0 ? type(uint256).max : timeouts[i];
            emit AssetSourceUpdated(assets[i], sources[i]);
        }
    }

    /**
     * @notice Internal function to set the fallback oracle.
     * @param fallbackOracle The address of the fallback oracle.
     */
    function _setFallbackOracle(address fallbackOracle) internal {
        _fallbackOracle = IOracle(fallbackOracle);
        emit FallbackOracleUpdated(fallbackOracle);
    }

    /**
     * @notice Gets an asset price by address.
     * @dev If the asset is an aToken, it will get the price of the underlying asset and convert it to shares.
     * @param asset The asset address.
     * @return The price of the asset.
     */
    function getAssetPrice(address asset) public view override returns (uint256) {
        address underlying;

        // Check if `asset` is an aToken.
        try ATokenNonRebasing(asset).UNDERLYING_ASSET_ADDRESS{gas: 4000}() returns (
            address underlying_
        ) {
            underlying = underlying_;
        } catch {
            underlying = asset;
        }

        IChainlinkAggregator source = _assetsSources[underlying];
        uint256 finalPrice;

        if (underlying == BASE_CURRENCY) {
            finalPrice = BASE_CURRENCY_UNIT;
        } else if (address(source) == address(0)) {
            finalPrice = _fallbackOracle.getAssetPrice(underlying);
        } else {
            (uint80 roundId, int256 price, uint256 startedAt, uint256 timestamp,) =
                IChainlinkAggregator(source).latestRoundData();

            // Chainlink integrity checks.
            if (
                roundId == 0 || timestamp == 0 || timestamp > block.timestamp || price <= 0
                    || startedAt == 0 || block.timestamp - timestamp > _assetToTimeout[asset]
            ) {
                require(address(_fallbackOracle) != address(0), Errors.O_PRICE_FEED_INCONSISTENCY);
                finalPrice = _fallbackOracle.getAssetPrice(underlying);
            } else {
                finalPrice = uint256(price);
            }
        }

        // If `asset` is an aToken then convert the price from asset to share.
        if (asset != underlying) {
            return ATokenNonRebasing(asset).convertToAssets(finalPrice);
        } else {
            return finalPrice;
        }
    }

    /**
     * @notice Gets a list of prices from a list of assets addresses.
     * @param assets The list of assets addresses.
     * @return An array containing the prices of the given assets.
     */
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = getAssetPrice(assets[i]);
        }
        return prices;
    }

    /**
     * @notice Gets the address of the source for an asset address.
     * @param asset The address of the asset.
     * @return address The address of the source.
     */
    function getSourceOfAsset(address asset) external view returns (address) {
        return address(_assetsSources[asset]);
    }

    /**
     * @notice Gets the address of the fallback oracle.
     * @return address The address of the fallback oracle.
     */
    function getFallbackOracle() external view returns (address) {
        return address(_fallbackOracle);
    }
}
