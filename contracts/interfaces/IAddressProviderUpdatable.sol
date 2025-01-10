// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title IAddressProviderUpdatable interface.
 * @author Cod3x
 */
interface IAddressProviderUpdatable {
    /**
     * @dev Updates the implementation of a mini pool.
     * @param addressProvider The new implementation address.
     */
    function initialize(address addressProvider) external;
}
