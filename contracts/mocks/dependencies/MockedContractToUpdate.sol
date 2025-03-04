// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {VersionedInitializable} from
    "contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";

import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";

contract MockedContractToUpdate is VersionedInitializable {
    IMiniPoolAddressesProvider addressesProvider;

    uint256 internal constant REVISION = 0x2;

    function getRevision() internal pure override returns (uint256) {
        return REVISION;
    }

    function initialize(IMiniPoolAddressesProvider provider) public initializer {
        addressesProvider = provider;
    }

    function initialize(IMiniPoolAddressesProvider provider, uint256 id) public initializer {
        addressesProvider = provider;
    }
}
