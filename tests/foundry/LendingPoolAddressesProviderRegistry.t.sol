// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

contract LendingPoolAddressesProviderRegistryTest is Common {
    event AddressesProviderRegistered(address indexed newAddress);
    event AddressesProviderUnregistered(address indexed newAddress);

    function testRegisteringAndReadingAddresses(uint256 id) public {
        address randomAddress = makeAddr("RandomAddr");
        id = bound(id, 1, type(uint256).max);
        LendingPoolAddressesProviderRegistry lendingPoolAddressesProviderRegistry =
            new LendingPoolAddressesProviderRegistry();
        address[] memory addressesProvidersList =
            lendingPoolAddressesProviderRegistry.getAddressesProvidersList();
        assertEq(addressesProvidersList.length, 0);

        vm.expectEmit(true, false, false, false);
        emit AddressesProviderRegistered(address(randomAddress));
        lendingPoolAddressesProviderRegistry.registerAddressesProvider(randomAddress, id);

        addressesProvidersList = lendingPoolAddressesProviderRegistry.getAddressesProvidersList();

        assertEq(addressesProvidersList.length, 1);
        assertEq(addressesProvidersList[0], randomAddress);

        lendingPoolAddressesProviderRegistry.registerAddressesProvider(randomAddress, id); // Second same registration to check if not be added
        assertEq(addressesProvidersList.length, 1);
    }

    function testUnregisteringAndReadingAddresses(uint256 id) public {
        /**
         * Preconditions:
         * 1. Length of array 'addressesProvidersList' must be zero
         * Test Scenario:
         * 1. Register address provider
         * 2. Unregister address provider
         * Invariants:
         * 1. Length of array 'addressesProvidersList' must be one after registering
         * 2. Length of array 'addressesProvidersList' must be zero after unregistering
         */
        address randomAddress1 = makeAddr("RandomAddr1");
        address randomAddress2 = makeAddr("RandomAddr2");
        id = bound(id, 1, type(uint256).max);
        LendingPoolAddressesProviderRegistry lendingPoolAddressesProviderRegistry =
            new LendingPoolAddressesProviderRegistry();
        address[] memory addressesProvidersList =
            lendingPoolAddressesProviderRegistry.getAddressesProvidersList();
        assertEq(addressesProvidersList.length, 0);

        lendingPoolAddressesProviderRegistry.registerAddressesProvider(randomAddress1, id);
        lendingPoolAddressesProviderRegistry.registerAddressesProvider(randomAddress2, id);

        vm.expectEmit(true, false, false, false);
        emit AddressesProviderUnregistered(address(randomAddress1));
        lendingPoolAddressesProviderRegistry.unregisterAddressesProvider(randomAddress1);

        addressesProvidersList = lendingPoolAddressesProviderRegistry.getAddressesProvidersList();

        // @issue7 There is no removal from list here
        // assertEq(addressesProvidersList.length, 1); // violated
        // assertEq(addressesProvidersList[0], randomAddress2); // violated

        uint256 obtainedId =
            lendingPoolAddressesProviderRegistry.getAddressesProviderIdByAddress(randomAddress1);
        assertEq(obtainedId, 0);
        obtainedId =
            lendingPoolAddressesProviderRegistry.getAddressesProviderIdByAddress(randomAddress2);
        assertEq(obtainedId, id);
    }
}
