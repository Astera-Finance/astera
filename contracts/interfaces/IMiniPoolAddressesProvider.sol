// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title IMiniPoolAddressesProvider interface.
 * @author Conclave
 */
interface IMiniPoolAddressesProvider {
    /**
     * @dev Emitted when the mini pool implementation is updated.
     * @param newAddress The address of the new MiniPool implementation.
     * @param miniPoolId The ID of the mini pool.
     */
    event MiniPoolUpdated(address indexed newAddress, uint256 indexed miniPoolId);

    /**
     * @dev Emitted when the aToken implementation is updated.
     * @param newAddress The address of the new aToken implementation.
     * @param miniPoolId The ID of the mini pool.
     */
    event ATokenUpdated(address indexed newAddress, uint256 indexed miniPoolId);

    /**
     * @dev Emitted when a flow limit is updated.
     * @param asset The asset address.
     * @param miniPool The mini pool address.
     * @param limit The new flow limit value.
     */
    event FlowLimitUpdated(address indexed asset, address indexed miniPool, uint256 indexed limit);

    /**
     * @dev Emitted when a new mini pool proxy is created.
     * @param poolId The ID of the mini pool.
     * @param id The identifier of the proxy.
     * @param newAddress The address of the created proxy contract.
     */
    event ProxyCreated(uint256 indexed poolId, bytes32 indexed id, address indexed newAddress);

    /**
     * @dev Emitted when a new proxy is created.
     * @param id The identifier of the proxy.
     * @param newAddress The address of the created proxy contract.
     */
    event ProxyCreated(bytes32 indexed id, address indexed newAddress);

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
     * @param miniPoolId The ID of the mini pool.
     */
    event PoolAdminSet(address indexed newAdmin, uint256 indexed miniPoolId);

    /**
     * @dev Emitted when a Astera treasury is set for all mini pools.
     * @param treasury The address of the Astera treasury.
     */
    event AsteraTreasurySet(address indexed treasury);

    /**
     * @dev Emitted when a mini pool owner treasury is set.
     * @param treasury The address of the mini pool owner treasury.
     * @param miniPoolId The ID of the mini pool.
     */
    event MinipoolOwnerTreasurySet(address indexed treasury, uint256 miniPoolId);

    /**
     * @dev Emitted when the maximum number of reserves with flow borrowing is updated.
     * @param newMax The new maximum number of reserves with flow borrowing.
     */
    event MaxReservesWithFlowBorrowingUpdated(uint256 newMax);

    /**
     * @dev Emitted when the access manager is updated.
     * @param newAddress The new access manager address.
     */
    event AccessManagerSet(address indexed newAddress);

    // Functions related to getting various addresses
    function getMiniPoolCount() external view returns (uint256);

    function getLendingPoolAddressesProvider() external view returns (address);

    function getLendingPool() external view returns (address);

    function getPoolAdmin(uint256 id) external view returns (address);

    function getMainPoolAdmin() external view returns (address);

    function getEmergencyAdmin() external view returns (address);

    function getPriceOracle() external view returns (address);

    function getFlowLimiter() external view returns (address);

    function getNumberOfReservesWithFlowBorrowing() external view returns (uint256);

    function getMaxReservesWithFlowBorrowing() external view returns (uint256);

    // Functions for MiniPool management
    function getMiniPool(uint256 id) external view returns (address);

    function getMiniPoolId(address miniPool) external view returns (uint256);

    function getMiniPoolToAERC6909(address miniPool) external view returns (address);

    function getMiniPoolToAERC6909(uint256 id) external view returns (address);

    function isMiniPool(address miniPool) external view returns (bool);

    function getMiniPoolAsteraTreasury() external view returns (address);

    function getMiniPoolOwnerTreasury(uint256 id) external view returns (address);

    function getMiniPoolConfigurator() external view returns (address);

    function getMiniPoolList() external view returns (address[] memory);

    function getAccessManager() external view returns (address);

    // Setters
    function setPoolAdmin(uint256 id, address newAdmin) external;

    function setFlowLimit(address asset, address miniPool, uint256 limit) external;

    function setMiniPoolImpl(address impl, uint256 miniPoolId) external;

    function setAToken6909Impl(address impl, uint256 miniPoolId) external;

    function deployMiniPool(address miniPoolImpl, address aTokenImpl, address poolAdmin)
        external
        returns (uint256);

    function setAsteraTreasury(address treasury) external;

    function setMinipoolOwnerTreasuryToMiniPool(uint256 id, address treasury) external;

    function setMiniPoolConfigurator(address configuratorImpl) external;

    function setMaxReservesWithFlowBorrowing(uint256 newMax) external;

    function setAccessManager(address accessManager) external;
}
