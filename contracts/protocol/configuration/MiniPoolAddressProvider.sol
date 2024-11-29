// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {Ownable} from "../../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {InitializableImmutableAdminUpgradeabilityProxy} from
    "../../../contracts/protocol/libraries/upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol";
import {ILendingPoolAddressesProvider} from
    "../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IFlowLimiter} from "../../../contracts/interfaces/base/IFlowLimiter.sol";
import {IMiniPoolAddressesProvider} from
    "../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

/**
 * @title MiniPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles.
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations.
 * - Owned by the Cod3x Governance.
 * @author Cod3x
 */
contract MiniPoolAddressesProvider is Ownable, IMiniPoolAddressesProvider {
    /**
     * @dev Struct containing configuration for a mini pool.
     * @param miniPool Address of the mini pool contract.
     * @param aErc6909 Address of the associated aToken contract.
     * @param cod3xTreasury Address of the Cod3x treasury.
     * @param minipoolOwnerTreasury Address of the mini pool owner's treasury.
     * @param admin Address of the pool admin.
     */
    struct MiniPoolConfig {
        address miniPool;
        address aErc6909;
        address minipoolOwnerTreasury;
        address admin;
    }

    /**
     * @dev Modifier to check if pool ID is valid.
     * @param poolId The ID of the pool to check.
     */
    modifier poolIdCheck(uint256 poolId) {
        if (poolId >= _miniPoolCount) {
            revert(Errors.PAP_POOL_ID_OUT_OF_RANGE);
        }
        _;
    }

    /**
     * @dev Modifier to restrict access to mini pool configurator only.
     */
    modifier onlyMiniPoolConfigurator() {
        _onlyMiniPoolConfigurator();
        _;
    }

    /// @dev Mapping of identifiers to addresses.
    mapping(bytes32 => address) private _addresses;

    /// @dev Mapping of pool IDs to their configurations.
    mapping(uint256 => MiniPoolConfig) private _miniPoolsConfig;

    /// @dev Counter for the number of mini pools.
    uint256 private _miniPoolCount;

    /// @dev Address of the Cod3x treasury.
    address private _cod3xTreasury;

    /// @dev Constant identifier for lending pool addresses provider.
    bytes32 private constant LENDING_POOL_ADDRESSES_PROVIDER = "LENDING_POOL_ADDRESSES_PROVIDER";

    /// @dev Constant identifier for mini pool configurator.
    bytes32 private constant MINI_POOL_CONFIGURATOR = "MINI_POOL_CONFIGURATOR";

    /**
     * @dev Constructor to initialize the contract.
     * @param provider The address of the lending pool addresses provider.
     */
    constructor(ILendingPoolAddressesProvider provider) Ownable(msg.sender) {
        _addresses[LENDING_POOL_ADDRESSES_PROVIDER] = address(provider);
    }

    /* Getters */
    /**
     * @dev Returns the total number of mini pools.
     * @return The count of mini pools.
     */
    function getMiniPoolCount() external view returns (uint256) {
        return _miniPoolCount;
    }

    /**
     * @dev Returns the address of the lending pool addresses provider.
     * @return The provider address.
     */
    function getLendingPoolAddressesProvider() external view returns (address) {
        return _addresses[LENDING_POOL_ADDRESSES_PROVIDER];
    }

    /**
     * @dev Returns the address of the lending pool.
     * @return The lending pool address.
     */
    function getLendingPool() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getLendingPool();
    }

    /**
     * @dev Returns the admin address for a specific pool.
     * @param id The ID of the pool.
     * @return The admin address.
     */
    function getPoolAdmin(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].admin;
    }

    /**
     * @dev Returns the main pool admin address.
     * @return The main pool admin address.
     */
    function getMainPoolAdmin() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getPoolAdmin();
    }

    /**
     * @dev Returns the emergency admin address.
     * @return The emergency admin address.
     */
    function getEmergencyAdmin() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getEmergencyAdmin();
    }

    /**
     * @dev Returns the price oracle address.
     * @return The price oracle address.
     */
    function getPriceOracle() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getPriceOracle();
    }

    /**
     * @dev Returns the flow limiter address.
     * @return The flow limiter address.
     */
    function getFlowLimiter() public view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getFlowLimiter();
    }

    /**
     * @dev Returns the aToken address for a specific pool ID.
     * @param id The pool ID.
     * @return The aToken address.
     */
    function getAToken6909(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].aErc6909;
    }

    /**
     * @dev Returns the mini pool address for a specific ID.
     * @param id The pool ID.
     * @return The mini pool address.
     */
    function getMiniPool(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].miniPool;
    }

    /**
     * @dev Returns the ID for a given mini pool address.
     * @param miniPool The mini pool address.
     * @return The pool ID.
     */
    function getMiniPoolId(address miniPool) external view returns (uint256) {
        return _getMiniPoolId(miniPool);
    }

    /**
     * @dev Internal function to get mini pool ID from address.
     * @param miniPool The mini pool address.
     * @return The pool ID.
     */
    function _getMiniPoolId(address miniPool) private view returns (uint256) {
        for (uint256 id = 0; id < _miniPoolCount; id++) {
            if (_miniPoolsConfig[id].miniPool == miniPool) {
                return id;
            }
        }
        revert(Errors.PAP_NO_MINI_POOL_ID_FOR_ADDRESS);
    }

    /**
     * @dev Returns the aToken address for a given mini pool address.
     * @param miniPool The mini pool address.
     * @return The aToken address.
     */
    function getMiniPoolToAERC6909(address miniPool) external view returns (address) {
        uint256 miniPoolId = _getMiniPoolId(miniPool);
        return _miniPoolsConfig[miniPoolId].aErc6909;
    }

    /**
     * @dev Returns the aToken address for a specific pool ID.
     * @param id The pool ID.
     * @return The aToken address.
     */
    function getMiniPoolToAERC6909(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].aErc6909;
    }

    /**
     * @dev Returns the Cod3x treasury address.
     * @return The treasury address.
     */
    function getMiniPoolCod3xTreasury() external view returns (address) {
        return _cod3xTreasury;
    }

    /**
     * @dev Returns the mini pool owner's treasury address for a specific pool ID.
     * @param id The pool ID.
     * @return The treasury address.
     */
    function getMiniPoolOwnerTreasury(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].minipoolOwnerTreasury;
    }

    /**
     * @dev Returns the mini pool configurator address.
     * @return The configurator address.
     */
    function getMiniPoolConfigurator() external view returns (address) {
        return _addresses[MINI_POOL_CONFIGURATOR];
    }

    /**
     * @dev Returns a list of all mini pool addresses.
     * @return Array of mini pool addresses.
     */
    function getMiniPoolList() external view returns (address[] memory) {
        address[] memory miniPoolList = new address[](_miniPoolCount);
        for (uint256 idx = 0; idx < _miniPoolCount; idx++) {
            miniPoolList[idx] = _miniPoolsConfig[idx].miniPool;
        }
        return miniPoolList;
    }

    /**
     * @dev Returns an address by its identifier.
     * @param id The identifier.
     * @return The address.
     */
    function getAddress(bytes32 id) public view returns (address) {
        return _addresses[id];
    }

    /**
     * @dev Internal function to verify caller is mini pool configurator.
     */
    function _onlyMiniPoolConfigurator() internal view {
        require(
            _addresses[MINI_POOL_CONFIGURATOR] == msg.sender,
            Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
    }

    /* Setters */
    // ======= OnlyOwner =======
    /**
     * @dev Updates the implementation of a mini pool.
     * @param impl The new implementation address.
     * @param miniPoolId The ID of the mini pool to update.
     */
    function setMiniPoolImpl(address impl, uint256 miniPoolId) external onlyOwner {
        bytes memory params =
            abi.encodeWithSignature("initialize(address,uint256)", address(this), miniPoolId);
        _updateMiniPool(impl, miniPoolId, params);
        emit MiniPoolUpdated(impl);
    }

    /**
     * @dev Updates the implementation of an aToken.
     * @param impl The new implementation address.
     * @param miniPoolId The ID of the associated mini pool.
     */
    function setAToken6909Impl(address impl, uint256 miniPoolId) external onlyOwner {
        bytes memory params =
            abi.encodeWithSignature("initialize(address,uint256)", address(this), miniPoolId);
        _updateAToken(impl, miniPoolId, params);
        emit ATokenUpdated(impl);
    }

    /**
     * @dev Sets an address for an identifier.
     * @param id The identifier.
     * @param newAddress The new address to set.
     */
    function setAddress(bytes32 id, address newAddress) external onlyOwner {
        _addresses[id] = newAddress;
        emit AddressSet(id, newAddress, false);
    }

    /**
     * @dev Deploys a new mini pool with associated contracts.
     * @param miniPoolImpl The mini pool implementation address.
     * @param aTokenImpl The aToken implementation address.
     * @param poolAdmin The admin address for the new pool.
     * @return The ID of the newly created mini pool.
     */
    function deployMiniPool(address miniPoolImpl, address aTokenImpl, address poolAdmin)
        external
        onlyOwner
        returns (uint256)
    {
        bytes memory params =
            abi.encodeWithSignature("initialize(address,uint256)", address(this), _miniPoolCount);

        _initMiniPool(miniPoolImpl, params);

        _initATokenPool(aTokenImpl, params);

        uint256 miniPoolId = _miniPoolCount;

        _miniPoolsConfig[miniPoolId].admin = poolAdmin;
        _miniPoolCount++;

        return miniPoolId;
    }

    /**
     * @dev Sets the mini pool configurator implementation.
     * @param configuratorImpl The new configurator implementation address.
     */
    function setMiniPoolConfigurator(address configuratorImpl) external onlyOwner {
        _updateImpl(MINI_POOL_CONFIGURATOR, configuratorImpl);
        emit MiniPoolConfiguratorUpdated(configuratorImpl);
    }

    // ======= Only configurator =======

    /**
     * @dev Sets the flow limit for a specific asset and mini pool.
     * @param asset The asset address.
     * @param miniPool The mini pool address.
     * @param limit The new flow limit.
     */
    function setFlowLimit(address asset, address miniPool, uint256 limit)
        external
        onlyMiniPoolConfigurator
    {
        IFlowLimiter(getFlowLimiter()).setFlowLimit(asset, miniPool, limit);
        emit FlowLimitUpdated(limit);
    }

    /**
     * @dev Sets a new admin for a specific pool.
     * @param id The pool ID.
     * @param newAdmin The new admin address.
     */
    function setPoolAdmin(uint256 id, address newAdmin) external onlyMiniPoolConfigurator {
        require(newAdmin != address(0));
        _miniPoolsConfig[id].admin = newAdmin;
        emit PoolAdminSet(newAdmin);
    }

    /**
     * @dev Sets the Cod3x treasury address for all mini pools.
     * @param treasury The new treasury address.
     */
    function setCod3xTreasury(address treasury) external onlyMiniPoolConfigurator {
        _cod3xTreasury = treasury;
        emit Cod3xTreasurySet(treasury);
    }

    /**
     * @dev Sets the mini pool owner's treasury address.
     * @param id The pool ID.
     * @param treasury The new treasury address.
     */
    function setMinipoolOwnerTreasuryToMiniPool(uint256 id, address treasury)
        external
        poolIdCheck(id)
        onlyMiniPoolConfigurator
    {
        _miniPoolsConfig[id].minipoolOwnerTreasury = treasury;
        emit MinipoolOwnerTreasurySet(treasury, id);
    }

    /* Internals */
    /**
     * @dev Internal function to update mini pool implementation.
     * @param miniPoolImpl The new implementation address.
     * @param miniPoolId The ID of the mini pool to update.
     * @param params The initialization parameters.
     */
    function _updateMiniPool(address miniPoolImpl, uint256 miniPoolId, bytes memory params)
        internal
        poolIdCheck(miniPoolId)
    {
        address payable proxyAddress = payable(_miniPoolsConfig[miniPoolId].miniPool);
        InitializableImmutableAdminUpgradeabilityProxy proxy =
            InitializableImmutableAdminUpgradeabilityProxy(proxyAddress);
        proxy.upgradeToAndCall(miniPoolImpl, params);
        _miniPoolsConfig[miniPoolId].miniPool = address(proxy);
    }

    /**
     * @dev Internal function to update aToken implementation.
     * @param aTokenImpl The new implementation address.
     * @param miniPoolId The ID of the associated mini pool.
     * @param params The initialization parameters.
     */
    function _updateAToken(address aTokenImpl, uint256 miniPoolId, bytes memory params)
        internal
        poolIdCheck(miniPoolId)
    {
        address payable proxyAddress = payable(_miniPoolsConfig[miniPoolId].aErc6909);
        InitializableImmutableAdminUpgradeabilityProxy proxy =
            InitializableImmutableAdminUpgradeabilityProxy(proxyAddress);
        proxy.upgradeToAndCall(aTokenImpl, params);
        /* Update new ERC 6909 impl for all specified miniPools Ids */
        _miniPoolsConfig[miniPoolId].aErc6909 = address(proxy);
    }

    /**
     * @dev Internal function to initialize a new mini pool.
     * @param miniPoolImpl The implementation address.
     * @param params The initialization parameters.
     */
    function _initMiniPool(address miniPoolImpl, bytes memory params) internal {
        InitializableImmutableAdminUpgradeabilityProxy proxy =
            new InitializableImmutableAdminUpgradeabilityProxy(address(this));

        proxy.initialize(miniPoolImpl, params);

        _miniPoolsConfig[_miniPoolCount].miniPool = address(proxy);
        emit ProxyCreated(_miniPoolCount, address(proxy));
    }

    /**
     * @dev Internal function to initialize a new aToken pool.
     * @param aTokenImpl The implementation address.
     * @param params The initialization parameters.
     */
    function _initATokenPool(address aTokenImpl, bytes memory params) internal {
        InitializableImmutableAdminUpgradeabilityProxy aTokenProxy =
            new InitializableImmutableAdminUpgradeabilityProxy(address(this));

        aTokenProxy.initialize(aTokenImpl, params);

        _miniPoolsConfig[_miniPoolCount].aErc6909 = address(aTokenProxy);
        emit ProxyCreated(_miniPoolCount, address(aTokenProxy));
    }

    /**
     * @dev Internal function to update implementation of a contract.
     * @param id The identifier of the contract.
     * @param newAddress The new implementation address.
     */
    function _updateImpl(bytes32 id, address newAddress) internal {
        address payable proxyAddress = payable(_addresses[id]);

        InitializableImmutableAdminUpgradeabilityProxy proxy =
            InitializableImmutableAdminUpgradeabilityProxy(proxyAddress);
        bytes memory params = abi.encodeWithSignature("initialize(address)", address(this));
        if (proxyAddress == address(0)) {
            proxy = new InitializableImmutableAdminUpgradeabilityProxy(address(this));
            proxy.initialize(newAddress, params);
            _addresses[id] = address(proxy);
            emit ProxyCreated(id, address(proxy));
        } else {
            proxy.upgradeToAndCall(newAddress, params);
        }
    }
}
