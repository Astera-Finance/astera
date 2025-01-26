// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IRewardsDistributor} from "../../contracts/interfaces/IRewardsDistributor.sol";
import {DistributionTypes} from "../../contracts/protocol/libraries/types/DistributionTypes.sol";

/**
 * @title IRewardsController interface.
 * @author Cod3x
 */
interface IRewardsController is IRewardsDistributor {
    /**
     * @notice Emitted when rewards are claimed
     * @param user The address of the user receiving rewards
     * @param reward The address of the reward token
     * @param to The address receiving the claimed rewards
     * @param claimer The address that initiated the claim
     * @param amount The amount of rewards claimed
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
     * @param claimer The address authorized to claim on behalf of the user
     */
    event ClaimerSet(address indexed user, address indexed claimer);

    /**
     * @notice Emitted when the rewards vault is updated
     * @param vault The address of the new rewards vault
     */
    event RewardsVaultUpdated(address indexed vault);

    /**
     * @notice Emitted when the mini pool addresses provider is set
     * @param addressesProvider The address of the new mini pool addresses provider
     */
    event MiniPoolAddressesProviderSet(address indexed addressesProvider);

    /**
     * @notice Emitted when the reward forwarder is set
     * @param forwarder The address of the new reward forwarder
     */
    event RewardForwarderSet(address indexed forwarder);

    function setClaimer(address user, address claimer) external;

    function getClaimer(address user) external view returns (address);

    function getMiniPoolAddressesProvider() external view returns (address);

    function configureAssets(DistributionTypes.RewardsConfigInput[] memory config) external;

    function handleAction(address asset, uint256 userBalance, uint256 totalSupply) external;

    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward)
        external
        returns (uint256);

    function claimRewardsOnBehalf(
        address[] calldata assets,
        uint256 amount,
        address user,
        address to,
        address reward
    ) external returns (uint256);

    function claimRewardsToSelf(address[] calldata assets, uint256 amount, address reward)
        external
        returns (uint256);

    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    function claimAllRewardsOnBehalf(address[] calldata assets, address user, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    function claimAllRewardsToSelf(address[] calldata assets)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}
