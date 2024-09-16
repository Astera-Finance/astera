// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IMiniPoolRewardsDistributor} from "./IMiniPoolRewardsDistributor.sol";
import {DistributionTypes} from "../libraries/DistributionTypes.sol";

interface IMiniPoolRewardsController is IMiniPoolRewardsDistributor {
    event RewardsClaimed(
        address indexed user,
        address indexed reward,
        address indexed to,
        address claimer,
        uint256 amount
    );

    event ClaimerSet(address indexed user, address indexed claimer);

    function setClaimer(address user, address claimer) external;

    function getClaimer(address user) external view returns (address);

    function configureAssets(DistributionTypes.MiniPoolRewardsConfigInput[] memory config) external;

    function handleAction(uint256 assetID, address user, uint256 totalSupply, uint256 userBalance) external;

    function claimRewards(DistributionTypes.asset6909[] calldata assets, uint256 amount, address to, address reward)
        external
        returns (uint256);

    function claimRewardsOnBehalf(
        DistributionTypes.asset6909[] calldata assets,
        uint256 amount,
        address user,
        address to,
        address reward
    ) external returns (uint256);

    function claimRewardsToSelf(DistributionTypes.asset6909[] calldata assets, uint256 amount, address reward)
        external
        returns (uint256);

    function claimAllRewards(DistributionTypes.asset6909[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    function claimAllRewardsOnBehalf(DistributionTypes.asset6909[] calldata assets, address user, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    function claimAllRewardsToSelf(DistributionTypes.asset6909[] calldata assets)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}
