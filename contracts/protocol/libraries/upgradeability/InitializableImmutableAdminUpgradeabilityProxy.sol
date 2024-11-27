// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {BaseImmutableAdminUpgradeabilityProxy} from "./BaseImmutableAdminUpgradeabilityProxy.sol";
import {InitializableUpgradeabilityProxy} from
    "../../../../contracts/dependencies/openzeppelin/upgradeability/InitializableUpgradeabilityProxy.sol";
import {Proxy} from "../../../../contracts/dependencies/openzeppelin/upgradeability/Proxy.sol";

/**
 * @title InitializableAdminUpgradeabilityProxy
 * @author Cod3x
 * @dev Extends BaseAdminUpgradeabilityProxy with an initializer function
 */
contract InitializableImmutableAdminUpgradeabilityProxy is
    BaseImmutableAdminUpgradeabilityProxy,
    InitializableUpgradeabilityProxy
{
    /**
     * @dev Constructor.
     * @param admin The address of the admin
     */
    constructor(address admin) BaseImmutableAdminUpgradeabilityProxy(admin) {
        // Intentionally left blank
    }

    /// @inheritdoc BaseImmutableAdminUpgradeabilityProxy
    function _willFallback() internal override(BaseImmutableAdminUpgradeabilityProxy, Proxy) {
        BaseImmutableAdminUpgradeabilityProxy._willFallback();
    }
}
