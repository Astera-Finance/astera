// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IRewardsController} from "contracts/interfaces/IRewardsController.sol";
import {RewardsDistributor} from "./RewardsDistributor.sol";
import {IScaledBalanceToken} from "contracts/interfaces/IScaledBalanceToken.sol";
import {DistributionTypes} from "contracts/protocol/libraries/types/DistributionTypes.sol";
import {IAERC6909} from "contracts/interfaces/IAERC6909.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";

/**
 * @title RewardsController
 * @author Cod3x
 */
abstract contract RewardsController is RewardsDistributor, IRewardsController {
    // user => authorized claimer
    mapping(address => address) internal _authorizedClaimers;
    IMiniPoolAddressesProvider internal _addressesProvider;
    mapping(address => bool) internal _isAtokenERC6909;
    mapping(address => bool) internal _isMiniPool;
    //aToken => ERC6909 => last Reported (totalSupply(ID) - balanceOf(ERC6909))
    mapping(address => mapping(address => uint256)) internal lastReportedDiff;
    uint256 internal _totalDiff;
    uint256 internal _totalTrackedMiniPools;
    address public rewardForwarder;

    modifier onlyAuthorizedClaimers(address claimer, address user) {
        require(_authorizedClaimers[user] == claimer, "CLAIMER_UNAUTHORIZED");
        _;
    }

    constructor(address initialOwner) RewardsDistributor(initialOwner) {}

    function setMiniPoolAddressesProvider(address addressesProvider) external onlyOwner {
        _addressesProvider = IMiniPoolAddressesProvider(addressesProvider);
    }

    function setRewardForwarder(address forwarder) external onlyOwner {
        if (rewardForwarder != address(0)) {
            rewardForwarder = forwarder;
        } else {
            rewardForwarder = forwarder;
            for (uint256 i = 0; i < _totalTrackedMiniPools; i++) {
                address miniPool = _addressesProvider.getMiniPool(i);
                setDefaultForwarder(miniPool);
                address aToken6909 = _addressesProvider.getMiniPoolToAERC6909(miniPool);
                setDefaultForwarder(aToken6909);
            }
        }
    }

    function getClaimer(address user) external view override returns (address) {
        return _authorizedClaimers[user];
    }

    function setClaimer(address user, address caller) external override onlyOwner {
        _authorizedClaimers[user] = caller;
        emit ClaimerSet(user, caller);
    }

    function configureAssets(DistributionTypes.RewardsConfigInput[] memory config)
        external
        override
        onlyOwner
    {
        for (uint256 i = 0; i < config.length; i++) {
            config[i].totalSupply = IScaledBalanceToken(config[i].asset).scaledTotalSupply();
        }
        _configureAssets(config);
    }

    function handleAction(address user, uint256 totalSupply, uint256 userBalance)
        external
        override
    {
        refreshMiniPoolData();
        //if user is an ERC6909 aToken, this will only be true for aTokens
        if (_isAtokenERC6909[user] == true) {
            (uint256 assetID,,) = IAERC6909(user).getIdForUnderlying(msg.sender);
            //for trancheATokens we calculate the total supply of the AERC6909 ID for the assetID
            //we subtract the current balance
            uint256 totalSupplyAsset = IAERC6909(user).scaledTotalSupply(assetID);
            uint256 diff = totalSupplyAsset - userBalance;
            _totalDiff = _totalDiff - lastReportedDiff[msg.sender][user] + diff;
            lastReportedDiff[msg.sender][user] = diff;
            userBalance = totalSupplyAsset;
        }
        _updateUserRewardsPerAssetInternal(msg.sender, user, userBalance, totalSupply + _totalDiff);
    }

    function refreshMiniPoolData() internal {
        if (address(_addressesProvider) != address(0)) {
            if (_totalTrackedMiniPools != _addressesProvider.getMiniPoolCount()) {
                for (
                    uint256 i = _totalTrackedMiniPools;
                    i < _addressesProvider.getMiniPoolCount();
                    i++
                ) {
                    address miniPool = _addressesProvider.getMiniPool(i);
                    _isMiniPool[miniPool] = true;
                    setDefaultForwarder(miniPool);
                    address aToken6909 = _addressesProvider.getMiniPoolToAERC6909(miniPool);
                    _isAtokenERC6909[aToken6909] = true;
                    setDefaultForwarder(aToken6909);
                    _totalTrackedMiniPools++;
                }
            }
        }
    }

    function setDefaultForwarder(address claimee) internal {
        if (rewardForwarder != address(0)) {
            _authorizedClaimers[claimee] = rewardForwarder;
            emit ClaimerSet(claimee, rewardForwarder);
        }
    }

    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward)
        external
        override
        returns (uint256)
    {
        require(to != address(0), "INVALID_TO_ADDRESS");
        return _claimRewards(assets, amount, msg.sender, msg.sender, to, reward);
    }

    function claimRewardsOnBehalf(
        address[] calldata assets,
        uint256 amount,
        address user,
        address to,
        address reward
    ) external override onlyAuthorizedClaimers(msg.sender, user) returns (uint256) {
        require(user != address(0), "INVALID_USER_ADDRESS");
        require(to != address(0), "INVALID_TO_ADDRESS");
        return _claimRewards(assets, amount, msg.sender, user, to, reward);
    }

    function claimRewardsToSelf(address[] calldata assets, uint256 amount, address reward)
        external
        override
        returns (uint256)
    {
        return _claimRewards(assets, amount, msg.sender, msg.sender, msg.sender, reward);
    }

    function claimAllRewards(address[] calldata assets, address to)
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        require(to != address(0), "INVALID_TO_ADDRESS");
        return _claimAllRewards(assets, msg.sender, msg.sender, to);
    }

    function claimAllRewardsOnBehalf(address[] calldata assets, address user, address to)
        external
        override
        onlyAuthorizedClaimers(msg.sender, user)
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        require(user != address(0), "INVALID_USER_ADDRESS");
        require(to != address(0), "INVALID_TO_ADDRESS");
        return _claimAllRewards(assets, msg.sender, user, to);
    }

    function claimAllRewardsToSelf(address[] calldata assets)
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        return _claimAllRewards(assets, msg.sender, msg.sender, msg.sender);
    }

    function _getUserStake(address[] calldata assets, address user)
        internal
        view
        override
        returns (DistributionTypes.UserAssetInput[] memory userState)
    {
        userState = new DistributionTypes.UserAssetInput[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            userState[i].underlyingAsset = assets[i];
            (userState[i].userBalance, userState[i].totalSupply) =
                IScaledBalanceToken(assets[i]).getScaledUserBalanceAndSupply(user);
        }
        return userState;
    }

    function _claimRewards(
        address[] calldata assets,
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

    function _claimAllRewards(address[] calldata assets, address claimer, address user, address to)
        internal
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
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
