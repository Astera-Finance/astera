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
    event MarketIdSet(string newMarketId);
    event LendingPoolUpdated(address indexed newAddress);
    event ConfigurationAdminUpdated(address indexed newAddress);
    event EmergencyAdminUpdated(address indexed newAddress);
    event LendingPoolConfiguratorUpdated(address indexed newAddress);
    event PriceOracleUpdated(address indexed newAddress);
    event ProxyCreated(bytes32 id, address indexed newAddress);
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
