// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title IMiniPoolAddressProviderUpdatable interface.
 * @author Cod3x
 */
interface IMiniPoolAddressProviderUpdatable {
    /**
     * @dev Updates the implementation of a mini pool.
     * @param addressProvider The new implementation address.
     * @param miniPoolId The ID of the mini pool to update.
     */
    function initialize(address addressProvider, uint256 miniPoolId) external;
}
