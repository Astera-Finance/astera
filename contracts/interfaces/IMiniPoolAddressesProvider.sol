// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title IMiniPoolAddressesProvider interface.
 * @author Cod3x
 */
interface IMiniPoolAddressesProvider {
    /**
     * @dev Emitted when the mini pool implementation is updated.
     * @param newAddress The address of the new MiniPool implementation.
     */
    event MiniPoolUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the aToken implementation is updated.
     * @param newAddress The address of the new aToken implementation.
     */
    event ATokenUpdated(address indexed newAddress);

    /**
     * @dev Emitted when a flow limit is updated.
     * @param limit The new flow limit value.
     */
    event FlowLimitUpdated(uint256 indexed limit);

    /**
     * @dev Emitted when a new mini pool proxy is created.
     * @param poolId The ID of the mini pool.
     * @param newAddress The address of the created proxy contract.
     */
    event ProxyCreated(uint256 poolId, address indexed newAddress);

    /**
     * @dev Emitted when a new proxy is created.
     * @param id The identifier of the proxy.
     * @param newAddress The address of the created proxy contract.
     */
    event ProxyCreated(bytes32 id, address indexed newAddress);

    /**
     * @dev Emitted when an address is set.
     * @param id The identifier of the address.
     * @param newAddress The address being set.
     * @param hasProxy Whether the address is set in a proxy contract.
     */
    event AddressSet(bytes32 id, address indexed newAddress, bool hasProxy);

    /**
     * @dev Emitted when the mini pool configurator implementation is updated.
     * @param newAddress The address of the new MiniPoolConfigurator implementation.
     */
    event MiniPoolConfiguratorUpdated(address indexed newAddress);

    /**
     * @dev Emitted when a pool admin is set.
     * @param newAdmin The address of the new pool admin.
     */
    event PoolAdminSet(address newAdmin);

    /**
     * @dev Emitted when a Cod3x treasury is set for all mini pools.
     * @param treasury The address of the Cod3x treasury.
     */
    event Cod3xTreasurySet(address indexed treasury);

    /**
     * @dev Emitted when a mini pool owner treasury is set.
     * @param treasury The address of the mini pool owner treasury.
     * @param miniPoolId The ID of the mini pool.
     */
    event MinipoolOwnerTreasurySet(address indexed treasury, uint256 miniPoolId);

    // Functions related to getting various addresses
    function getMiniPoolCount() external view returns (uint256);

    function getLendingPoolAddressesProvider() external view returns (address);

    function getLendingPool() external view returns (address);

    function getPoolAdmin(uint256 id) external view returns (address);

    function getMainPoolAdmin() external view returns (address);

    function getEmergencyAdmin() external view returns (address);

    function getPriceOracle() external view returns (address);

    function getFlowLimiter() external view returns (address);

    // Functions for MiniPool management
    function getMiniPool(uint256 id) external view returns (address);

    function getAToken6909(uint256 id) external view returns (address);

    function getMiniPoolId(address miniPool) external view returns (uint256);

    function getMiniPoolToAERC6909(address miniPool) external view returns (address);

    function getMiniPoolToAERC6909(uint256 id) external view returns (address);

    function getMiniPoolCod3xTreasury() external view returns (address);

    function getMiniPoolOwnerTreasury(uint256 id) external view returns (address);

    function getMiniPoolConfigurator() external view returns (address);

    function getMiniPoolList() external view returns (address[] memory);

    // Setters
    function setPoolAdmin(uint256 id, address newAdmin) external;

    function setFlowLimit(address asset, address miniPool, uint256 limit) external;

    function setMiniPoolImpl(address impl, uint256 miniPoolId) external;

    function setAToken6909Impl(address impl, uint256 miniPoolId) external;

    function deployMiniPool(address miniPoolImpl, address aTokenImpl, address poolAdmin)
        external
        returns (uint256);

    function setCod3xTreasury(address treasury) external;

    function setMinipoolOwnerTreasuryToMiniPool(uint256 id, address treasury) external;

    function setMiniPoolConfigurator(address configuratorImpl) external;
}
