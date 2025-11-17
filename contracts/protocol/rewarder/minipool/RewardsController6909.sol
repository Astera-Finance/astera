// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {
    IMiniPoolRewardsController
} from "../../../../contracts/interfaces/IMiniPoolRewardsController.sol";
import {RewardsDistributor6909} from "./RewardsDistributor6909.sol";
import {IAERC6909} from "../../../../contracts/interfaces/IAERC6909.sol";
import {
    DistributionTypes
} from "../../../../contracts/protocol/libraries/types/DistributionTypes.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title RewardsController6909
 * @author Conclave
 * @notice Contract to manage rewards distribution for ERC6909 tokens.
 * @dev Abstract contract that inherits from RewardsDistributor6909 and implements IMiniPoolRewardsController.
 */
abstract contract RewardsController6909 is RewardsDistributor6909, IMiniPoolRewardsController {
    /// @dev Mapping from user address to their authorized claimer address.
    mapping(address => address) internal _authorizedClaimers;

    /**
     * @dev Modifier to restrict function access to authorized claimers only.
     * @param claimer The address attempting to claim.
     * @param user The user address whose rewards are being claimed.
     */
    modifier onlyAuthorizedClaimers(address claimer, address user) {
        require(_authorizedClaimers[user] == claimer, Errors.R_CLAIMER_UNAUTHORIZED);
        _;
    }

    /**
     * @dev Constructor that initializes the contract with an owner.
     * @param initialOwner The address to set as the initial owner.
     */
    constructor(address initialOwner) RewardsDistributor6909(initialOwner) {}

    /**
     * @notice Returns the authorized claimer for a specific user.
     * @param user The user address to query.
     * @return The address of the authorized claimer.
     */
    function getClaimer(address user) external view override returns (address) {
        return _authorizedClaimers[user];
    }

    /**
     * @notice Sets an authorized claimer for a user.
     * @param user The user address to set a claimer for.
     * @param caller The address to authorize as claimer.
     */
    function setClaimer(address user, address caller) external override onlyOwner {
        _authorizedClaimers[user] = caller;
        emit ClaimerSet(user, caller);
    }

    /**
     * @notice Configures the reward distribution for multiple assets.
     * @param config Array of reward configuration parameters.
     */
    function configureAssets(DistributionTypes.MiniPoolRewardsConfigInput[] memory config)
        external
        override
        onlyOwner
    {
        _configureAssets(config);
    }

    /**
     * @notice Updates reward state when user balance changes.
     * @param assetID The ID of the asset being updated.
     * @param user The user address whose rewards are being updated.
     * @param totalSupply The total supply of the asset.
     * @param userBalance The user's balance of the asset.
     */
    function handleAction(uint256 assetID, address user, uint256 totalSupply, uint256 userBalance)
        external
        override
    {
        _updateUserRewardsPerAssetInternal(msg.sender, assetID, user, userBalance, totalSupply);
    }

    /**
     * @notice Claims rewards for the caller.
     * @param assets Array of assets to claim rewards from.
     * @param amount Amount of rewards to claim.
     * @param to Address to receive the rewards.
     * @param reward Address of the reward token.
     * @return The amount of rewards claimed.
     */
    function claimRewards(
        DistributionTypes.Asset6909[] calldata assets,
        uint256 amount,
        address to,
        address reward
    ) external override returns (uint256) {
        require(to != address(0), Errors.R_INVALID_ADDRESS);
        return _claimRewards(assets, amount, msg.sender, msg.sender, to, reward);
    }

    /**
     * @notice Claims rewards on behalf of a user.
     * @param assets Array of assets to claim rewards from.
     * @param amount Amount of rewards to claim.
     * @param user Address of the user to claim for.
     * @param to Address to receive the rewards.
     * @param reward Address of the reward token.
     * @return The amount of rewards claimed.
     */
    function claimRewardsOnBehalf(
        DistributionTypes.Asset6909[] calldata assets,
        uint256 amount,
        address user,
        address to,
        address reward
    ) external override onlyAuthorizedClaimers(msg.sender, user) returns (uint256) {
        require(user != address(0), Errors.R_INVALID_ADDRESS);
        require(to != address(0), Errors.R_INVALID_ADDRESS);
        return _claimRewards(assets, amount, msg.sender, user, to, reward);
    }

    /**
     * @notice Claims rewards and sends them to the caller.
     * @param assets Array of assets to claim rewards from.
     * @param amount Amount of rewards to claim.
     * @param reward Address of the reward token.
     * @return The amount of rewards claimed.
     */
    function claimRewardsToSelf(
        DistributionTypes.Asset6909[] calldata assets,
        uint256 amount,
        address reward
    ) external override returns (uint256) {
        return _claimRewards(assets, amount, msg.sender, msg.sender, msg.sender, reward);
    }

    /**
     * @notice Claims all available rewards for multiple assets.
     * @param assets Array of assets to claim rewards from.
     * @param to Address to receive the rewards.
     * @return rewardTokens Array of reward token addresses.
     * @return claimedAmounts Array of claimed amounts corresponding to each reward token.
     */
    function claimAllRewards(DistributionTypes.Asset6909[] calldata assets, address to)
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        require(to != address(0), Errors.R_INVALID_ADDRESS);
        return _claimAllRewards(assets, msg.sender, msg.sender, to);
    }

    /**
     * @notice Claims all rewards on behalf of a user.
     * @param assets Array of assets to claim rewards from.
     * @param user Address of the user to claim for.
     * @param to Address to receive the rewards.
     * @return rewardTokens Array of reward token addresses.
     * @return claimedAmounts Array of claimed amounts corresponding to each reward token.
     */
    function claimAllRewardsOnBehalf(
        DistributionTypes.Asset6909[] calldata assets,
        address user,
        address to
    )
        external
        override
        onlyAuthorizedClaimers(msg.sender, user)
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        require(user != address(0), Errors.R_INVALID_ADDRESS);
        require(to != address(0), Errors.R_INVALID_ADDRESS);
        return _claimAllRewards(assets, msg.sender, user, to);
    }

    /**
     * @notice Claims all rewards and sends them to the caller.
     * @param assets Array of assets to claim rewards from.
     * @return rewardTokens Array of reward token addresses.
     * @return claimedAmounts Array of claimed amounts corresponding to each reward token.
     */
    function claimAllRewardsToSelf(DistributionTypes.Asset6909[] calldata assets)
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        return _claimAllRewards(assets, msg.sender, msg.sender, msg.sender);
    }

    /**
     * @dev Internal function to get user stake information for multiple assets.
     * @param assets Array of assets to get stake information for.
     * @param user Address of the user.
     * @return userState Array containing user stake information for each asset.
     */
    function _getUserStake(DistributionTypes.Asset6909[] calldata assets, address user)
        internal
        view
        override
        returns (DistributionTypes.UserMiniPoolAssetInput[] memory userState)
    {
        userState = new DistributionTypes.UserMiniPoolAssetInput[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            userState[i].asset = assets[i];
            (userState[i].userBalance, userState[i].totalSupply) = IAERC6909(assets[i].market6909)
                .getScaledUserBalanceAndSupply(user, assets[i].assetID);
        }
        return userState;
    }

    /**
     * @dev Internal function to process reward claims.
     * @param assets Array of assets to claim rewards from.
     * @param amount Amount of rewards to claim.
     * @param claimer Address of the claimer.
     * @param user Address of the user.
     * @param to Address to receive the rewards.
     * @param reward Address of the reward token.
     * @return The amount of rewards claimed.
     */
    function _claimRewards(
        DistributionTypes.Asset6909[] calldata assets,
        uint256 amount,
        address claimer,
        address user,
        address to,
        address reward
    ) internal returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        uint256 unclaimedRewards = _usersUnclaimedRewards[user][reward];

        if (amount > unclaimedRewards) {
            _distributeRewards(user, _getUserStake(assets, user));
            unclaimedRewards = _usersUnclaimedRewards[user][reward];
        }

        if (unclaimedRewards == 0) {
            return 0;
        }

        uint256 amountToClaim = amount > unclaimedRewards ? unclaimedRewards : amount;
        _usersUnclaimedRewards[user][reward] = unclaimedRewards - amountToClaim; // Safe due to the previous line

        _transferRewards(to, reward, amountToClaim);
        emit RewardsClaimed(user, reward, to, claimer, amountToClaim);

        return amountToClaim;
    }

    /**
     * @dev Internal function to claim all rewards for multiple assets.
     * @param assets Array of assets to claim rewards from.
     * @param claimer Address of the claimer.
     * @param user Address of the user.
     * @param to Address to receive the rewards.
     * @return rewardTokens Array of reward token addresses.
     * @return claimedAmounts Array of claimed amounts corresponding to each reward token.
     */
    function _claimAllRewards(
        DistributionTypes.Asset6909[] calldata assets,
        address claimer,
        address user,
        address to
    ) internal returns (address[] memory rewardTokens, uint256[] memory claimedAmounts) {
        _distributeRewards(user, _getUserStake(assets, user));

        rewardTokens = new address[](_rewardTokens.length);
        claimedAmounts = new uint256[](_rewardTokens.length);

        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            address reward = _rewardTokens[i];
            uint256 rewardAmount = _usersUnclaimedRewards[user][reward];

            rewardTokens[i] = reward;
            claimedAmounts[i] = rewardAmount;

            if (rewardAmount != 0) {
                _usersUnclaimedRewards[user][reward] = 0;
                _transferRewards(to, reward, rewardAmount);
                emit RewardsClaimed(user, reward, to, claimer, rewardAmount);
            }
        }
        return (rewardTokens, claimedAmounts);
    }

    /**
     * @dev Internal function to transfer rewards.
     * @param to Address to receive the rewards.
     * @param reward Address of the reward token.
     * @param amount Amount of rewards to transfer.
     */
    function _transferRewards(address to, address reward, uint256 amount) internal {
        bool success = __transferRewards(to, reward, amount);
        require(success == true, Errors.R_TRANSFER_ERROR);
    }

    /**
     * @dev Internal virtual function to be implemented by child contracts for reward transfers.
     * @param to Address to receive the rewards.
     * @param reward Address of the reward token.
     * @param amount Amount of rewards to transfer.
     * @return A boolean indicating if the transfer was successful.
     */
    function __transferRewards(address to, address reward, uint256 amount)
        internal
        virtual
        returns (bool);
}
