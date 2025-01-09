// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IRewardsDistributor} from "../../../../contracts/interfaces/IRewardsDistributor.sol";
import {IERC20Detailed} from
    "../../../../contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {DistributionTypes} from
    "../../../../contracts/protocol/libraries/types/DistributionTypes.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title RewardsDistributor
 * @author Cod3x
 * @notice Contract for managing and distributing rewards to users based on their asset balances.
 * @dev Abstract contract that inherits from IRewardsDistributor and Ownable.
 */
abstract contract RewardsDistributor is IRewardsDistributor, Ownable {
    /**
     * @dev Struct containing reward distribution data for a specific reward token.
     * @param emissionPerSecond Rate at which rewards are distributed per second.
     * @param index Current reward index for the asset.
     * @param lastUpdateTimestamp Last time the reward distribution was updated.
     * @param distributionEnd Timestamp when reward distribution ends.
     * @param usersIndex Mapping of user addresses to their reward index.
     */
    struct RewardData {
        uint88 emissionPerSecond;
        uint104 index;
        uint32 lastUpdateTimestamp;
        uint32 distributionEnd;
        mapping(address => uint256) usersIndex;
    }

    /**
     * @dev Struct containing asset-specific reward distribution data.
     * @param rewards Mapping of reward token addresses to their RewardData.
     * @param availableRewards Array of available reward token addresses.
     * @param decimals Number of decimals for the asset.
     */
    struct AssetData {
        // reward => rewardData
        mapping(address => RewardData) rewards;
        mapping(address => uint256) initialIndexes;
        address[] availableRewards;
        uint8 decimals;
    }

    // incentivized asset => AssetData
    mapping(address => AssetData) internal _assets;

    // user => reward => unclaimed rewards
    mapping(address => mapping(address => uint256)) internal _usersUnclaimedRewards;

    // reward => isEnabled
    mapping(address => bool) internal _isRewardEnabled;

    address[] internal _rewardTokens;

    /**
     * @dev Constructor that sets the initial owner of the contract.
     * @param initialOwner Address to be set as the contract owner.
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice Retrieves reward distribution data for a specific asset and reward token.
     * @param asset The address of the asset.
     * @param reward The address of the reward token.
     * @return Current reward index.
     * @return Current emission rate per second.
     * @return Last update timestamp.
     * @return Distribution end timestamp.
     */
    function getRewardsData(address asset, address reward)
        public
        view
        override
        returns (uint256, uint256, uint256, uint256)
    {
        return (
            _assets[asset].rewards[reward].index,
            _assets[asset].rewards[reward].emissionPerSecond,
            _assets[asset].rewards[reward].lastUpdateTimestamp,
            _assets[asset].rewards[reward].distributionEnd
        );
    }

    /**
     * @notice Gets the distribution end timestamp for a specific asset and reward.
     * @param asset The address of the asset.
     * @param reward The address of the reward token.
     * @return The timestamp when distribution ends.
     */
    function getDistributionEnd(address asset, address reward)
        external
        view
        override
        returns (uint256)
    {
        return _assets[asset].rewards[reward].distributionEnd;
    }

    /**
     * @notice Gets all available reward tokens for a specific asset.
     * @param asset The address of the asset.
     * @return Array of reward token addresses.
     */
    function getRewardsByAsset(address asset) external view override returns (address[] memory) {
        return _assets[asset].availableRewards;
    }

    /**
     * @notice Gets all reward tokens supported by the contract.
     * @return Array of reward token addresses.
     */
    function getRewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /**
     * @notice Gets the user's index for a specific asset and reward.
     * @param user The address of the user.
     * @param asset The address of the asset.
     * @param reward The address of the reward token.
     * @return The user's reward index.
     */
    function getUserAssetData(address user, address asset, address reward)
        public
        view
        override
        returns (uint256)
    {
        return _assets[asset].rewards[reward].usersIndex[user];
    }

    /**
     * @notice Gets the user's unclaimed rewards from storage.
     * @param user The address of the user.
     * @param reward The address of the reward token.
     * @return Amount of unclaimed rewards.
     */
    function getUserUnclaimedRewardsFromStorage(address user, address reward)
        external
        view
        override
        returns (uint256)
    {
        return _usersUnclaimedRewards[user][reward];
    }

    /**
     * @notice Gets the user's rewards balance for a specific reward token across multiple assets.
     * @param assets Array of asset addresses.
     * @param user The address of the user.
     * @param reward The address of the reward token.
     * @return Total unclaimed rewards.
     */
    function getUserRewardsBalance(address[] calldata assets, address user, address reward)
        external
        view
        override
        returns (uint256)
    {
        return _getUserReward(user, reward, _getUserStake(assets, user));
    }

    /**
     * @notice Gets all reward balances for a user across multiple assets.
     * @param assets Array of asset addresses.
     * @param user The address of the user.
     * @return rewardTokens Array of reward token addresses.
     * @return unclaimedAmounts Array of unclaimed amounts for each reward token.
     */
    function getAllUserRewardsBalance(address[] calldata assets, address user)
        external
        view
        override
        returns (address[] memory rewardTokens, uint256[] memory unclaimedAmounts)
    {
        return _getAllUserRewards(user, _getUserStake(assets, user));
    }

    /**
     * @notice Sets the distribution end timestamp for a specific asset and reward.
     * @param asset The address of the asset.
     * @param reward The address of the reward token.
     * @param distributionEnd The new distribution end timestamp.
     */
    function setDistributionEnd(address asset, address reward, uint32 distributionEnd)
        external
        override
        onlyOwner
    {
        _assets[asset].rewards[reward].distributionEnd = distributionEnd;

        emit AssetConfigUpdated(
            asset, reward, _assets[asset].rewards[reward].emissionPerSecond, distributionEnd
        );
    }

    /**
     * @notice Configures reward distribution parameters for multiple assets.
     * @param rewardsInput Array of reward configuration parameters.
     */
    function _configureAssets(DistributionTypes.RewardsConfigInput[] memory rewardsInput)
        internal
    {
        for (uint256 i = 0; i < rewardsInput.length; i++) {
            _assets[rewardsInput[i].asset].decimals =
                IERC20Detailed(rewardsInput[i].asset).decimals();

            RewardData storage rewardConfig =
                _assets[rewardsInput[i].asset].rewards[rewardsInput[i].reward];

            // Add reward address to asset available rewards if `latestUpdateTimestamp` is zero.
            if (rewardConfig.lastUpdateTimestamp == 0) {
                _assets[rewardsInput[i].asset].availableRewards.push(rewardsInput[i].reward);
            }

            // Add reward address to global rewards list if still not enabled.
            if (_isRewardEnabled[rewardsInput[i].reward] == false) {
                _isRewardEnabled[rewardsInput[i].reward] = true;
                _rewardTokens.push(rewardsInput[i].reward);
            }

            // Due emissions is still zero, updates only `latestUpdateTimestamp`.
            _updateAssetStateInternal(
                rewardsInput[i].asset,
                rewardsInput[i].reward,
                rewardConfig,
                rewardsInput[i].totalSupply,
                _assets[rewardsInput[i].asset].decimals
            );

            // Configure emission and distribution end of the reward per asset.
            rewardConfig.emissionPerSecond = rewardsInput[i].emissionPerSecond;
            rewardConfig.distributionEnd = rewardsInput[i].distributionEnd;

            emit AssetConfigUpdated(
                rewardsInput[i].asset,
                rewardsInput[i].reward,
                rewardsInput[i].emissionPerSecond,
                rewardsInput[i].distributionEnd
            );
        }
    }

    /**
     * @notice Updates the reward state for an asset.
     * @param asset The address of the asset.
     * @param reward The address of the reward token.
     * @param rewardConfig Storage pointer to the reward configuration.
     * @param totalSupply Total supply of the asset.
     * @param decimals Decimals of the asset.
     * @return The new asset index.
     */
    function _updateAssetStateInternal(
        address asset,
        address reward,
        RewardData storage rewardConfig,
        uint256 totalSupply,
        uint8 decimals
    ) internal returns (uint256) {
        uint256 oldIndex = rewardConfig.index;

        if (block.timestamp == rewardConfig.lastUpdateTimestamp) {
            return oldIndex;
        }

        uint256 newIndex = _getAssetIndex(
            oldIndex,
            rewardConfig.emissionPerSecond,
            rewardConfig.lastUpdateTimestamp,
            rewardConfig.distributionEnd,
            totalSupply,
            decimals
        );

        if (newIndex != oldIndex) {
            require(newIndex <= type(uint104).max, "Index overflow");
            //optimization: storing one after another saves one SSTORE
            rewardConfig.index = uint104(newIndex);
            rewardConfig.lastUpdateTimestamp = uint32(block.timestamp);
            emit AssetIndexUpdated(asset, reward, newIndex);
        } else {
            rewardConfig.lastUpdateTimestamp = uint32(block.timestamp);
        }

        return newIndex;
    }

    /**
     * @notice Updates rewards for a user for a specific asset and reward token.
     * @param user The address of the user.
     * @param asset The address of the asset.
     * @param reward The address of the reward token.
     * @param userBalance User's balance of the asset.
     * @param totalSupply Total supply of the asset.
     * @return Amount of accrued rewards.
     */
    function _updateUserRewardsInternal(
        address user,
        address asset,
        address reward,
        uint256 userBalance,
        uint256 totalSupply
    ) internal returns (uint256) {
        RewardData storage rewardData = _assets[asset].rewards[reward];
        uint256 userIndex = rewardData.usersIndex[user];
        uint256 accruedRewards = 0;

        uint256 newIndex = _updateAssetStateInternal(
            asset, reward, rewardData, totalSupply, _assets[asset].decimals
        );

        if (userIndex != newIndex) {
            if (userBalance != 0) {
                accruedRewards =
                    _getRewards(userBalance, newIndex, userIndex, _assets[asset].decimals);
            }

            rewardData.usersIndex[user] = newIndex;
            emit UserIndexUpdated(user, asset, reward, newIndex);
        }

        return accruedRewards;
    }

    /**
     * @notice Updates rewards for a user for all reward tokens of an asset.
     * @param asset The address of the asset.
     * @param user The address of the user.
     * @param userBalance User's balance of the asset.
     * @param totalSupply Total supply of the asset.
     */
    function _updateUserRewardsPerAssetInternal(
        address asset,
        address user,
        uint256 userBalance,
        uint256 totalSupply
    ) internal {
        for (uint256 r = 0; r < _assets[asset].availableRewards.length; r++) {
            address reward = _assets[asset].availableRewards[r];
            uint256 accruedRewards =
                _updateUserRewardsInternal(user, asset, reward, userBalance, totalSupply);
            if (accruedRewards != 0) {
                _usersUnclaimedRewards[user][reward] += accruedRewards;

                emit RewardsAccrued(user, reward, accruedRewards);
            }
        }
    }

    /**
     * @notice Distributes rewards for a user across multiple assets.
     * @param user The address of the user.
     * @param userState Array of user asset input data.
     */
    function _distributeRewards(address user, DistributionTypes.UserAssetInput[] memory userState)
        internal
    {
        for (uint256 i = 0; i < userState.length; i++) {
            _updateUserRewardsPerAssetInternal(
                userState[i].underlyingAsset,
                user,
                userState[i].userBalance,
                userState[i].totalSupply
            );
        }
    }

    /**
     * @notice Gets the total rewards for a user for a specific reward token.
     * @param user The address of the user.
     * @param reward The address of the reward token.
     * @param userState Array of user asset input data.
     * @return unclaimedRewards Total unclaimed rewards.
     */
    function _getUserReward(
        address user,
        address reward,
        DistributionTypes.UserAssetInput[] memory userState
    ) internal view returns (uint256 unclaimedRewards) {
        // Add unrealized rewards.
        for (uint256 i = 0; i < userState.length; i++) {
            if (userState[i].userBalance == 0) {
                continue;
            }
            unclaimedRewards += _getUnrealizedRewardsFromStake(user, reward, userState[i]);
        }

        // Return unrealized rewards plus stored unclaimed rewards.
        return unclaimedRewards + _usersUnclaimedRewards[user][reward];
    }

    /**
     * @notice Gets all rewards for a user across all reward tokens.
     * @param user The address of the user.
     * @param userState Array of user asset input data.
     * @return rewardTokens Array of reward token addresses.
     * @return unclaimedRewards Array of unclaimed amounts for each reward token.
     */
    function _getAllUserRewards(address user, DistributionTypes.UserAssetInput[] memory userState)
        internal
        view
        returns (address[] memory rewardTokens, uint256[] memory unclaimedRewards)
    {
        rewardTokens = new address[](_rewardTokens.length);
        unclaimedRewards = new uint256[](rewardTokens.length);

        // Add stored rewards from user to `unclaimedRewards`.
        for (uint256 y = 0; y < rewardTokens.length; y++) {
            rewardTokens[y] = _rewardTokens[y];
            unclaimedRewards[y] = _usersUnclaimedRewards[user][rewardTokens[y]];
        }

        // Add unrealized rewards from user to `unclaimedRewards`.
        for (uint256 i = 0; i < userState.length; i++) {
            if (userState[i].userBalance == 0) {
                continue;
            }
            for (uint256 r = 0; r < rewardTokens.length; r++) {
                unclaimedRewards[r] +=
                    _getUnrealizedRewardsFromStake(user, rewardTokens[r], userState[i]);
            }
        }
        return (rewardTokens, unclaimedRewards);
    }

    /**
     * @notice Calculates unrealized rewards for a user's stake.
     * @param user The address of the user.
     * @param reward The address of the reward token.
     * @param stake The user's stake data.
     * @return Amount of unrealized rewards.
     */
    function _getUnrealizedRewardsFromStake(
        address user,
        address reward,
        DistributionTypes.UserAssetInput memory stake
    ) internal view returns (uint256) {
        RewardData storage rewardData = _assets[stake.underlyingAsset].rewards[reward];
        uint8 assetDecimals = _assets[stake.underlyingAsset].decimals;
        uint256 assetIndex = _getAssetIndex(
            rewardData.index,
            rewardData.emissionPerSecond,
            rewardData.lastUpdateTimestamp,
            rewardData.distributionEnd,
            stake.totalSupply,
            assetDecimals
        );

        return
            _getRewards(stake.userBalance, assetIndex, rewardData.usersIndex[user], assetDecimals);
    }

    /**
     * @notice Calculates rewards based on principal balance and index difference.
     * @param principalUserBalance User's principal balance.
     * @param reserveIndex Current reserve index.
     * @param userIndex User's stored index.
     * @param decimals Number of decimals.
     * @return Amount of rewards.
     */
    function _getRewards(
        uint256 principalUserBalance,
        uint256 reserveIndex,
        uint256 userIndex,
        uint8 decimals
    ) internal pure returns (uint256) {
        return (principalUserBalance * (reserveIndex - userIndex)) / 10 ** decimals;
    }

    /**
     * @notice Calculates the current asset index based on emission parameters.
     * @param currentIndex Current index value.
     * @param emissionPerSecond Rate of emission per second.
     * @param lastUpdateTimestamp Last update timestamp.
     * @param distributionEnd Distribution end timestamp.
     * @param totalBalance Total balance of the asset.
     * @param decimals Number of decimals.
     * @return New asset index.
     */
    function _getAssetIndex(
        uint256 currentIndex,
        uint256 emissionPerSecond,
        uint128 lastUpdateTimestamp,
        uint256 distributionEnd,
        uint256 totalBalance,
        uint8 decimals
    ) internal view returns (uint256) {
        if (
            emissionPerSecond == 0 || totalBalance == 0 || lastUpdateTimestamp == block.timestamp
                || lastUpdateTimestamp >= distributionEnd
        ) {
            return currentIndex;
        }

        uint256 currentTimestamp =
            block.timestamp > distributionEnd ? distributionEnd : block.timestamp;
        uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;
        return (emissionPerSecond * timeDelta * (10 ** decimals)) / totalBalance + currentIndex;
    }

    /**
     * @notice Gets the user's stake data for multiple assets.
     * @param assets Array of asset addresses.
     * @param user The address of the user.
     * @return userState Array of user asset input data.
     */
    function _getUserStake(address[] calldata assets, address user)
        internal
        view
        virtual
        returns (DistributionTypes.UserAssetInput[] memory userState);

    /**
     * @notice Gets the decimals of an asset.
     * @param asset The address of the asset.
     * @return Number of decimals.
     */
    function getAssetDecimals(address asset) external view override returns (uint8) {
        return _assets[asset].decimals;
    }

    /**
     * @notice Gets the status of a reward token.
     * @param reward The address of the reward token.
     * @return Status of the reward token.
     */
    function getIsRewardEnabled(address reward) external view override returns (bool) {
        return _isRewardEnabled[reward];
    }
}
