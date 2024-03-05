// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

interface IMiniPoolAddressesProvider {
    // Functions related to getting various addresses
    function getLendingPoolAddressesProvider() external view returns (address);
    function getLendingPool() external view returns (address);
    function getLendingPoolConfigurator() external view returns (address);
    function getPoolAdmin() external view returns (address);
    function getEmergencyAdmin() external view returns (address);
    function getLendingPoolCollateralManager() external view returns (address);
    function getPriceOracle() external view returns (address);

    // Functions related to MiniPool implementation management
    function setMiniPoolImpl(address impl) external;
    function getMiniPoolImpl() external view returns (address);
    
    // Functions related to AToken6909 implementation management
    function setAToken6909Impl(address impl) external;
    function getAToken6909Impl() external view returns (address);

    // Functions for MiniPool management
    function deployMiniPool() external;
    function upgradeMiniPool(address MiniPoolProxy) external;
    function getMiniPool(uint256 id) external view returns (address);

    // Functions for mapping MiniPools to AERC6909 tokens
    function getMiniPoolToAERC6909(address minipool) external view returns (address);
    function getAERC6909BYID(uint256 id) external view returns (address);
}
