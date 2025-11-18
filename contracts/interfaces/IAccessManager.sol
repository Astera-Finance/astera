// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.20;

/**
 * @title IAccessManager
 * @notice Interface for the AccessManager contract
 * @dev Manages access control for flashloan operations
 */
interface IAccessManager {
    /**
     * @notice Emitted when a user is added to the flashloan whitelist
     * @param user The address of the user being whitelisted
     */
    event UserWhitelisted(address indexed user);

    /**
     * @notice Emitted when a user is removed from the flashloan whitelist
     * @param user The address of the user being removed
     */
    event UserRemovedFromWhitelist(address indexed user);

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
    function addUserToFlashloanWhitelist(address user) external;
}
