// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {Ownable} from "contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {IERC20} from "contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IPriceOracleGetter} from "contracts/interfaces/IPriceOracleGetter.sol";
import {IChainlinkAggregator} from "contracts/interfaces/IChainlinkAggregator.sol";
import {SafeERC20} from "contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";
import {ATokenNonRebasing} from "contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";

/// @title Oracle
/// @author Cod3x
/// @notice Proxy smart contract to get the price of an asset from a price source, with Chainlink Aggregator
///         smart contracts as primary option
/// - If the returned price by a Chainlink aggregator is <= 0, the call is forwarded to a fallbackOracle
/// - Owned by the Aave governance system, allowed to add sources for assets, replace them
///   and change the fallbackOracle
contract Oracle is IPriceOracleGetter, Ownable {
    using SafeERC20 for IERC20;

    event BaseCurrencySet(address indexed baseCurrency, uint256 baseCurrencyUnit);
    event AssetSourceUpdated(address indexed asset, address indexed source);
    event FallbackOracleUpdated(address indexed fallbackOracle);

    mapping(address => IChainlinkAggregator) private assetsSources;
    IPriceOracleGetter private _fallbackOracle;
    address public immutable BASE_CURRENCY;
    uint256 public immutable BASE_CURRENCY_UNIT;

    /// @notice Constructor
    /// @param assets The addresses of the assets
    /// @param sources The address of the source of each asset
    /// @param fallbackOracle The address of the fallback oracle to use if the data of an
    ///        aggregator is not consistent
    /// @param baseCurrency the base currency used for the price quotes. If USD is used, base currency is 0x0
    /// @param baseCurrencyUnit the unit of the base currency
    constructor(
        address[] memory assets,
        address[] memory sources,
        address fallbackOracle,
        address baseCurrency,
        uint256 baseCurrencyUnit
    ) Ownable(msg.sender) {
        _setFallbackOracle(fallbackOracle);
        _setAssetsSources(assets, sources);
        BASE_CURRENCY = baseCurrency;
        BASE_CURRENCY_UNIT = baseCurrencyUnit;
        emit BaseCurrencySet(baseCurrency, baseCurrencyUnit);
    }

    /// @notice External function called by the Aave governance to set or replace sources of assets
    /// @param assets The addresses of the assets
    /// @param sources The address of the source of each asset
    function setAssetSources(address[] calldata assets, address[] calldata sources)
        external
        onlyOwner
    {
        _setAssetsSources(assets, sources);
    }

    /// @notice Sets the fallbackOracle
    /// - Callable only by the Aave governance
    /// @param fallbackOracle The address of the fallbackOracle
    function setFallbackOracle(address fallbackOracle) external onlyOwner {
        _setFallbackOracle(fallbackOracle);
    }

    /// @notice Internal function to set the sources for each asset
    /// @param assets The addresses of the assets
    /// @param sources The address of the source of each asset
    function _setAssetsSources(address[] memory assets, address[] memory sources) internal {
        require(assets.length == sources.length, "INCONSISTENT_PARAMS_LENGTH");
        for (uint256 i = 0; i < assets.length; i++) {
            assetsSources[assets[i]] = IChainlinkAggregator(sources[i]);
            emit AssetSourceUpdated(assets[i], sources[i]);
        }
    }

    /// @notice Internal function to set the fallbackOracle
    /// @param fallbackOracle The address of the fallbackOracle
    function _setFallbackOracle(address fallbackOracle) internal {
        _fallbackOracle = IPriceOracleGetter(fallbackOracle);
        emit FallbackOracleUpdated(fallbackOracle);
    }

    /// @notice Gets an asset price by address
    /// @param asset The asset address
    function getAssetPrice(address asset) public view override returns (uint256) {
        address underlying;

        // Check if `asset`is an aToken.
        try ATokenNonRebasing(asset).UNDERLYING_ASSET_ADDRESS{gas: 4000}() returns (
            address underlying_
        ) {
            underlying = underlying_;
        } catch {
            underlying = asset;
        }

        IChainlinkAggregator source = assetsSources[underlying];
        uint256 finalPrice;

        if (underlying == BASE_CURRENCY) {
            finalPrice = BASE_CURRENCY_UNIT;
        } else if (address(source) == address(0)) {
            finalPrice = _fallbackOracle.getAssetPrice(underlying);
        } else {
            int256 price = IChainlinkAggregator(source).latestAnswer();
            if (price > 0) {
                finalPrice = uint256(price);
            } else {
                finalPrice = _fallbackOracle.getAssetPrice(underlying);
            }
        }

        // if `asset` is an aToken then convert the price from asset to share.
        if (asset != underlying) {
            return ATokenNonRebasing(asset).convertToShares(finalPrice);
        } else {
            return finalPrice;
        }
    }

    /// @notice Gets a list of prices from a list of assets addresses
    /// @param assets The list of assets addresses
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = getAssetPrice(assets[i]);
        }
        return prices;
    }

    /// @notice Gets the address of the source for an asset address
    /// @param asset The address of the asset
    /// @return address The address of the source
    function getSourceOfAsset(address asset) external view returns (address) {
        return address(assetsSources[asset]);
    }

    /// @notice Gets the address of the fallback oracle
    /// @return address The addres of the fallback oracle
    function getFallbackOracle() external view returns (address) {
        return address(_fallbackOracle);
    }
}
