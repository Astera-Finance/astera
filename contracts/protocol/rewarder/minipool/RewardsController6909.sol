// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IMiniPoolRewardsController} from
    "../../../../contracts/interfaces/IMiniPoolRewardsController.sol";
import {RewardsDistributor6909} from "./RewardsDistributor6909.sol";
import {IAERC6909} from "../../../../contracts/interfaces/IAERC6909.sol";
import {DistributionTypes} from
    "../../../../contracts/protocol/libraries/types/DistributionTypes.sol";

/**
 * @title RewardsController6909
 * @author Cod3x
 */
abstract contract RewardsController6909 is RewardsDistributor6909, IMiniPoolRewardsController {
    // user => authorized claimer
    mapping(address => address) internal _authorizedClaimers;

    modifier onlyAuthorizedClaimers(address claimer, address user) {
        require(_authorizedClaimers[user] == claimer, "CLAIMER_UNAUTHORIZED");
        _;
    }

    constructor(address initialOwner) RewardsDistributor6909(initialOwner) {}

    function getClaimer(address user) external view override returns (address) {
        return _authorizedClaimers[user];
    }

    function setClaimer(address user, address caller) external override onlyOwner {
        _authorizedClaimers[user] = caller;
        emit ClaimerSet(user, caller);
    }

    function configureAssets(DistributionTypes.MiniPoolRewardsConfigInput[] memory config)
        external
        override
        onlyOwner
    {
        for (uint256 i = 0; i < config.length; i++) {
            //fix Token Configuration
            config[i].totalSupply =
                IAERC6909(config[i].asset.market6909).scaledTotalSupply(config[i].asset.assetID);
        }
        _configureAssets(config);
    }

    function handleAction(uint256 assetID, address user, uint256 totalSupply, uint256 userBalance)
        external
        override
    {
        _updateUserRewardsPerAssetInternal(msg.sender, assetID, user, userBalance, totalSupply);
    }

    function claimRewards(
        DistributionTypes.Asset6909[] calldata assets,
        uint256 amount,
        address to,
        address reward
    ) external override returns (uint256) {
        require(to != address(0), "INVALID_TO_ADDRESS");
        return _claimRewards(assets, amount, msg.sender, msg.sender, to, reward);
    }

    function claimRewardsOnBehalf(
        DistributionTypes.Asset6909[] calldata assets,
        uint256 amount,
        address user,
        address to,
        address reward
    ) external override onlyAuthorizedClaimers(msg.sender, user) returns (uint256) {
        require(user != address(0), "INVALID_USER_ADDRESS");
        require(to != address(0), "INVALID_TO_ADDRESS");
        return _claimRewards(assets, amount, msg.sender, user, to, reward);
    }

    function claimRewardsToSelf(
        DistributionTypes.Asset6909[] calldata assets,
        uint256 amount,
        address reward
    ) external override returns (uint256) {
        return _claimRewards(assets, amount, msg.sender, msg.sender, msg.sender, reward);
    }

    function claimAllRewards(DistributionTypes.Asset6909[] calldata assets, address to)
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        require(to != address(0), "INVALID_TO_ADDRESS");
        return _claimAllRewards(assets, msg.sender, msg.sender, to);
    }

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
        require(user != address(0), "INVALID_USER_ADDRESS");
        require(to != address(0), "INVALID_TO_ADDRESS");
        return _claimAllRewards(assets, msg.sender, user, to);
    }

    function claimAllRewardsToSelf(DistributionTypes.Asset6909[] calldata assets)
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        return _claimAllRewards(assets, msg.sender, msg.sender, msg.sender);
    }

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

    function _transferRewards(address to, address reward, uint256 amount) internal {
        bool success = transferRewards(to, reward, amount);
        require(success == true, "TRANSFER_ERROR");
    }

    function transferRewards(address to, address reward, uint256 amount)
        internal
        virtual
        returns (bool);
}
