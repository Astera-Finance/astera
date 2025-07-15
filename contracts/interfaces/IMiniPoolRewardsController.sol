// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IMiniPoolRewardsDistributor} from
    "../../contracts/interfaces/IMiniPoolRewardsDistributor.sol";
import {DistributionTypes} from "../../contracts/protocol/libraries/types/DistributionTypes.sol";

/**
 * @title IMiniPoolRewardsController interface.
 * @author Conclave
 */
interface IMiniPoolRewardsController is IMiniPoolRewardsDistributor {
    /**
     * @notice Emitted when rewards are claimed
     * @param user The address of the user rewards are being claimed for
     * @param reward The reward token being claimed
     * @param to The address receiving the claimed rewards
     * @param claimer The address executing the claim
     * @param amount The amount of rewards being claimed
     */
    event RewardsClaimed(
        address indexed user,
        address indexed reward,
        address indexed to,
        address claimer,
        uint256 amount
    );

    /**
     * @notice Emitted when a claimer is set for a user
     * @param user The address of the user
     * @param claimer The address being set as the claimer
     */
    event ClaimerSet(address indexed user, address indexed claimer);

    /**
     * @notice Emitted when the rewards vault is updated
     * @param vault The new vault address
     */
    event RewardsVaultUpdated(address indexed vault);

    function setClaimer(address user, address claimer) external;

    function getClaimer(address user) external view returns (address);

    function configureAssets(DistributionTypes.MiniPoolRewardsConfigInput[] memory config)
        external;

    function handleAction(uint256 assetID, address user, uint256 totalSupply, uint256 userBalance)
        external;

    function claimRewards(
        DistributionTypes.Asset6909[] calldata assets,
        uint256 amount,
        address to,
        address reward
    ) external returns (uint256);

    function claimRewardsOnBehalf(
        DistributionTypes.Asset6909[] calldata assets,
        uint256 amount,
        address user,
        address to,
        address reward
    ) external returns (uint256);

    function claimRewardsToSelf(
        DistributionTypes.Asset6909[] calldata assets,
        uint256 amount,
        address reward
    ) external returns (uint256);

    function claimAllRewards(DistributionTypes.Asset6909[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    function claimAllRewardsOnBehalf(
        DistributionTypes.Asset6909[] calldata assets,
        address user,
        address to
    ) external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    function claimAllRewardsToSelf(DistributionTypes.Asset6909[] calldata assets)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}
