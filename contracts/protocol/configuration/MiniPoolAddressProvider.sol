// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {Ownable} from '../../dependencies/openzeppelin/contracts/Ownable.sol';

// Prettier ignore to prevent buidler flatter bug
// prettier-ignore
import {InitializableImmutableAdminUpgradeabilityProxy} from '../libraries/upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol';

import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';

/**
 * @title LendingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations
 * - Owned by the Aave Governance
 * @author Aave
 **/
contract MiniPoolAddressesProvider is Ownable{
  
  mapping(bytes32 => address) private _addresses;

  mapping(uint256 => address) private _minipools;
  mapping(address => address) private _miniPoolToAERC6909;
  mapping(uint256 => address) private _miniPoolToTreasury; 
  uint256 private _minipoolCount;

  bytes32 private constant LENDING_POOL = 'LENDING_POOL';
  bytes32 private constant LENDING_POOL_ADDRESSES_PROVIDER = 'LENDING_POOL_ADDRESSES_PROVIDER';
  bytes32 private constant LENDING_POOL_CONFIGURATOR = 'LENDING_POOL_CONFIGURATOR';
  bytes32 private constant POOL_ADMIN = 'POOL_ADMIN';
  bytes32 private constant EMERGENCY_ADMIN = 'EMERGENCY_ADMIN';
  bytes32 private constant LENDING_POOL_COLLATERAL_MANAGER = 'COLLATERAL_MANAGER';
  bytes32 private constant PRICE_ORACLE = 'PRICE_ORACLE';

  bytes32 private constant MINIPOOL_IMPL = 'MINIPOOL_IMPL';
  bytes32 private constant ATOKEN6909_IMPL = 'ATOKEN6909_IMPL';

  constructor(ILendingPoolAddressesProvider provider) public Ownable(msg.sender) {
    _addresses[LENDING_POOL_ADDRESSES_PROVIDER] = address(provider);
    _addresses[LENDING_POOL] = provider.getLendingPool();
    _addresses[LENDING_POOL_CONFIGURATOR] = provider.getLendingPoolConfigurator();
    _addresses[POOL_ADMIN] = provider.getPoolAdmin();
    _addresses[EMERGENCY_ADMIN] = provider.getEmergencyAdmin();
    _addresses[LENDING_POOL_COLLATERAL_MANAGER] = provider.getLendingPoolCollateralManager();
    _addresses[PRICE_ORACLE] = provider.getPriceOracle();
  }

  function getLendingPoolAddressesProvider() external view returns (address) {
    return _addresses[LENDING_POOL_ADDRESSES_PROVIDER];
  }

  function getLendingPool() external view returns (address) {
    return _addresses[LENDING_POOL];
  }

  function getLendingPoolConfigurator() external view returns (address) {
    return _addresses[LENDING_POOL_CONFIGURATOR];
  }

  function getPoolAdmin() external view returns (address) {
    return _addresses[POOL_ADMIN];
  }

  function getEmergencyAdmin() external view returns (address) {
    return _addresses[EMERGENCY_ADMIN];
  }

  function getLendingPoolCollateralManager() external view returns (address) {
    return _addresses[LENDING_POOL_COLLATERAL_MANAGER];
  }

  function getPriceOracle() external view returns (address) {
    return _addresses[PRICE_ORACLE];
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

  function upgradeMiniPool(address MiniPoolProxy) external onlyOwner {

  }

  function deployMiniPool() external onlyOwner {
    InitializableImmutableAdminUpgradeabilityProxy proxy = new InitializableImmutableAdminUpgradeabilityProxy(
      _addresses[MINIPOOL_IMPL]);

    bytes memory data = abi.encode(_minipoolCount);
    proxy.initialize(address(this), data);

    _minipools[_minipoolCount] = address(proxy);

    InitializableImmutableAdminUpgradeabilityProxy aTokenProxy = new InitializableImmutableAdminUpgradeabilityProxy(
      _addresses[ATOKEN6909_IMPL]);

    aTokenProxy.initialize(address(this), data);

    _minipoolCount++;
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
    return _addresses[LENDING_POOL_CONFIGURATOR];
  }


  



}
