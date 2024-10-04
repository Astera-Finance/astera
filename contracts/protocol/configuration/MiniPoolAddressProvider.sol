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

/**
 * @title LendingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations
 * - Owned by the Aave Governance
 * @author Cod3x
 *
 */
contract MiniPoolAddressesProvider is Ownable, IMiniPoolAddressesProvider {
    mapping(bytes32 => address) private _addresses;

    mapping(uint256 => address) private _minipools;
    mapping(address => address) private _miniPoolToAERC6909;
    mapping(uint256 => address) private _miniPoolToTreasury;
    uint256 private _minipoolCount;

    bytes32 private constant LENDING_POOL_ADDRESSES_PROVIDER = "LENDING_POOL_ADDRESSES_PROVIDER";
    bytes32 private constant MINI_POOL_CONFIGURATOR = "MINI_POOL_CONFIGURATOR";
    bytes32 private constant LENDING_POOL_COLLATERAL_MANAGER = "COLLATERAL_MANAGER";

    bytes32 private constant MINIPOOL_IMPL = "MINIPOOL_IMPL";
    bytes32 private constant ATOKEN6909_IMPL = "ATOKEN6909_IMPL";

    constructor(ILendingPoolAddressesProvider provider) Ownable(msg.sender) {
        _addresses[LENDING_POOL_ADDRESSES_PROVIDER] = address(provider);
    }

    function getMiniPoolCount() external view returns (uint256) {
        return _minipoolCount;
    }

    function getLendingPoolAddressesProvider() external view returns (address) {
        return _addresses[LENDING_POOL_ADDRESSES_PROVIDER];
    }

    function getLendingPool() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getLendingPool();
    }

    function getLendingPoolConfigurator() external view returns (address) {
        return _addresses[MINI_POOL_CONFIGURATOR];
    }

    function getPoolAdmin() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getPoolAdmin();
    }

    function getEmergencyAdmin() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getEmergencyAdmin();
    }

    function getLendingPoolCollateralManager() external view returns (address) {
        return _addresses[LENDING_POOL_COLLATERAL_MANAGER];
    }

    function getPriceOracle() external view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getPriceOracle();
    }

    function getFlowLimiter() public view returns (address) {
        return ILendingPoolAddressesProvider(_addresses[LENDING_POOL_ADDRESSES_PROVIDER])
            .getFlowLimiter();
    }

    function setFlowLimit(address asset, address miniPool, uint256 limit) external onlyOwner {
        IFlowLimiter(getFlowLimiter()).setFlowLimit(asset, miniPool, limit);
    }

    function setMiniPoolImpl(address impl) external onlyOwner {
        _addresses[MINIPOOL_IMPL] = impl;
    }

    function getMiniPoolImpl() external view returns (address) {
        return _addresses[MINIPOOL_IMPL];
    }

    function setAToken6909Impl(address impl) external onlyOwner {
        _addresses[ATOKEN6909_IMPL] = impl;
    }

    function getAToken6909Impl() external view returns (address) {
        return _addresses[ATOKEN6909_IMPL];
    }

    function upgradeMiniPool(address MiniPoolProxy) external onlyOwner {}

    function deployMiniPool() external onlyOwner returns (uint256) {
        InitializableImmutableAdminUpgradeabilityProxy proxy =
            new InitializableImmutableAdminUpgradeabilityProxy(address(this));

        bytes memory params =
            abi.encodeWithSignature("initialize(address,uint256)", address(this), _minipoolCount);
        proxy.initialize(_addresses[MINIPOOL_IMPL], params);

        _minipools[_minipoolCount] = address(proxy);

        InitializableImmutableAdminUpgradeabilityProxy aTokenProxy =
            new InitializableImmutableAdminUpgradeabilityProxy(address(this));

        aTokenProxy.initialize(_addresses[ATOKEN6909_IMPL], params);

        _miniPoolToAERC6909[address(proxy)] = address(aTokenProxy);

        uint256 minipoolID = _minipoolCount;

        _minipoolCount++;

        return minipoolID;
    }

    function getMiniPool(uint256 id) external view returns (address) {
        return _minipools[id];
    }

    function getMiniPoolToAERC6909(address minipool) external view returns (address) {
        return _miniPoolToAERC6909[minipool];
    }

    function getAERC6909BYID(uint256 id) external view returns (address) {
        return _miniPoolToAERC6909[_minipools[id]];
    }

    function getMiniPoolTreasury(uint256 id) external view returns (address) {
        return _miniPoolToTreasury[id];
    }

    function getMiniPoolConfigurator() external view returns (address) {
        return _addresses[MINI_POOL_CONFIGURATOR];
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
        } else {
            proxy.upgradeToAndCall(newAddress, params);
        }
    }

    function setMiniPoolConfigurator(address configuratorIMPL) external onlyOwner {
        _updateImpl(MINI_POOL_CONFIGURATOR, configuratorIMPL);
    }

    function setMiniPoolCollateralManager(address collateralManager) external onlyOwner {
        _addresses[LENDING_POOL_COLLATERAL_MANAGER] = collateralManager;
    }

    function setMiniPoolToTreasury(uint256 id, address treasury) external onlyOwner {
        _miniPoolToTreasury[id] = treasury;
    }
}
