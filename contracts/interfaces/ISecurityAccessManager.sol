// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.20;

/**
 * @title ISecurityAccessManager
 * @notice Interface for the AccessManager contract
 * @dev Manages access control for flashloan operations
 */
interface ISecurityAccessManager {
    struct DepositCheckpoints {
        uint208 depositAmount; // inUSD
        uint48 depositTime;
    }

    struct UserRegister {
        mapping(address => DepositCheckpoints[]) depositCheckpoints;
        // DepositCheckpoints[] depositCheckpoints;
        uint16 trustPoints;
    }

    struct LevelParams {
        uint208 maxDeposit;
        uint32 cooldownTime;
        uint16 trustPointsThreshold;
    }

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

    event LevelsSet(
        uint32[] indexed cooldownTimes,
        uint208[] indexed maxDeposits,
        uint16[] indexed trustPointsThresholds
    );

    event DepositRegistered(
        address indexed asset, uint208 indexed amount, uint48 indexed timestamp
    );

    event DepositUnregistered(
        address indexed asset, uint208 indexed amount, uint48 indexed timestamp
    );

    event TrustPointsChanged(address indexed user, uint16 amount);

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
