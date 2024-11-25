// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {Ownable} from "../../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";

// Prettier ignore to prevent buidler flatter bug
// prettier-ignore
import {InitializableImmutableAdminUpgradeabilityProxy} from
    "../../../contracts/protocol/libraries/upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol";
import {ILendingPoolAddressesProvider} from
    "../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IFlowLimiter} from "../../../contracts/interfaces/IFlowLimiter.sol";
import {IMiniPoolAddressesProvider} from
    "../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

/**
 * @title LendingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations
 * - Owned by the Cod3x Governance
 * @author Cod3x
 *
 */
contract MiniPoolAddressesProvider is Ownable, IMiniPoolAddressesProvider {
    struct MiniPoolConfig {
        address miniPool;
        address aErc6909;
        address cod3xTreasury;
        address minipoolOwnerTreasury;
        address admin;
    }

    modifier poolIdCheck(uint256 poolId) {
        if (poolId >= _miniPoolCount) {
            revert(Errors.PAP_POOL_ID_OUT_OF_RANGE);
        }
        _;
    }

    modifier onlyMiniPoolConfigurator() {
        _onlyMiniPoolConfigurator();
        _;
    }

    mapping(bytes32 => address) private _addresses;
    mapping(uint256 => MiniPoolConfig) private _miniPoolsConfig;
    uint256 private _miniPoolCount;

    bytes32 private constant LENDING_POOL_ADDRESSES_PROVIDER = "LENDING_POOL_ADDRESSES_PROVIDER";
    bytes32 private constant MINI_POOL_CONFIGURATOR = "MINI_POOL_CONFIGURATOR";

    constructor(ILendingPoolAddressesProvider provider) Ownable(msg.sender) {
        _addresses[LENDING_POOL_ADDRESSES_PROVIDER] = address(provider);
    }

    /* Getters */
    function getMiniPoolCount() external view returns (uint256) {
        return _miniPoolCount;
    }

    function getLendingPoolAddressesProvider() external view returns (address) {
        return _addresses[LENDING_POOL_ADDRESSES_PROVIDER];
    }

    function getLendingPool() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getLendingPool();
    }

    function getPoolAdmin(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].admin;
    }

    function getMainPoolAdmin() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getPoolAdmin();
    }

    function getEmergencyAdmin() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getEmergencyAdmin();
    }

    function getPriceOracle() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getPriceOracle();
    }

    function getFlowLimiter() public view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getFlowLimiter();
    }

    function getAToken6909(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].aErc6909;
    }

    function getMiniPool(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].miniPool;
    }

    function getMiniPoolId(address miniPool) external view returns (uint256) {
        return _getMiniPoolId(miniPool);
    }

    function _getMiniPoolId(address miniPool) private view returns (uint256) {
        for (uint256 id = 0; id < _miniPoolCount; id++) {
            if (_miniPoolsConfig[id].miniPool == miniPool) {
                return id;
            }
        }
        revert(Errors.PAP_NO_MINI_POOL_ID_FOR_ADDRESS);
    }

    function getMiniPoolToAERC6909(address miniPool) external view returns (address) {
        uint256 miniPoolId = _getMiniPoolId(miniPool);
        return _miniPoolsConfig[miniPoolId].aErc6909;
    }

    function getMiniPoolToAERC6909(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].aErc6909;
    }

    function getMiniPoolCod3xTreasury(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].cod3xTreasury;
    }

    function getMiniPoolOwnerTreasury(uint256 id) external view returns (address) {
        return _miniPoolsConfig[id].minipoolOwnerTreasury;
    }

    function getMiniPoolConfigurator() external view returns (address) {
        return _addresses[MINI_POOL_CONFIGURATOR];
    }

    function getMiniPoolList() external view returns (address[] memory) {
        address[] memory miniPoolList = new address[](_miniPoolCount);
        for (uint256 idx = 0; idx < _miniPoolCount; idx++) {
            miniPoolList[idx] = _miniPoolsConfig[idx].miniPool;
        }
        return miniPoolList;
    }

    /**
     * @dev Returns an address by id
     * @return The address
     */
    function getAddress(bytes32 id) public view returns (address) {
        return _addresses[id];
    }

    function _onlyMiniPoolConfigurator() internal view {
        require(
            _addresses[MINI_POOL_CONFIGURATOR] == msg.sender,
            Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
    }

    /* Setters */
    /*___ OnlyOwner ___*/
    function setMiniPoolImpl(address impl, uint256 miniPoolId) external onlyOwner {
        bytes memory params =
            abi.encodeWithSignature("initialize(address,uint256)", address(this), miniPoolId);
        _updateMiniPool(impl, miniPoolId, params);
        emit MiniPoolUpdated(impl);
    }

    function setAToken6909Impl(address impl, uint256 miniPoolId) external onlyOwner {
        bytes memory params =
            abi.encodeWithSignature("initialize(address,uint256)", address(this), miniPoolId);
        _updateAToken(impl, miniPoolId, params);
        emit ATokenUpdated(impl);
    }
    /**
     * @dev Sets an address for an id replacing the address saved in the addresses map
     * IMPORTANT Use this function carefully, as it will do a hard replacement
     * @param id The id
     * @param newAddress The address to set
     */

    function setAddress(bytes32 id, address newAddress) external onlyOwner {
        _addresses[id] = newAddress;
        emit AddressSet(id, newAddress, false);
    }

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

    function setMiniPoolConfigurator(address configuratorImpl) external onlyOwner {
        _updateImpl(MINI_POOL_CONFIGURATOR, configuratorImpl);
        emit MiniPoolConfiguratorUpdated(configuratorImpl);
    }

    /*___ Only configurator ___*/

    function setFlowLimit(address asset, address miniPool, uint256 limit)
        external
        onlyMiniPoolConfigurator
    {
        IFlowLimiter(getFlowLimiter()).setFlowLimit(asset, miniPool, limit);
        emit FlowLimitUpdated(limit);
    }

    function setPoolAdmin(uint256 id, address newAdmin) external onlyMiniPoolConfigurator {
        require(newAdmin != address(0));
        _miniPoolsConfig[id].admin = newAdmin;
        emit PoolAdminSet(newAdmin);
    }

    function setCod3xTreasuryToMiniPool(uint256 id, address treasury)
        external
        poolIdCheck(id)
        onlyMiniPoolConfigurator
    {
        _miniPoolsConfig[id].cod3xTreasury = treasury;
        emit Cod3xTreasurySet(treasury, id);
    }

    function setMinipoolOwnerTreasuryToMiniPool(uint256 id, address treasury)
        external
        poolIdCheck(id)
        onlyMiniPoolConfigurator
    {
        _miniPoolsConfig[id].minipoolOwnerTreasury = treasury;
        emit MinipoolOwnerTreasurySet(treasury, id);
    }

    /* Internals */
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

    function _initMiniPool(address miniPoolImpl, bytes memory params) internal {
        InitializableImmutableAdminUpgradeabilityProxy proxy =
            new InitializableImmutableAdminUpgradeabilityProxy(address(this));

        proxy.initialize(miniPoolImpl, params);

        _miniPoolsConfig[_miniPoolCount].miniPool = address(proxy);
        emit ProxyCreated(_miniPoolCount, address(proxy));
    }

    function _initATokenPool(address aTokenImpl, bytes memory params) internal {
        InitializableImmutableAdminUpgradeabilityProxy aTokenProxy =
            new InitializableImmutableAdminUpgradeabilityProxy(address(this));

        aTokenProxy.initialize(aTokenImpl, params);

        _miniPoolsConfig[_miniPoolCount].aErc6909 = address(aTokenProxy);
        emit ProxyCreated(_miniPoolCount, address(aTokenProxy));
    }

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
