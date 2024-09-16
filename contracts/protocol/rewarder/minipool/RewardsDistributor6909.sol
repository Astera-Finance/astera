// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IMiniPoolRewardsDistributor} from "contracts/interfaces/IMiniPoolRewardsDistributor.sol";
import {IERC20Detailed} from "contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {IERC6909} from "contracts/interfaces/IERC6909.sol";
import {DistributionTypes} from "contracts/protocol/rewarder/DistributionTypes.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

abstract contract RewardsDistributor6909 is IMiniPoolRewardsDistributor, Ownable {
    struct RewardData {
        uint88 emissionPerSecond;
        uint104 index;
        uint32 lastUpdateTimestamp;
        uint32 distributionEnd;
        mapping(address => uint256) usersIndex;
    }

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

    constructor(address initialOwner) Ownable(initialOwner) {}

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

    function getDistributionEnd(address market6909, uint256 assetID, address reward)
        external
        view
        override
        returns (uint256)
    {
        return _assets[market6909][assetID].rewards[reward].distributionEnd;
    }

    function getRewardsByAsset(address market6909, uint256 assetID)
        external
        view
        override
        returns (address[] memory)
    {
        return _assets[market6909][assetID].availableRewards;
    }

    function getRewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    function getUserAssetData(address user, address market6909, uint256 assetID, address reward)
        public
        view
        override
        returns (uint256)
    {
        return _assets[market6909][assetID].rewards[reward].usersIndex[user];
    }

    function getUserUnclaimedRewardsFromStorage(address user, address reward)
        external
        view
        override
        returns (uint256)
    {
        return _usersUnclaimedRewards[user][reward];
    }

    function getUserRewardsBalance(
        DistributionTypes.asset6909[] calldata assets,
        address user,
        address reward
    ) external view override returns (uint256) {
        return _getUserReward(user, reward, _getUserStake(assets, user));
    }

    function getAllUserRewardsBalance(DistributionTypes.asset6909[] calldata assets, address user)
        external
        view
        override
        returns (address[] memory rewardTokens, uint256[] memory unclaimedAmounts)
    {
        return _getAllUserRewards(user, _getUserStake(assets, user));
    }

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

    function _configureAssets(DistributionTypes.MiniPoolRewardsConfigInput[] memory rewardsInput)
        internal
    {
        for (uint256 i = 0; i < rewardsInput.length; i++) {
            _assets[rewardsInput[i].asset.market6909][rewardsInput[i].asset.assetID].decimals =
                IERC6909(rewardsInput[i].asset.market6909).decimals(rewardsInput[i].asset.assetID);

            RewardData storage rewardConfig = _assets[rewardsInput[i].asset.market6909][rewardsInput[i]
                .asset
                .assetID].rewards[rewardsInput[i].reward];

            // Add reward address to asset available rewards if latestUpdateTimestamp is zero
            if (rewardConfig.lastUpdateTimestamp == 0) {
                _assets[rewardsInput[i].asset.market6909][rewardsInput[i].asset.assetID]
                    .availableRewards
                    .push(rewardsInput[i].reward);
            }

            // Add reward address to global rewards list if still not enabled
            if (_isRewardEnabled[rewardsInput[i].reward] == false) {
                _isRewardEnabled[rewardsInput[i].reward] = true;
                _rewardTokens.push(rewardsInput[i].reward);
            }

            // Due emissions is still zero, updates only latestUpdateTimestamp
            _updateAssetStateInternal(
                rewardsInput[i].asset.market6909,
                rewardsInput[i].asset.assetID,
                rewardsInput[i].reward,
                rewardConfig,
                rewardsInput[i].totalSupply,
                _assets[rewardsInput[i].asset.market6909][rewardsInput[i].asset.assetID].decimals
            );

            // Configure emission and distribution end of the reward per asset
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
            require(newIndex <= type(uint104).max, "Index overflow");
            //optimization: storing one after another saves one SSTORE
            rewardConfig.index = uint104(newIndex);
            rewardConfig.lastUpdateTimestamp = uint32(block.timestamp);
            emit AssetIndexUpdated(market6909, assetID, reward, newIndex);
        } else {
            rewardConfig.lastUpdateTimestamp = uint32(block.timestamp);
        }

        return newIndex;
    }

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

    function _updateUserRewardsPerAssetInternal(
        address market6909,
        uint256 assetID,
        address user,
        uint256 userBalance,
        uint256 totalSupply
    ) internal {
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

    function _getUserReward(
        address user,
        address reward,
        DistributionTypes.UserMiniPoolAssetInput[] memory userState
    ) internal view returns (uint256 unclaimedRewards) {
        // Add unrealized rewards
        for (uint256 i = 0; i < userState.length; i++) {
            if (userState[i].userBalance == 0) {
                continue;
            }
            unclaimedRewards += _getUnrealizedRewardsFromStake(user, reward, userState[i]);
        }

        // Return unrealized rewards plus stored unclaimed rewardss
        return unclaimedRewards + _usersUnclaimedRewards[user][reward];
    }

    function _getAllUserRewards(
        address user,
        DistributionTypes.UserMiniPoolAssetInput[] memory userState
    ) internal view returns (address[] memory rewardTokens, uint256[] memory unclaimedRewards) {
        rewardTokens = new address[](_rewardTokens.length);
        unclaimedRewards = new uint256[](rewardTokens.length);

        // Add stored rewards from user to unclaimedRewards
        for (uint256 y = 0; y < rewardTokens.length; y++) {
            rewardTokens[y] = _rewardTokens[y];
            unclaimedRewards[y] = _usersUnclaimedRewards[user][rewardTokens[y]];
        }

        // Add unrealized rewards from user to unclaimedRewards
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

    function _getRewards(
        uint256 principalUserBalance,
        uint256 reserveIndex,
        uint256 userIndex,
        uint8 decimals
    ) internal pure returns (uint256) {
        return (principalUserBalance * (reserveIndex - userIndex)) / 10 ** decimals;
    }

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

    function _getUserStake(DistributionTypes.asset6909[] calldata assets, address user)
        internal
        view
        virtual
        returns (DistributionTypes.UserMiniPoolAssetInput[] memory userState);

    function getAssetDecimals(DistributionTypes.asset6909 calldata asset)
        external
        view
        override
        returns (uint8)
    {
        return _assets[asset.market6909][asset.assetID].decimals;
    }
}
