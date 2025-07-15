// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {BaseImmutableAdminUpgradeabilityProxy} from "./BaseImmutableAdminUpgradeabilityProxy.sol";
import {InitializableUpgradeabilityProxy} from
    "../../../../contracts/dependencies/openzeppelin/upgradeability/InitializableUpgradeabilityProxy.sol";
import {Proxy} from "../../../../contracts/dependencies/openzeppelin/upgradeability/Proxy.sol";

/**
 * @title InitializableAdminUpgradeabilityProxy
 * @author Conclave
 * @notice Proxy contract that combines immutable admin functionality with initialization capabilities.
 * @dev Extends `BaseImmutableAdminUpgradeabilityProxy` with an initializer function for one-time setup.
 * This contract inherits initialization capabilities from `InitializableUpgradeabilityProxy` and admin
 * functionality from `BaseImmutableAdminUpgradeabilityProxy`.
 */
contract InitializableImmutableAdminUpgradeabilityProxy is
    BaseImmutableAdminUpgradeabilityProxy,
    InitializableUpgradeabilityProxy
{
    /**
     * @dev Constructor that sets up the immutable admin address.
     * @param admin The address of the `admin` that will have special privileges.
     */
    constructor(address admin) BaseImmutableAdminUpgradeabilityProxy(admin) {
        // Intentionally left blank.
    }

    /// @inheritdoc BaseImmutableAdminUpgradeabilityProxy
    function _willFallback() internal override(BaseImmutableAdminUpgradeabilityProxy, Proxy) {
        BaseImmutableAdminUpgradeabilityProxy._willFallback();
    }
}
