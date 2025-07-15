// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title IOracle interface.
 * @author Conclave
 */
interface IOracle {
    // Events
    /**
     * @dev Emitted when the base currency is set
     * @param baseCurrency The address of the base currency
     * @param baseCurrencyUnit The unit of the base currency
     */
    event BaseCurrencySet(address indexed baseCurrency, uint256 baseCurrencyUnit);

    /**
     * @dev Emitted when an asset source is updated
     * @param asset The address of the asset
     * @param source The address of the price source
     */
    event AssetSourceUpdated(address indexed asset, address indexed source, uint256 timeout);

    /**
     * @dev Emitted when the fallback oracle is updated
     * @param fallbackOracle The address of the new fallback oracle
     */
    event FallbackOracleUpdated(address indexed fallbackOracle);

    // Setters
    function setAssetSources(
        address[] calldata assets,
        address[] calldata sources,
        uint256[] calldata timeouts
    ) external;

    function setFallbackOracle(address fallbackOracle) external;

    // Getters
    function getAssetPrice(address asset) external view returns (uint256);

    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);

    function getSourceOfAsset(address asset) external view returns (address);

    function getAssetTimeout(address asset) external view returns (uint256);

    function getFallbackOracle() external view returns (address);

    function getLendingpoolConfigurator() external view returns (address);

    function BASE_CURRENCY() external view returns (address);

    function BASE_CURRENCY_UNIT() external view returns (uint256);
}
