// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title LendingPoolAddressesProvider interface.
 * @author Conclave
 */
interface ILendingPoolAddressesProvider {
    /**
     * @dev Emitted when the market identifier is updated.
     * @param newMarketId The new market identifier for the protocol.
     */
    event MarketIdSet(string newMarketId);

    /**
     * @dev Emitted when the lending pool implementation is updated.
     * @param newAddress The address of the new `LendingPool` implementation contract.
     */
    event LendingPoolUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the configuration admin is updated.
     * @param newAddress The address of the new configuration admin that can modify pool parameters.
     */
    event ConfigurationAdminUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the emergency admin is updated.
     * @param newAddress The address of the new emergency admin that can pause protocol functions.
     */
    event EmergencyAdminUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the lending pool configurator implementation is updated.
     * @param newAddress The address of the new `LendingPoolConfigurator` implementation contract.
     */
    event LendingPoolConfiguratorUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the price oracle is updated.
     * @param newAddress The address of the new `PriceOracle` contract used for asset price feeds.
     */
    event PriceOracleUpdated(address indexed newAddress);

    /**
     * @dev Emitted when a new proxy contract is created.
     * @param id The identifier `bytes32` of the proxy being created.
     * @param newAddress The address of the newly created proxy contract.
     */
    event ProxyCreated(bytes32 indexed id, address indexed newAddress);

    /**
     * @dev Emitted when an address mapping is set in the provider.
     * @param id The identifier `bytes32` for the address being set.
     * @param newAddress The new address being mapped to the identifier.
     * @param hasProxy Boolean indicating if the address is set behind a proxy contract.
     */
    event AddressSet(bytes32 id, address indexed newAddress, bool hasProxy);

    /**
     * @dev Emitted when the MiniPool addresses provider is updated.
     * @param newAddress The new MiniPool addresses provider address.
     */
    event MiniPoolAddressesProviderUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the flow limiter is updated.
     * @param newAddress The new flow limiter address.
     */
    event FlowLimiterUpdated(address indexed newAddress);

    function getMiniPoolAddressesProvider() external view returns (address);

    function getLendingPool() external view returns (address);

    function getLendingPoolConfigurator() external view returns (address);

    function getPoolAdmin() external view returns (address);

    function getEmergencyAdmin() external view returns (address);

    function getPriceOracle() external view returns (address);

    function getFlowLimiter() external view returns (address);

    function getAddress(bytes32 id) external view returns (address);

    function setAddress(bytes32 id, address newAddress) external;

    function setAddressAsProxy(bytes32 id, address impl) external;

    function setLendingPoolImpl(address pool) external;

    function setLendingPoolConfiguratorImpl(address configurator) external;

    function setPoolAdmin(address admin) external;

    function setEmergencyAdmin(address admin) external;

    function setPriceOracle(address priceOracle) external;

    function setMiniPoolAddressesProvider(address provider) external;

    function setFlowLimiter(address flowLimiter) external;
}
