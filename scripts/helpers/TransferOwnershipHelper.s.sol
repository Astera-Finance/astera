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
        contracts.lendingPoolAddressesProvider.setPoolAdmin(roles.poolAdmin);
        contracts.aTokensAndRatesHelper.transferOwnership(roles.poolAdmin);
        contracts.wethGateway.transferOwnership(roles.poolAdmin);
        contracts.lendingPoolAddressesProvider.setEmergencyAdmin(roles.emergencyAdmin);
        contracts.lendingPoolAddressesProvider.transferOwnership(roles.addressesProviderOwner);
        contracts.miniPoolAddressesProvider.transferOwnership(roles.addressesProviderOwner);
        contracts.rewarder.transferOwnership(roles.rewarderOwner);
        contracts.rewarder6909.transferOwnership(roles.rewarderOwner);
        contracts.oracle.transferOwnership(roles.oracleOwner);
        contracts.cod3xLendDataProvider.transferOwnership(roles.dataProviderOwner);

        for (uint256 idx = 0; idx < contracts.piStrategies.length; idx++) {
            contracts.piStrategies[idx].transferOwnership(roles.piInterestStrategiesOwner);
        }
        for (uint256 idx = 0; idx < contracts.miniPoolPiStrategies.length; idx++) {
            contracts.miniPoolPiStrategies[idx].transferOwnership(roles.piInterestStrategiesOwner);
        }
    }
}
