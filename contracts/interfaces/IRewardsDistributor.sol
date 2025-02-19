// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {DistributionTypes} from "../../contracts/protocol/libraries/types/DistributionTypes.sol";

/**
 * @title IRewardsDistributor interface.
 * @author Cod3x
 */
interface IRewardsDistributor {
    /**
     * @notice Emitted when an asset's reward configuration is updated
     * @param asset The address of the incentivized asset
     * @param reward The address of the reward token
     * @param emission The new emission rate per second
     * @param distributionEnd The new end timestamp of the reward distribution
     */
    event AssetConfigUpdated(
        address indexed asset, address indexed reward, uint256 emission, uint256 distributionEnd
    );

    /**
     * @notice Emitted when an asset's reward index is updated
     * @param asset The address of the incentivized asset
     * @param reward The address of the reward token
     * @param index The new reward index
     */
    event AssetIndexUpdated(address indexed asset, address indexed reward, uint256 index);

    /**
     * @notice Emitted when a user's reward index for an asset is updated
     * @param user The address of the user
     * @param asset The address of the incentivized asset
     * @param reward The address of the reward token
     * @param index The new user reward index
     */
    event UserIndexUpdated(
        address indexed user, address indexed asset, address indexed reward, uint256 index
    );

    /**
     * @notice Emitted when rewards are accrued for a user
     * @param user The address of the user
     * @param reward The address of the reward token
     * @param amount The amount of rewards accrued
     */
    event RewardsAccrued(address indexed user, address indexed reward, uint256 amount);

    function setDistributionEnd(address asset, address reward, uint32 distributionEnd) external;

    function getDistributionEnd(address asset, address reward) external view returns (uint256);

    function getUserAssetData(address user, address asset, address reward)
        external
        view
        returns (uint256);

    function getRewardsData(address asset, address reward)
        external
        view
        returns (uint256, uint256, uint256, uint256);

    function getRewardsByAsset(address asset) external view returns (address[] memory);

    function getRewardTokens() external view returns (address[] memory);

    function getUserUnclaimedRewardsFromStorage(address user, address reward)
        external
        view
        returns (uint256);

    function getUserRewardsBalance(address[] calldata assets, address user, address reward)
        external
        view
        returns (uint256);

    function getAllUserRewardsBalance(address[] calldata assets, address user)
        external
        view
        returns (address[] memory, uint256[] memory);

    function getAssetDecimals(address asset) external view returns (uint8);

    function getIsRewardEnabled(address reward) external view returns (bool);
}
