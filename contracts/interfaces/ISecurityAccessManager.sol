// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.20;

/**
 * @title ISecurityAccessManager
 * @notice Interface for the SecurityAccessManager contract
 * @dev Manages access control, trust points, and deposit levels for users
 */
interface ISecurityAccessManager {
    struct DepositCheckpoints {
        uint208 depositAmount; // inUSD
        uint48 depositTime;
    }

    struct UserRegister {
        mapping(address => DepositCheckpoints[]) depositCheckpoints;
        uint16 trustPoints;
    }

    struct LevelParams {
        uint208 maxDeposit;
        uint32 cooldownTime;
        uint16 trustPointsThreshold;
    }

    /**
     * @notice Emitted when level parameters are set for an asset
     * @param cooldownTimes Array of cooldown times for each level
     * @param maxDeposits Array of maximum deposits for each level
     * @param trustPointsThresholds Array of trust points thresholds for each level
     */
    event LevelsSet(
        uint32[] indexed cooldownTimes,
        uint208[] indexed maxDeposits,
        uint16[] indexed trustPointsThresholds
    );

    /**
     * @notice Emitted when a deposit is registered
     * @param asset The address of the asset
     * @param amount The deposit amount in USD (8 decimals)
     * @param timestamp The time of deposit registration
     */
    event DepositRegistered(
        address indexed asset, uint208 indexed amount, uint48 indexed timestamp
    );

    /**
     * @notice Emitted when a deposit is unregistered
     * @param asset The address of the asset
     * @param amount The unregistered amount in USD (8 decimals)
     * @param timestamp The time of deposit unregistration
     */
    event DepositUnregistered(
        address indexed asset, uint208 indexed amount, uint48 indexed timestamp
    );

    /**
     * @notice Emitted when trust points are changed for a user
     * @param user The address of the user
     * @param amount The new trust points amount
     */
    event TrustPointsChanged(address indexed user, uint16 amount);

    /**
     *
     * @param asset The address of the asset
     * @param level The level index
     * @param cooldownTime Time in seconds for cooldown
     * @param maxDeposit Maximum deposit in USD (8 decimals)
     * @param trustPointsThreshold Trust points threshold for the level
     */
    event LevelParamsChanged(
        address indexed asset,
        uint256 indexed level,
        uint32 cooldownTime,
        uint208 maxDeposit,
        uint16 trustPointsThreshold
    );

    /**
     * @notice Sets level parameters for a specific asset
     * @param _cooldownTimes Array of cooldown times for each level in seconds
     * @param _maxDeposits Array of max deposits for specific assets in 8 decimals
     * @param _trustPointsThresholds Array of trust points thresholds for each level
     * @param _asset Address of the asset
     */
    function setLevelParams(
        uint32[] memory _cooldownTimes,
        uint208[] memory _maxDeposits,
        uint16[] memory _trustPointsThresholds,
        address _asset
    ) external;

    /**
     * @notice Increases trust points for a user
     * @param user The address of the user
     * @param amount The amount to increase
     */
    function increaseTrustPoints(address user, uint16 amount) external;

    /**
     * @notice Decreases trust points for a user
     * @param user The address of the user
     * @param amount The amount to decrease
     */
    function decreaseTrustPoints(address user, uint16 amount) external;

    /**
     * @notice Registers a deposit for the caller
     * @param _amount The deposit amount in USD (8 decimals)
     * @param _user The address of the user
     */
    function registerDeposit(uint208 _amount, address _user) external;

    /**
     * @notice Unregisters a deposit for the caller
     * @param _amount The amount to unregister in USD (8 decimals)
     * @param _user The address of the user
     */
    function unregisterDeposit(uint208 _amount, address _user) external;

    /**
     * @notice Gets the user level based on trust points for a specific asset
     * @param _user The address of the user
     * @param _asset The address of the asset
     * @return uint8 The user's level (0 being the lowest)
     */
    function getUserLevel(address _user, address _asset) external view returns (uint8);

    /**
     * @notice Gets the liquid funds available for a user (deposits past cooldown)
     * @param _user The address of the user
     * @param _asset The address of the asset
     * @return uint256 The amount of liquid funds
     */
    function getLiquidFunds(address _user, address _asset) external view returns (uint256);

    /**
     * @notice Gets all funds (liquid and locked) for a user
     * @param _user The address of the user
     * @param _asset The address of the asset
     * @return uint256 The total amount of all funds
     */
    function getAllFunds(address _user, address _asset) external view returns (uint256);

    /**
     * @notice Gets the deposit checkpoints for a user
     * @param _user The address of the user
     * @param _asset The address of the asset
     * @return DepositCheckpoints[] Array of deposit checkpoints
     */
    function getUserTrustPoints(address _user, address _asset)
        external
        view
        returns (DepositCheckpoints[] memory);

    /**
     * @notice Gets the trust points balance for a user
     * @param _user The address of the user
     * @return uint256 The trust points amount
     */
    function getUserDepositCheckpoints(address _user) external view returns (uint256);

    /**
     * @notice Gets the level parameters for an asset
     * @param _asset The address of the asset
     * @return LevelParams[] Array of level parameters
     */
    function getLevelParams(address _asset) external view returns (LevelParams[] memory);

    /**
     * @notice Gets the maximum deposit amount in original token decimals
     * @param _userLevel The user's level
     * @param _asset The address of the asset
     * @return uint256 The maximum deposit in original decimals
     */
    function getMaxDepositInOriginDecimals(uint256 _userLevel, address _asset)
        external
        view
        returns (uint256);
}
