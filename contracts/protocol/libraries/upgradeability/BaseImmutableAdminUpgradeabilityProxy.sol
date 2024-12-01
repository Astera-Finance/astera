// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {BaseUpgradeabilityProxy} from
    "../../../../contracts/dependencies/openzeppelin/upgradeability/BaseUpgradeabilityProxy.sol";

/**
 * @title BaseImmutableAdminUpgradeabilityProxy
 * @author Aave, inspired by the OpenZeppelin upgradeability proxy pattern
 * @notice This contract combines an upgradeability proxy with an authorization mechanism for administrative tasks.
 * @dev The admin role is stored in an immutable, which helps saving transactions costs.
 * All external functions in this contract must be guarded by the `ifAdmin` modifier.
 * See ethereum/solidity#3864 for a Solidity feature proposal that would enable this to be done automatically.
 */
contract BaseImmutableAdminUpgradeabilityProxy is BaseUpgradeabilityProxy {
    address internal immutable _admin;

    /**
     * @dev Constructor.
     * @param admin The address of the admin.
     */
    constructor(address admin) {
        _admin = admin;
    }

    /**
     * @dev Modifier that checks if the caller is the admin.
     * If caller is admin, execute function.
     * If caller is not admin, delegate call to implementation.
     */
    modifier ifAdmin() {
        if (msg.sender == _admin) {
            _;
        } else {
            _fallback();
        }
    }

    /**
     * @notice Returns the admin address of this proxy.
     * @return The address of the proxy admin.
     */
    function admin() external ifAdmin returns (address) {
        return _admin;
    }

    /**
     * @notice Returns the implementation address of this proxy.
     * @return The address of the implementation.
     */
    function implementation() external ifAdmin returns (address) {
        return _implementation();
    }

    /**
     * @notice Upgrades the implementation address of this proxy.
     * @dev Only the admin can call this function.
     * @param newImplementation The address of the new implementation.
     */
    function upgradeTo(address newImplementation) external ifAdmin {
        _upgradeTo(newImplementation);
    }

    /**
     * @notice Upgrades the implementation and calls a function on the new implementation.
     * @dev This is useful to initialize the proxied contract.
     * @param newImplementation The address of the new implementation.
     * @param data The calldata to delegatecall the new implementation with.
     * It should include the signature and parameters of the function to be called, as described in
     * https://solidity.readthedocs.io/en/v0.4.24/abi-spec.html#function-selector-and-argument-encoding.
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data)
        external
        payable
        ifAdmin
    {
        _upgradeTo(newImplementation);
        (bool success,) = newImplementation.delegatecall(data);
        require(success);
    }

    /**
     * @dev Prevents the admin from calling the fallback function.
     * Only non-admin callers can trigger the proxy fallback.
     */
    function _willFallback() internal virtual override {
        require(msg.sender != _admin, "Cannot call fallback function from the proxy admin");
        super._willFallback();
    }
}
