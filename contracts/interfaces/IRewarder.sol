// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title IRewarder interface.
 * @author Conclave
 */
interface IRewarder {
    /**
     * @notice Emitted when rewards are accrued for a user
     * @param user The address of the user for whom rewards are being accrued
     * @param amount The amount of rewards accrued
     */
    event RewardsAccrued(address indexed user, uint256 amount);

    /**
     * @notice Emitted when rewards are claimed by a user
     * @param user The address of the user claiming rewards
     * @param to The address receiving the claimed rewards
     * @param amount The amount of rewards claimed
     */
    event RewardsClaimed(address indexed user, address indexed to, uint256 amount);

    /**
     * @notice Emitted when rewards are claimed on behalf of a user
     * @param user The address of the user for whom rewards are claimed
     * @param to The address receiving the claimed rewards
     * @param claimer The address that initiated the claim
     * @param amount The amount of rewards claimed
     */
    event RewardsClaimed(
        address indexed user, address indexed to, address indexed claimer, uint256 amount
    );

    /**
     * @notice Emitted when a claimer is set for a user
     * @param user The address of the user
     * @param claimer The address authorized to claim on behalf of the user
     */
    event ClaimerSet(address indexed user, address indexed claimer);

    function getAssetData(address asset) external view returns (uint256, uint256, uint256);

    function assets(address asset) external view returns (uint128, uint128, uint256);

    function setClaimer(address user, address claimer) external;

    function getClaimer(address user) external view returns (address);

    function configureAssets(address[] calldata assets, uint256[] calldata emissionsPerSecond)
        external;

    function handleAction(address asset, uint256 userBalance, uint256 totalSupply) external;

    function getRewardsBalance(address[] calldata assets, address user)
        external
        view
        returns (uint256);

    function claimRewards(address[] calldata assets, uint256 amount, address to)
        external
        returns (uint256);

    function claimRewardsOnBehalf(
        address[] calldata assets,
        uint256 amount,
        address user,
        address to
    ) external returns (uint256);

    function getUserUnclaimedRewards(address user) external view returns (uint256);

    function getUserAssetData(address user, address asset) external view returns (uint256);

    function REWARD_TOKEN() external view returns (address);

    function PRECISION() external view returns (uint8);

    function DISTRIBUTION_END() external view returns (uint256);
}
