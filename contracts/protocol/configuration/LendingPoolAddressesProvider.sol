// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {Ownable} from "../../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {InitializableImmutableAdminUpgradeabilityProxy} from
    "../../../contracts/protocol/libraries/upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol";
import {ILendingPoolAddressesProvider} from
    "../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IAddressProviderUpdatable} from
    "../../../contracts/interfaces/IAddressProviderUpdatable.sol";

/**
 * @title LendingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles.
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations.
 * - Owned by the Astera Governance.
 * @author Conclave
 */
contract LendingPoolAddressesProvider is Ownable, ILendingPoolAddressesProvider {
    mapping(bytes32 => address) private _addresses;

    bytes32 private constant LENDING_POOL = keccak256("LENDING_POOL");
    bytes32 private constant LENDING_POOL_CONFIGURATOR = keccak256("LENDING_POOL_CONFIGURATOR");
    bytes32 private constant POOL_ADMIN = keccak256("POOL_ADMIN");
    bytes32 private constant EMERGENCY_ADMIN = keccak256("EMERGENCY_ADMIN");
    bytes32 private constant PRICE_ORACLE = keccak256("PRICE_ORACLE");
    bytes32 private constant MINIPOOL_ADDRESSES_PROVIDER = keccak256("MINIPOOL_ADDRESSES_PROVIDER");
    bytes32 private constant FLOW_LIMITER = keccak256("FLOW_LIMITER");

    constructor() Ownable(msg.sender) {}

    /**
     * @dev General function to update the implementation of a proxy registered with certain `id`.
     * If there is no proxy registered, it will instantiate one and set as implementation the `implementationAddress`.
     * IMPORTANT: Use this function carefully, only for ids that don't have an explicit setter function,
     * in order to avoid unexpected consequences.
     * @param id The identifier of the proxy to update.
     * @param implementationAddress The address of the new implementation.
     */
    function setAddressAsProxy(bytes32 id, address implementationAddress)
        external
        override
        onlyOwner
    {
        _updateImpl(id, implementationAddress);
        emit AddressSet(id, implementationAddress, true);
    }

    /**
     * @dev Sets an address for an id replacing the address saved in the addresses map.
     * IMPORTANT: Use this function carefully, as it will do a hard replacement.
     * @param id The identifier for the address mapping.
     * @param newAddress The address to set.
     */
    function setAddress(bytes32 id, address newAddress) external override onlyOwner {
        _addresses[id] = newAddress;

        emit AddressSet(id, newAddress, false);
    }

    /**
     * @dev Returns an address by id.
     * @param id The identifier to look up.
     * @return The address mapped to the id.
     */
    function getAddress(bytes32 id) public view override returns (address) {
        return _addresses[id];
    }

    /**
     * @dev Returns the address of the LendingPool proxy.
     * @return The LendingPool proxy address.
     */
    function getLendingPool() external view override returns (address) {
        return getAddress(LENDING_POOL);
    }

    /**
     * @dev Updates the implementation of the LendingPool, or creates the proxy
     * setting the new `pool` implementation on the first time calling it.
     * @param pool The new LendingPool implementation address.
     */
    function setLendingPoolImpl(address pool) external override onlyOwner {
        _updateImpl(LENDING_POOL, pool);

        emit LendingPoolUpdated(pool);
    }

    /**
     * @dev Returns the address of the LendingPoolConfigurator proxy.
     * @return The LendingPoolConfigurator proxy address.
     */
    function getLendingPoolConfigurator() external view override returns (address) {
        return getAddress(LENDING_POOL_CONFIGURATOR);
    }

    /**
     * @dev Updates the implementation of the LendingPoolConfigurator, or creates the proxy
     * setting the new `configurator` implementation on the first time calling it.
     * @param configurator The new LendingPoolConfigurator implementation address.
     */
    function setLendingPoolConfiguratorImpl(address configurator) external override onlyOwner {
        _updateImpl(LENDING_POOL_CONFIGURATOR, configurator);
        emit LendingPoolConfiguratorUpdated(configurator);
    }

    /**
     * @dev The functions below are getters/setters of addresses that are outside the context
     * of the protocol hence the upgradable proxy pattern is not used.
     */

    /**
     * @dev Returns the address of the pool admin.
     * @return The current pool admin address.
     */
    function getPoolAdmin() external view override returns (address) {
        return getAddress(POOL_ADMIN);
    }

    /**
     * @dev Updates the pool admin address.
     * @param admin The new admin address.
     */
    function setPoolAdmin(address admin) external override onlyOwner {
        _addresses[POOL_ADMIN] = admin;

        emit ConfigurationAdminUpdated(admin);
    }

    /**
     * @dev Returns the address of the emergency admin.
     * @return The current emergency admin address.
     */
    function getEmergencyAdmin() external view override returns (address) {
        return getAddress(EMERGENCY_ADMIN);
    }

    /**
     * @dev Updates the emergency admin address.
     * @param emergencyAdmin The new emergency admin address.
     */
    function setEmergencyAdmin(address emergencyAdmin) external override onlyOwner {
        _addresses[EMERGENCY_ADMIN] = emergencyAdmin;

        emit EmergencyAdminUpdated(emergencyAdmin);
    }

    /**
     * @dev Returns the address of the price oracle.
     * @return The current price oracle address.
     */
    function getPriceOracle() external view override returns (address) {
        return getAddress(PRICE_ORACLE);
    }

    /**
     * @dev Updates the price oracle address.
     * @param priceOracle The new price oracle address.
     */
    function setPriceOracle(address priceOracle) external override onlyOwner {
        _addresses[PRICE_ORACLE] = priceOracle;

        emit PriceOracleUpdated(priceOracle);
    }

    /**
     * @dev Internal function to update the implementation of a specific proxied component of the protocol.
     * If there is no proxy registered in the given `id`, it creates the proxy setting `newAddress`
     * as implementation and calls the initialize() function on the proxy.
     * If there is already a proxy registered, it just updates the implementation to `newAddress` and
     * calls the initialize() function via upgradeToAndCall() in the proxy.
     * @param id The id of the proxy to be updated.
     * @param newAddress The address of the new implementation.
     */
    function _updateImpl(bytes32 id, address newAddress) internal {
        address payable proxyAddress = payable(_addresses[id]);

        InitializableImmutableAdminUpgradeabilityProxy proxy =
            InitializableImmutableAdminUpgradeabilityProxy(proxyAddress);
        bytes memory params = abi.encodeCall(IAddressProviderUpdatable.initialize, (address(this)));

        if (proxyAddress == address(0)) {
            proxy = new InitializableImmutableAdminUpgradeabilityProxy(address(this));
            proxy.initialize(newAddress, params);
            _addresses[id] = address(proxy);
            emit ProxyCreated(id, address(proxy));
        } else {
            proxy.upgradeToAndCall(newAddress, params);
        }
    }

    /**
     * @dev Returns the address of the MiniPool addresses provider.
     * @return The current MiniPool addresses provider address.
     */
    function getMiniPoolAddressesProvider() external view override returns (address) {
        return getAddress(MINIPOOL_ADDRESSES_PROVIDER);
    }

    /**
     * @dev Updates the MiniPool addresses provider.
     * @param provider The new MiniPool addresses provider address.
     */
    function setMiniPoolAddressesProvider(address provider) external override onlyOwner {
        _addresses[MINIPOOL_ADDRESSES_PROVIDER] = provider;

        emit MiniPoolAddressesProviderUpdated(provider);
    }

    /**
     * @dev Returns the address of the flow limiter.
     * @return The current flow limiter address.
     */
    function getFlowLimiter() external view override returns (address) {
        return getAddress(FLOW_LIMITER);
    }

    /**
     * @dev Updates the flow limiter address.
     * @param flowLimiter The new flow limiter address.
     */
    function setFlowLimiter(address flowLimiter) external override onlyOwner {
        _addresses[FLOW_LIMITER] = flowLimiter;

        emit FlowLimiterUpdated(flowLimiter);
    }
}
