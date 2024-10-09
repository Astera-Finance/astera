// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface IMiniPoolAddressesProvider {
    // Events
    event MiniPoolUpdated(address indexed newAddress);
    event ATokenUpdated(address indexed newAddress);
    event FlowLimitUpdated(uint256 indexed limit);
    event ProxyCreated(uint256 poolId, address indexed newAddress);
    event ProxyCreated(bytes32 id, address indexed newAddress);
    event AddressSet(bytes32 id, address indexed newAddress, bool hasProxy);
    event MiniPoolConfiguratorUpdated(address indexed newAddress);
    event MiniPoolCollateralManagerUpdated(address indexed newAddress);
    event TreasurySet(address indexed treasury, uint256 miniPoolId);

    // Errors
    error NoMiniPoolIdForAddress();
    error NoImplOfAToken6909();
    error PoolIdOutOfRange();
    error NotAllowedIds();

    // Functions related to getting various addresses
    function getMiniPoolCount() external view returns (uint256);
    function getLendingPoolAddressesProvider() external view returns (address);
    function getLendingPool() external view returns (address);
    function getPoolAdmin() external view returns (address);
    function getEmergencyAdmin() external view returns (address);
    function getMiniPoolCollateralManager() external view returns (address);
    function getPriceOracle() external view returns (address);
    function getFlowLimiter() external view returns (address);

    // Functions for MiniPool management
    function getMiniPool(uint256 id) external view returns (address);
    function getAToken6909(uint256 id) external view returns (address);
    function getMiniPoolId(address miniPool) external view returns (uint256);
    function getMiniPoolToAERC6909(address miniPool) external view returns (address);
    function getMiniPoolToAERC6909(uint256 id) external view returns (address);
    function getMiniPoolTreasury(uint256 id) external view returns (address);
    function getMiniPoolConfigurator() external view returns (address);
    function getMiniPoolList() external view returns (address[] memory);

    // Setters
    function setFlowLimit(address asset, address miniPool, uint256 limit) external;
    function setMiniPoolImpl(address impl, uint256 miniPoolId) external;
    function setAToken6909Impl(address impl, uint256 miniPoolId) external;
    function deployMiniPool(address miniPoolImpl, address aTokenImpl) external returns (uint256);
    function setMiniPoolCollateralManager(address collateralManager) external;
    function setMiniPoolToTreasury(uint256 id, address treasury) external;
    function setMiniPoolConfigurator(address configuratorImpl) external;
}
