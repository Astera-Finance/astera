// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.20;

/**
 * @title IAccessManager
 * @notice Interface for the AccessManager contract
 * @dev Manages access control for flashloan operations
 */
interface IAccessManager {
    /**
     * @notice Checks if a user is whitelisted for flashloans
     * @param user The address to check
     * @return bool True if the user is whitelisted, false otherwise
     */
    function isFlashloanWhitelisted(address user) external view returns (bool);

    /**
     * @notice Adds or updates a user's flashloan whitelist status
     * @param user The address to whitelist
     */
    function setFlashloanWhitelistedUser(address user) external;
}
