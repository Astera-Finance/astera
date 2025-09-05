// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../DeployDataTypes.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";

import "forge-std/console.sol";

contract TransferOwnershipHelper {
    address constant FOUNDRY_DEFAULT = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    DeployedContracts contracts;

    function _transferMiniPoolOwnership(MiniPoolRole memory miniPoolRole) internal {
        IMiniPool mp =
            IMiniPool(contracts.miniPoolAddressesProvider.getMiniPool(miniPoolRole.miniPoolId));
        contracts.miniPoolConfigurator.setMinipoolOwnerTreasuryToMiniPool(
            miniPoolRole.poolOwnerTreasury, mp
        );
        contracts.miniPoolConfigurator.setPoolAdmin(miniPoolRole.newPoolOwner, mp);
    }

    function _transferOwnershipsAndRenounceRoles(Roles memory roles) internal {
        console.log("Transfer admin to:");
        console.log(roles.poolAdmin);
        console.log(roles.emergencyAdmin);
        console.log(roles.addressesProviderOwner);
        console.log(roles.oracleOwner);
        console.log(roles.dataProviderOwner);
        console.log(roles.piInterestStrategiesOwner);

        if (
            contracts.lendingPoolAddressesProvider.getPoolAdmin() == msg.sender
                && contracts.lendingPoolAddressesProvider.getPoolAdmin() != roles.poolAdmin
        ) {
            contracts.lendingPoolAddressesProvider.setPoolAdmin(roles.poolAdmin);
        }
        if (
            contracts.wethGateway.owner() == msg.sender
                && contracts.wethGateway.owner() != roles.poolAdmin
        ) {
            contracts.wethGateway.transferOwnership(roles.poolAdmin);
        }
        if (
            contracts.lendingPoolAddressesProvider.owner() == msg.sender
                && contracts.lendingPoolAddressesProvider.getEmergencyAdmin() != roles.emergencyAdmin
        ) {
            contracts.lendingPoolAddressesProvider.setEmergencyAdmin(roles.emergencyAdmin);
        }
        if (
            contracts.lendingPoolAddressesProvider.owner() == msg.sender
                && contracts.lendingPoolAddressesProvider.owner() != roles.addressesProviderOwner
        ) {
            contracts.lendingPoolAddressesProvider.transferOwnership(roles.addressesProviderOwner);
        }
        if (address(contracts.miniPoolAddressesProvider) != address(0)) {
            if (
                contracts.miniPoolAddressesProvider.owner() == msg.sender
                    && contracts.miniPoolAddressesProvider.owner() != roles.addressesProviderOwner
            ) {
                contracts.miniPoolAddressesProvider.transferOwnership(roles.addressesProviderOwner);
            }
        }
        if (address(0) != address(contracts.rewarder)) {
            if (
                contracts.rewarder.owner() == msg.sender
                    && contracts.rewarder.owner() != roles.rewarderOwner
            ) {
                contracts.rewarder.transferOwnership(roles.rewarderOwner);
            }
        }
        if (address(0) != address(contracts.rewarder6909)) {
            if (
                contracts.rewarder6909.owner() == msg.sender
                    && contracts.rewarder6909.owner() != roles.rewarderOwner
            ) {
                contracts.rewarder6909.transferOwnership(roles.rewarderOwner);
            }
        }
        if (contracts.oracle.owner() == msg.sender && contracts.oracle.owner() != roles.oracleOwner)
        {
            contracts.oracle.transferOwnership(roles.oracleOwner);
        }
        if (
            contracts.asteraDataProvider.owner() == msg.sender
                && contracts.asteraDataProvider.owner() != roles.dataProviderOwner
        ) {
            contracts.asteraDataProvider.transferOwnership(roles.dataProviderOwner);
        }

        for (uint256 idx = 0; idx < contracts.piStrategies.length; idx++) {
            if (address(contracts.piStrategies[idx]) != address(0)) {
                if (
                    contracts.piStrategies[idx].owner() == msg.sender
                        && contracts.piStrategies[idx].owner() != roles.piInterestStrategiesOwner
                ) {
                    contracts.piStrategies[idx].transferOwnership(roles.piInterestStrategiesOwner);
                }
            }
        }
        for (uint256 idx = 0; idx < contracts.miniPoolPiStrategies.length; idx++) {
            if (address(contracts.miniPoolPiStrategies[idx]) != address(0)) {
                if (
                    contracts.miniPoolPiStrategies[idx].owner() == msg.sender
                        && contracts.miniPoolPiStrategies[idx].owner()
                            != roles.piInterestStrategiesOwner
                ) {
                    contracts.miniPoolPiStrategies[idx].transferOwnership(
                        roles.piInterestStrategiesOwner
                    );
                }
            }
        }
    }
}
