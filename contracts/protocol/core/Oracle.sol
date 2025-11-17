// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {Ownable} from "../../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {IERC20} from "../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IOracle} from "../../../contracts/interfaces/IOracle.sol";
import {IChainlinkAggregator} from "../../../contracts/interfaces/base/IChainlinkAggregator.sol";
import {SafeERC20} from "../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {ATokenNonRebasing} from
    "../../../contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";
import {Errors} from "../../../contracts/protocol/libraries/helpers/Errors.sol";
import {ILendingPoolConfigurator} from "../../../contracts/interfaces/ILendingPoolConfigurator.sol";
import {ILendingPoolAddressesProvider} from
    "../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";

/**
 * @title Oracle
 * @author Conclave
 * @notice Proxy smart contract to get the price of an asset from a price source, with Chainlink Aggregator
 * smart contracts as primary option.
 * @dev The contract has the following features:
 * - Abstract aToken price to underlying asset price adjusted to the asset/share conversion ratio.
 * - If the returned price by a Chainlink aggregator is <= 0, the call is forwarded to a `fallbackOracle`.
 * - Owned by the Astera Governance system, allowed to add sources for assets, replace them
 *   and change the `fallbackOracle`.
 * @dev ATTENTION: All aggregators (main and fallback) are expected to return prices in BASE_CURRENCY with the
 * same BASE_CURRENCY_UNIT unit.
 */
contract Oracle is IOracle, Ownable {
    using SafeERC20 for IERC20;

    /// @dev Mapping of asset addresses to their corresponding Chainlink aggregator contracts.
    mapping(address => IChainlinkAggregator) private _assetsSources;

    /// @dev Mapping of asset addresses to their corresponding Chainlink timeout values.
    mapping(address => uint256) private _assetToTimeout;

    /// @dev The fallback oracle used when Chainlink data is invalid.
    IOracle private _fallbackOracle;

    ILendingPoolConfigurator private _lendingpoolConfigurator;

    ILendingPoolAddressesProvider private _lendingpoolAddressesProvider;

    /**
     * @dev The base currency address used for price quotes.
     * @notice If `USD` returns `0x0`, if `ETH` returns `WETH` address.
     */
    address public immutable BASE_CURRENCY;

    /// @dev The unit of the base currency used for price normalization. MUST BE USD IF USING asUSD.
    uint256 public immutable BASE_CURRENCY_UNIT;

    /// @dev The address of the asUSD token.
    address public constant AS_USD = address(0xa500000000e482752f032eA387390b6025a2377b);

    /**
     * @notice Initializes the Oracle contract.
     * @param assets The addresses of the assets.
     * @param sources The address of the source of each asset.
     * @param timeouts The timeout values for each Chainlink price feed.
     * @param fallbackOracle The address of the fallback oracle to use if the data of an
     * aggregator is not consistent.
     * @param baseCurrency The base currency used for the price quotes. If USD is used, base currency is 0x0.
     * @param baseCurrencyUnit The unit of the base currency.
     * @param lendingpoolAddressesProvider The address of the lending pool addresses provider.
     */
    constructor(
        address[] memory assets,
        address[] memory sources,
        uint256[] memory timeouts,
        address fallbackOracle,
        address baseCurrency,
        uint256 baseCurrencyUnit,
        address lendingpoolAddressesProvider
    ) Ownable(msg.sender) {
        _setFallbackOracle(fallbackOracle);
        _setAssetsSources(assets, sources, timeouts);
        BASE_CURRENCY = baseCurrency;
        BASE_CURRENCY_UNIT = baseCurrencyUnit;
        _lendingpoolAddressesProvider = ILendingPoolAddressesProvider(lendingpoolAddressesProvider);
        _lendingpoolConfigurator =
            ILendingPoolConfigurator(_lendingpoolAddressesProvider.getLendingPoolConfigurator());

        emit BaseCurrencySet(baseCurrency, baseCurrencyUnit);
    }

    /**
     * @notice External function called by the Astera Governance to set or replace sources of assets.
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
     * @dev Only callable by the Astera Governance.
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
        uint256 assetsLength = assets.length;
        require(assetsLength == sources.length, Errors.O_INCONSISTENT_PARAMS_LENGTH);
        require(assetsLength == timeouts.length, Errors.O_INCONSISTENT_PARAMS_LENGTH);
        for (uint256 i = 0; i < assetsLength; i++) {
            address asset = assets[i];
            address source = sources[i];
            uint256 timeout = timeouts[i];
            _assetsSources[asset] = IChainlinkAggregator(source);
            _assetToTimeout[asset] = timeout == 0 ? type(uint256).max : timeout;
            emit AssetSourceUpdated(asset, source, timeout);
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
        if (_lendingpoolConfigurator.getIsAToken(asset)) {
            underlying = ATokenNonRebasing(asset).UNDERLYING_ASSET_ADDRESS();
        } else {
            underlying = asset;
        }

        IChainlinkAggregator source = _assetsSources[underlying];
        uint256 finalPrice;

        // If the asset is the base currency or asUSD and the caller is the lending pool, return the unit
        // of the base currency.
        // Since the lending pool is used as a primary market for asUSD, this allows the lending pool to get the price
        // of asUSD at 1$ but minipools and other contracts to still get the price of asUSD from the aggregator.
        if (
            underlying == BASE_CURRENCY
                || (asset == AS_USD && msg.sender == _lendingpoolAddressesProvider.getLendingPool())
        ) {
            finalPrice = BASE_CURRENCY_UNIT;
        } else if (address(source) == address(0)) {
            finalPrice = _fallbackOracle.getAssetPrice(underlying);
        } else {
            (uint80 roundId, int256 price, uint256 startedAt, uint256 timestamp,) =
                IChainlinkAggregator(source).latestRoundData();

            // Chainlink integrity checks.
            if (
                roundId == 0 || timestamp == 0 || timestamp > block.timestamp || price <= 0
                    || startedAt == 0 || block.timestamp - timestamp > _assetToTimeout[underlying]
            ) {
                require(address(_fallbackOracle) != address(0), Errors.O_PRICE_FEED_INCONSISTENCY);
                finalPrice = _fallbackOracle.getAssetPrice(underlying);
            } else {
                finalPrice = uint256(price);
            }
        }

        // If "asset" is an aToken then convert the price from share to asset.
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
     * @notice Gets the timeout for an asset.
     * @param asset The address of the asset.
     * @return uint256 The timeout for the asset.
     */
    function getAssetTimeout(address asset) external view returns (uint256) {
        return _assetToTimeout[asset];
    }

    /**
     * @notice Gets the address of the fallback oracle.
     * @return address The address of the fallback oracle.
     */
    function getFallbackOracle() external view returns (address) {
        return address(_fallbackOracle);
    }

    /**
     * @notice Gets the address of the lending pool configurator.
     * @return address The address of the lending pool configurator.
     */
    function getLendingpoolConfigurator() external view returns (address) {
        return address(_lendingpoolConfigurator);
    }
}
