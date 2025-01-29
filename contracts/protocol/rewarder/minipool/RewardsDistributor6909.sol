// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IMiniPoolRewardsDistributor} from
    "../../../../contracts/interfaces/IMiniPoolRewardsDistributor.sol";
import {IAERC6909} from "../../../../contracts/interfaces/IAERC6909.sol";
import {DistributionTypes} from
    "../../../../contracts/protocol/libraries/types/DistributionTypes.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title RewardsDistributor6909
 * @author Cod3x
 * @notice Abstract contract for distributing rewards to ERC6909 token holders.
 * @dev Implements core reward distribution logic and state management.
 */
abstract contract RewardsDistributor6909 is IMiniPoolRewardsDistributor, Ownable {
    /**
     * @dev Struct containing reward distribution data for a specific reward token.
     * @param emissionPerSecond Rate at which rewards are distributed per second.
     * @param index Current reward index for the asset.
     * @param lastUpdateTimestamp Last time the reward distribution was updated.
     * @param distributionEnd Timestamp when reward distribution ends.
     * @param usersIndex Mapping of user addresses to their reward index.
     */
    struct RewardData {
        uint192 emissionPerSecond;
        uint256 index;
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
        address[] availableRewards;
        uint8 decimals;
    }

    // incentivized Market6909 => asset id => AssetData
    mapping(address => mapping(uint256 => AssetData)) internal _assets;

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
     * @param market6909 The address of the ERC6909 market contract.
     * @param assetID The ID of the asset.
     * @param reward The address of the reward token.
     * @return index Current reward index.
     * @return emissionPerSecond Current emission rate per second.
     * @return lastUpdateTimestamp Last update timestamp.
     * @return distributionEnd Distribution end timestamp.
     */
    function getRewardsData(address market6909, uint256 assetID, address reward)
        public
        view
        override
        returns (uint256, uint256, uint256, uint256)
    {
        return (
            _assets[market6909][assetID].rewards[reward].index,
            _assets[market6909][assetID].rewards[reward].emissionPerSecond,
            _assets[market6909][assetID].rewards[reward].lastUpdateTimestamp,
            _assets[market6909][assetID].rewards[reward].distributionEnd
        );
    }

    /**
     * @notice Gets the distribution end timestamp for a specific asset and reward.
     * @param market6909 The address of the ERC6909 market contract.
     * @param assetID The ID of the asset.
     * @param reward The address of the reward token.
     * @return The timestamp when distribution ends.
     */
    function getDistributionEnd(address market6909, uint256 assetID, address reward)
        external
        view
        override
        returns (uint256)
    {
        return _assets[market6909][assetID].rewards[reward].distributionEnd;
    }

    /**
     * @notice Gets all available reward tokens for a specific asset.
     * @param market6909 The address of the ERC6909 market contract.
     * @param assetID The ID of the asset.
     * @return Array of reward token addresses.
     */
    function getRewardsByAsset(address market6909, uint256 assetID)
        external
        view
        override
        returns (address[] memory)
    {
        return _assets[market6909][assetID].availableRewards;
    }

    /**
     * @notice Gets all reward tokens supported by the distributor.
     * @return Array of reward token addresses.
     */
    function getRewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /**
     * @notice Gets the reward index for a specific user and asset.
     * @param user The user address.
     * @param market6909 The address of the ERC6909 market contract.
     * @param assetID The ID of the asset.
     * @param reward The address of the reward token.
     * @return The user's reward index.
     */
    function getUserAssetData(address user, address market6909, uint256 assetID, address reward)
        public
        view
        override
        returns (uint256)
    {
        return _assets[market6909][assetID].rewards[reward].usersIndex[user];
    }

    /**
     * @notice Gets the unclaimed rewards amount stored for a user.
     * @param user The user address.
     * @param reward The reward token address.
     * @return The amount of unclaimed rewards.
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
     * @notice Calculates the total rewards balance for a user for a specific reward token.
     * @param assets Array of asset data.
     * @param user The user address.
     * @param reward The reward token address.
     * @return The total rewards balance.
     */
    function getUserRewardsBalance(
        DistributionTypes.Asset6909[] calldata assets,
        address user,
        address reward
    ) external view override returns (uint256) {
        return _getUserReward(user, reward, _getUserStake(assets, user));
    }

    /**
     * @notice Gets all unclaimed reward balances for a user across all reward tokens.
     * @param assets Array of asset data.
     * @param user The user address.
     * @return rewardTokens Array of reward token addresses.
     * @return unclaimedAmounts Array of unclaimed amounts corresponding to each reward token.
     */
    function getAllUserRewardsBalance(DistributionTypes.Asset6909[] calldata assets, address user)
        external
        view
        override
        returns (address[] memory rewardTokens, uint256[] memory unclaimedAmounts)
    {
        return _getAllUserRewards(user, _getUserStake(assets, user));
    }

    /**
     * @notice Sets the distribution end timestamp for a specific asset and reward.
     * @param market6909 The address of the ERC6909 market contract.
     * @param assetID The ID of the asset.
     * @param reward The reward token address.
     * @param distributionEnd The new distribution end timestamp.
     */
    function setDistributionEnd(
        address market6909,
        uint256 assetID,
        address reward,
        uint32 distributionEnd
    ) external override onlyOwner {
        _assets[market6909][assetID].rewards[reward].distributionEnd = distributionEnd;

        emit AssetConfigUpdated(
            market6909,
            assetID,
            reward,
            _assets[market6909][assetID].rewards[reward].emissionPerSecond,
            distributionEnd
        );
    }

    /**
     * @dev Internal function to configure reward distribution parameters for multiple assets.
     * @param rewardsInput Array of reward configuration inputs.
     */
    function _configureAssets(DistributionTypes.MiniPoolRewardsConfigInput[] memory rewardsInput)
        internal
    {
        for (uint256 i = 0; i < rewardsInput.length; i++) {
            _assets[rewardsInput[i].asset.market6909][rewardsInput[i].asset.assetID].decimals =
                IAERC6909(rewardsInput[i].asset.market6909).decimals(rewardsInput[i].asset.assetID);

            RewardData storage rewardConfig = _assets[rewardsInput[i].asset.market6909][rewardsInput[i]
                .asset
                .assetID].rewards[rewardsInput[i].reward];

            // Add reward address to asset available rewards if latestUpdateTimestamp is zero.
            if (rewardConfig.lastUpdateTimestamp == 0) {
                _assets[rewardsInput[i].asset.market6909][rewardsInput[i].asset.assetID]
                    .availableRewards
                    .push(rewardsInput[i].reward);
            }

            // Add reward address to global rewards list if still not enabled.
            if (_isRewardEnabled[rewardsInput[i].reward] == false) {
                _isRewardEnabled[rewardsInput[i].reward] = true;
                _rewardTokens.push(rewardsInput[i].reward);
            }

            // Due emissions is still zero, updates only latestUpdateTimestamp.
            _updateAssetStateInternal(
                rewardsInput[i].asset.market6909,
                rewardsInput[i].asset.assetID,
                rewardsInput[i].reward,
                rewardConfig,
                IAERC6909(rewardsInput[i].asset.market6909).scaledTotalSupply(
                    rewardsInput[i].asset.assetID
                ),
                _assets[rewardsInput[i].asset.market6909][rewardsInput[i].asset.assetID].decimals
            );

            // Configure emission and distribution end of the reward per asset.
            rewardConfig.emissionPerSecond = rewardsInput[i].emissionPerSecond;
            rewardConfig.distributionEnd = rewardsInput[i].distributionEnd;

            emit AssetConfigUpdated(
                rewardsInput[i].asset.market6909,
                rewardsInput[i].asset.assetID,
                rewardsInput[i].reward,
                rewardsInput[i].emissionPerSecond,
                rewardsInput[i].distributionEnd
            );
        }
    }

    /**
     * @dev Updates the reward state for an asset.
     * @param market6909 The ERC6909 market contract address.
     * @param assetID The asset identifier.
     * @param reward The reward token address.
     * @param rewardConfig Storage pointer to reward configuration.
     * @param totalSupply Total supply of the asset.
     * @param decimals Decimals of the asset.
     * @return The new reward index.
     */
    function _updateAssetStateInternal(
        address market6909,
        uint256 assetID,
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
            rewardConfig.index = newIndex;
            rewardConfig.lastUpdateTimestamp = uint32(block.timestamp);
            emit AssetIndexUpdated(market6909, assetID, reward, newIndex);
        } else {
            rewardConfig.lastUpdateTimestamp = uint32(block.timestamp);
        }

        return newIndex;
    }

    /**
     * @dev Updates rewards for a specific user.
     * @param user The user address.
     * @param market6909 The ERC6909 market contract address.
     * @param assetID The asset identifier.
     * @param reward The reward token address.
     * @param userBalance User's balance of the asset.
     * @param totalSupply Total supply of the asset.
     * @return The amount of accrued rewards.
     */
    function _updateUserRewardsInternal(
        address user,
        address market6909,
        uint256 assetID,
        address reward,
        uint256 userBalance,
        uint256 totalSupply
    ) internal returns (uint256) {
        RewardData storage rewardData = _assets[market6909][assetID].rewards[reward];
        uint256 userIndex = rewardData.usersIndex[user];
        uint256 accruedRewards = 0;
        uint8 assetDecimals = _assets[market6909][assetID].decimals;

        uint256 newIndex = _updateAssetStateInternal(
            market6909, assetID, reward, rewardData, totalSupply, assetDecimals
        );
        if (userIndex != newIndex) {
            if (userBalance != 0) {
                accruedRewards = _getRewards(userBalance, newIndex, userIndex, assetDecimals);
            }

            rewardData.usersIndex[user] = newIndex;
            emit UserIndexUpdated(user, market6909, assetID, reward, newIndex);
        }

        return accruedRewards;
    }

    /**
     * @dev Updates rewards for a user across all reward tokens for a specific asset.
     * @param market6909 The ERC6909 market contract address.
     * @param assetID The asset identifier.
     * @param user The user address.
     * @param userBalance User's balance of the asset.
     * @param totalSupply Total supply of the asset.
     */
    function _updateUserRewardsPerAssetInternal(
        address market6909,
        uint256 assetID,
        address user,
        uint256 userBalance,
        uint256 totalSupply
    ) internal {
        require(
            address(IAERC6909(market6909).getIncentivesController()) != address(0),
            "Rewarder not set for market6909"
        );
        for (uint256 r = 0; r < _assets[market6909][assetID].availableRewards.length; r++) {
            address reward = _assets[market6909][assetID].availableRewards[r];
            uint256 accruedRewards = _updateUserRewardsInternal(
                user, market6909, assetID, reward, userBalance, totalSupply
            );
            if (accruedRewards != 0) {
                _usersUnclaimedRewards[user][reward] += accruedRewards;

                emit RewardsAccrued(user, reward, accruedRewards);
            }
        }
    }

    /**
     * @dev Distributes rewards for a user across multiple assets.
     * @param user The user address.
     * @param userState Array of user asset state data.
     */
    function _distributeRewards(
        address user,
        DistributionTypes.UserMiniPoolAssetInput[] memory userState
    ) internal {
        for (uint256 i = 0; i < userState.length; i++) {
            _updateUserRewardsPerAssetInternal(
                userState[i].asset.market6909,
                userState[i].asset.assetID,
                user,
                userState[i].userBalance,
                userState[i].totalSupply
            );
        }
    }

    /**
     * @dev Calculates total rewards for a user for a specific reward token.
     * @param user The user address.
     * @param reward The reward token address.
     * @param userState Array of user asset state data.
     * @return unclaimedRewards Total unclaimed rewards.
     */
    function _getUserReward(
        address user,
        address reward,
        DistributionTypes.UserMiniPoolAssetInput[] memory userState
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
     * @dev Calculates all unclaimed rewards for a user.
     * @param user The user address.
     * @param userState Array of user asset state data.
     * @return rewardTokens Array of reward token addresses.
     * @return unclaimedRewards Array of unclaimed reward amounts.
     */
    function _getAllUserRewards(
        address user,
        DistributionTypes.UserMiniPoolAssetInput[] memory userState
    ) internal view returns (address[] memory rewardTokens, uint256[] memory unclaimedRewards) {
        rewardTokens = new address[](_rewardTokens.length);
        unclaimedRewards = new uint256[](rewardTokens.length);

        // Add stored rewards from user to unclaimedRewards.
        for (uint256 y = 0; y < rewardTokens.length; y++) {
            rewardTokens[y] = _rewardTokens[y];
            unclaimedRewards[y] = _usersUnclaimedRewards[user][rewardTokens[y]];
        }

        // Add unrealized rewards from user to unclaimedRewards.
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
     * @dev Calculates unrealized rewards for a specific stake.
     * @param user The user address.
     * @param reward The reward token address.
     * @param stake The stake data.
     * @return The amount of unrealized rewards.
     */
    function _getUnrealizedRewardsFromStake(
        address user,
        address reward,
        DistributionTypes.UserMiniPoolAssetInput memory stake
    ) internal view returns (uint256) {
        RewardData storage rewardData =
            _assets[stake.asset.market6909][stake.asset.assetID].rewards[reward];
        uint8 assetDecimals = _assets[stake.asset.market6909][stake.asset.assetID].decimals;
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
     * @dev Calculates rewards based on principal balance and index difference.
     * @param principalUserBalance User's principal balance.
     * @param reserveIndex Current reserve index.
     * @param userIndex User's stored index.
     * @param decimals Number of decimals.
     * @return The calculated reward amount.
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
     * @dev Calculates the current asset index based on emission parameters.
     * @param currentIndex Current index value.
     * @param emissionPerSecond Rate of emission per second.
     * @param lastUpdateTimestamp Last update timestamp.
     * @param distributionEnd Distribution end timestamp.
     * @param totalBalance Total balance of the asset.
     * @param decimals Number of decimals.
     * @return The calculated asset index.
     */
    function _getAssetIndex(
        uint256 currentIndex,
        uint256 emissionPerSecond,
        uint128 lastUpdateTimestamp,
        uint256 distributionEnd,
        uint256 totalBalance,
        uint8 decimals
    ) internal view returns (uint256) {
        // emissionPerSecond equal 1 leads to 0 accrued rewards due to rounding down
        if (
            emissionPerSecond <= 1 || totalBalance == 0 || lastUpdateTimestamp == block.timestamp
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
     * @dev Gets the stake data for a user across multiple assets.
     * @param assets Array of asset data.
     * @param user The user address.
     * @return userState Array of user asset state data.
     */
    function _getUserStake(DistributionTypes.Asset6909[] calldata assets, address user)
        internal
        view
        virtual
        returns (DistributionTypes.UserMiniPoolAssetInput[] memory userState);

    /**
     * @notice Gets the number of decimals for a specific asset.
     * @param asset The asset data.
     * @return The number of decimals.
     */
    function getAssetDecimals(DistributionTypes.Asset6909 calldata asset)
        external
        view
        override
        returns (uint8)
    {
        return _assets[asset.market6909][asset.assetID].decimals;
    }
}
