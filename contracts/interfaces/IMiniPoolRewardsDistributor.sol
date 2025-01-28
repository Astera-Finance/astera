// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {DistributionTypes} from "../../contracts/protocol/libraries/types/DistributionTypes.sol";

/**
 * @title IMiniPoolRewardsDistributor interface.
 * @author Cod3x
 */
interface IMiniPoolRewardsDistributor {
    /**
     * @notice Emitted when an asset's reward configuration is updated
     * @param market6909 The address of the market6909 contract
     * @param assetID The ID of the asset in the market6909
     * @param reward The address of the reward token
     * @param emission The emission per second of rewards
     * @param distributionEnd The unix timestamp when the reward distribution ends
     */
    event AssetConfigUpdated(
        address indexed market6909,
        uint256 assetID,
        address indexed reward,
        uint256 emission,
        uint256 distributionEnd
    );

    /**
     * @notice Emitted when an asset's reward index is updated
     * @param market6909 The address of the market6909 contract
     * @param assetID The ID of the asset in the market6909
     * @param reward The address of the reward token
     * @param index The new index value
     */
    event AssetIndexUpdated(
        address indexed market6909, uint256 assetID, address indexed reward, uint256 index
    );

    /**
     * @notice Emitted when a user's reward index for an asset is updated
     * @param user The address of the user
     * @param market6909 The address of the market6909 contract
     * @param assetID The ID of the asset in the market6909
     * @param reward The address of the reward token
     * @param index The new index value
     */
    event UserIndexUpdated(
        address indexed user,
        address indexed market6909,
        uint256 assetID,
        address indexed reward,
        uint256 index
    );

    /**
     * @notice Emitted when new total supply threshold is set
     * @param decimals Number of decimals that are the subject of threshold
     * @param threshold The total supply amount of the threshold
     */
    event TotalSupplyThresholdSet(uint8 indexed decimals, uint256 indexed threshold);

    /**
     * @notice Emitted when rewards are accrued for a user
     * @param user The address of the user receiving rewards
     * @param reward The address of the reward token
     * @param amount The amount of rewards accrued
     */
    event RewardsAccrued(address indexed user, address indexed reward, uint256 amount);

    function setDistributionEnd(
        address market6909,
        uint256 assetID,
        address reward,
        uint32 distributionEnd
    ) external;

    function getDistributionEnd(address market6909, uint256 assetID, address reward)
        external
        view
        returns (uint256);

    function getUserAssetData(address user, address market6909, uint256 assetID, address reward)
        external
        view
        returns (uint256);

    function getRewardsData(address market6909, uint256 assetID, address reward)
        external
        view
        returns (uint256, uint256, uint256, uint256);

    function getRewardsByAsset(address market6909, uint256 assetID)
        external
        view
        returns (address[] memory);

    function getRewardTokens() external view returns (address[] memory);

    function getUserUnclaimedRewardsFromStorage(address user, address reward)
        external
        view
        returns (uint256);

    function getUserRewardsBalance(
        DistributionTypes.Asset6909[] calldata assets,
        address user,
        address reward
    ) external view returns (uint256);

    function getAllUserRewardsBalance(DistributionTypes.Asset6909[] calldata assets, address user)
        external
        view
        returns (address[] memory, uint256[] memory);

    function getAssetDecimals(DistributionTypes.Asset6909 calldata asset)
        external
        view
        returns (uint8);
}
