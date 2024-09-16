// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {DistributionTypes} from "contracts/protocol/libraries/types/DistributionTypes.sol";

interface IMiniPoolRewardsDistributor {
    event AssetConfigUpdated(
        address indexed market6909,
        uint256 assetID,
        address indexed reward,
        uint256 emission,
        uint256 distributionEnd
    );
    event AssetIndexUpdated(
        address indexed market6909, uint256 assetID, address indexed reward, uint256 index
    );
    event UserIndexUpdated(
        address indexed user,
        address indexed market6909,
        uint256 assetID,
        address indexed reward,
        uint256 index
    );

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
        DistributionTypes.asset6909[] calldata assets,
        address user,
        address reward
    ) external view returns (uint256);

    function getAllUserRewardsBalance(DistributionTypes.asset6909[] calldata assets, address user)
        external
        view
        returns (address[] memory, uint256[] memory);

    function getAssetDecimals(DistributionTypes.asset6909 calldata asset)
        external
        view
        returns (uint8);
}
