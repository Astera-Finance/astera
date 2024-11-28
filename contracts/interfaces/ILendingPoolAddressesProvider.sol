// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title LendingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations
 * - Owned by the Cod3x Governance
 * @author Cod3x
 *
 */
interface ILendingPoolAddressesProvider {
    /**
     * @dev Emitted when the market identifier is updated
     * @param newMarketId The new market identifier
     */
    event MarketIdSet(string newMarketId);

    /**
     * @dev Emitted when the lending pool implementation is updated
     * @param newAddress The address of the new LendingPool implementation
     */
    event LendingPoolUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the configuration admin is updated
     * @param newAddress The address of the new configuration admin
     */
    event ConfigurationAdminUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the emergency admin is updated
     * @param newAddress The address of the new emergency admin
     */
    event EmergencyAdminUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the lending pool configurator implementation is updated
     * @param newAddress The address of the new LendingPoolConfigurator implementation
     */
    event LendingPoolConfiguratorUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the price oracle is updated
     * @param newAddress The address of the new PriceOracle
     */
    event PriceOracleUpdated(address indexed newAddress);

    /**
     * @dev Emitted when a new proxy is created
     * @param id The identifier of the proxy
     * @param newAddress The address of the created proxy contract
     */
    event ProxyCreated(bytes32 id, address indexed newAddress);

    /**
     * @dev Emitted when an address is set
     * @param id The identifier of the address
     * @param newAddress The address being set
     * @param hasProxy Whether the address is set in a proxy contract
     */
    event AddressSet(bytes32 id, address indexed newAddress, bool hasProxy);

    // Functions related to getting various addresses
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

    //Functions related to implementaion management
    function setLendingPoolImpl(address pool) external;
    function setLendingPoolConfiguratorImpl(address configurator) external;

    //Functions related to proxies
    function setPoolAdmin(address admin) external;
    function setEmergencyAdmin(address admin) external;
    function setPriceOracle(address priceOracle) external;
    function setMiniPoolAddressesProvider(address provider) external;
    function setFlowLimiter(address flowLimiter) external;
}
