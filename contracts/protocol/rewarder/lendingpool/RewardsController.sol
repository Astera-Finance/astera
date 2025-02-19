// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IRewardsController} from "../../../../contracts/interfaces/IRewardsController.sol";
import {RewardsDistributor} from "./RewardsDistributor.sol";
import {IScaledBalanceToken} from "../../../../contracts/interfaces/base/IScaledBalanceToken.sol";
import {DistributionTypes} from
    "../../../../contracts/protocol/libraries/types/DistributionTypes.sol";
import {IAERC6909} from "../../../../contracts/interfaces/IAERC6909.sol";
import "../../../../contracts/interfaces/IAToken.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title RewardsController
 * @author Cod3x
 * @notice Contract to manage rewards distribution and claiming.
 * @dev Abstract contract that inherits from RewardsDistributor and implements IRewardsController.
 */
abstract contract RewardsController is RewardsDistributor, IRewardsController {
    /// @dev Mapping from `user` address to their authorized `claimer` address.
    mapping(address => address) internal _authorizedClaimers;

    /// @dev The MiniPool addresses provider contract instance.
    IMiniPoolAddressesProvider internal _addressesProvider;

    /// @dev Mapping to track if a token is an ERC6909 aToken.
    mapping(address => bool) internal _isAtokenERC6909;

    /// @dev Mapping to track if an address is a registered mini pool.
    mapping(address => bool) internal _isMiniPool;

    /// @dev Mapping from `aToken` to `ERC6909` to track the last reported difference between totalSupply(ID) and balanceOf(ERC6909).
    mapping(address => mapping(address => uint256)) internal lastReportedDiff;

    /// @dev Mapping from `aToken` to track the total difference in supply.
    mapping(address => uint256) internal _totalDiff;

    /// @dev Total number of mini pools being tracked by the system.
    uint256 internal _totalTrackedMiniPools;

    /// @dev Address of the contract responsible for forwarding rewards.
    address public rewardForwarder;

    /**
     * @notice Ensures caller is authorized to claim rewards for a user.
     * @param claimer Address attempting to claim.
     * @param user Address of the user rewards are being claimed for.
     */
    modifier onlyAuthorizedClaimers(address claimer, address user) {
        require(_authorizedClaimers[user] == claimer, Errors.R_CLAIMER_UNAUTHORIZED);
        _;
    }

    /**
     * @notice Constructor for RewardsController.
     * @param initialOwner Address of the initial owner of the contract.
     */
    constructor(address initialOwner) RewardsDistributor(initialOwner) {}

    /**
     * @notice Sets the MiniPool addresses provider.
     * @param addressesProvider Address of the MiniPool addresses provider.
     */
    function setMiniPoolAddressesProvider(address addressesProvider) external onlyOwner {
        require(address(addressesProvider) != address(0), Errors.R_INVALID_ADDRESS);
        require(address(_addressesProvider) == address(0), Errors.R_ALREADY_SET);
        _addressesProvider = IMiniPoolAddressesProvider(addressesProvider);

        emit MiniPoolAddressesProviderSet(addressesProvider);
    }

    function getMiniPoolAddressesProvider() external view returns (address) {
        return address(_addressesProvider);
    }

    /**
     * @notice Sets the reward forwarder address.
     * @param forwarder Address of the new reward forwarder.
     */
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

        emit RewardForwarderSet(forwarder);
    }
    /**
     * @notice Returns the authorized claimer address for a specific user.
     * @param user The address of the user to query.
     * @return The address of the authorized claimer for the given `user`.
     */

    function getClaimer(address user) external view override returns (address) {
        return _authorizedClaimers[user];
    }

    /**
     * @notice Sets an authorized claimer address for a specific user.
     * @param user The address of the user to set a claimer for.
     * @param caller The address to authorize as the claimer for the `user`.
     */
    function setClaimer(address user, address caller) external override onlyOwner {
        _authorizedClaimers[user] = caller;
        emit ClaimerSet(user, caller);
    }

    /**
     * @notice Configures the reward distribution parameters for multiple assets.
     * @dev Updates the total supply for each asset before configuring rewards.
     * @param config Array of reward configuration parameters for each asset.
     */
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

    /**
     * @notice Handles reward distribution updates when user balances change.
     * @param user Address of the user.
     * @param totalSupply Total supply of the asset.
     * @param userBalance User's balance of the asset.
     */
    function handleAction(address user, uint256 totalSupply, uint256 userBalance)
        external
        override
    {
        _refreshMiniPoolData();
        // If user is an ERC6909 aToken, this will only be true for aTokens.
        if (_isAtokenERC6909[user] == true) {
            (uint256 aTokenID,,) =
                IAERC6909(user).getIdForUnderlying(IAToken(msg.sender).WRAPPER_ADDRESS());
            // For trancheATokens we calculate the total supply of the AERC6909 ID for the aTokenID.
            // We subtract the current balance.
            uint256 totalSupplyAsset = IAERC6909(user).totalSupply(aTokenID);
            uint256 diff = totalSupplyAsset - userBalance;
            _totalDiff[msg.sender] =
                _totalDiff[msg.sender] - lastReportedDiff[msg.sender][user] + diff;
            lastReportedDiff[msg.sender][user] = diff;
            userBalance = totalSupplyAsset;
        }
        _updateUserRewardsPerAssetInternal(
            msg.sender, user, userBalance, totalSupply + _totalDiff[msg.sender]
        );
    }

    /**
     * @notice Updates MiniPool data if new MiniPools have been added.
     */
    function _refreshMiniPoolData() internal {
        IMiniPoolAddressesProvider addressesProvider = _addressesProvider;

        if (address(addressesProvider) != address(0)) {
            uint256 totalTrackedMiniPools = _totalTrackedMiniPools;
            if (totalTrackedMiniPools != addressesProvider.getMiniPoolCount()) {
                for (
                    uint256 i = totalTrackedMiniPools; i < addressesProvider.getMiniPoolCount(); i++
                ) {
                    address miniPool = addressesProvider.getMiniPool(i);
                    _isMiniPool[miniPool] = true;
                    setDefaultForwarder(miniPool);
                    address aToken6909 = addressesProvider.getMiniPoolToAERC6909(miniPool);
                    _isAtokenERC6909[aToken6909] = true;
                    setDefaultForwarder(aToken6909);
                    totalTrackedMiniPools++;
                }
                _totalTrackedMiniPools = totalTrackedMiniPools;
            }
        }
    }

    /**
     * @notice Sets the default forwarder for a claimee.
     * @param claimee Address to set the forwarder for.
     */
    function setDefaultForwarder(address claimee) internal {
        if (rewardForwarder != address(0)) {
            _authorizedClaimers[claimee] = rewardForwarder;
            emit ClaimerSet(claimee, rewardForwarder);
        }
    }

    /// @inheritdoc IRewardsController
    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward)
        external
        override
        returns (uint256)
    {
        require(to != address(0), Errors.R_INVALID_ADDRESS);
        return _claimRewards(assets, amount, msg.sender, msg.sender, to, reward);
    }

    /**
     * @notice Claims rewards on behalf of a user.
     * @param assets Array of asset addresses.
     * @param amount Amount of rewards to claim.
     * @param user Address of the user whose rewards are being claimed.
     * @param to Address to receive the rewards.
     * @param reward Address of the reward token.
     * @return Amount of rewards claimed.
     */
    function claimRewardsOnBehalf(
        address[] calldata assets,
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
     * @notice Claims rewards to self.
     * @param assets Array of asset addresses.
     * @param amount Amount of rewards to claim.
     * @param reward Address of the reward token.
     * @return Amount of rewards claimed.
     */
    function claimRewardsToSelf(address[] calldata assets, uint256 amount, address reward)
        external
        override
        returns (uint256)
    {
        return _claimRewards(assets, amount, msg.sender, msg.sender, msg.sender, reward);
    }
    /**
     * @notice Claims all rewards for multiple assets and sends them to a specified address.
     * @param assets Array of asset addresses to claim rewards from.
     * @param to Address that will receive the claimed rewards.
     * @return rewardTokens Array of reward token addresses that were claimed.
     * @return claimedAmounts Array of amounts that were claimed for each reward token.
     */

    function claimAllRewards(address[] calldata assets, address to)
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        require(to != address(0), Errors.R_INVALID_ADDRESS);
        return _claimAllRewards(assets, msg.sender, msg.sender, to);
    }

    /**
     * @notice Claims all rewards on behalf of a user for multiple assets.
     * @param assets Array of asset addresses to claim rewards from.
     * @param user Address of the user whose rewards are being claimed.
     * @param to Address that will receive the claimed rewards.
     * @return rewardTokens Array of reward token addresses that were claimed.
     * @return claimedAmounts Array of amounts that were claimed for each reward token.
     */
    function claimAllRewardsOnBehalf(address[] calldata assets, address user, address to)
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
     * @notice Claims all rewards for multiple assets and sends them to the caller.
     * @param assets Array of asset addresses to claim rewards from.
     * @return rewardTokens Array of reward token addresses that were claimed.
     * @return claimedAmounts Array of amounts that were claimed for each reward token.
     */
    function claimAllRewardsToSelf(address[] calldata assets)
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        return _claimAllRewards(assets, msg.sender, msg.sender, msg.sender);
    }

    /**
     * @notice Gets user stake information for multiple assets.
     * @param assets Array of asset addresses.
     * @param user Address of the user.
     * @return userState Array of user asset input data.
     */
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

    /**
     * @notice Claims specific amount of rewards.
     * @param assets Array of asset addresses.
     * @param amount Amount of rewards to claim.
     * @param claimer Address of the claimer.
     * @param user Address of the user.
     * @param to Address to receive the rewards.
     * @param reward Address of the reward token.
     * @return Amount of rewards claimed.
     */
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
        _usersUnclaimedRewards[user][reward] = unclaimedRewards - amountToClaim; // Safe due to the previous line.

        _transferRewards(to, reward, amountToClaim);
        emit RewardsClaimed(user, reward, to, claimer, amountToClaim);

        return amountToClaim;
    }

    /**
     * @notice Claims all available rewards.
     * @param assets Array of asset addresses.
     * @param claimer Address of the claimer.
     * @param user Address of the user.
     * @param to Address to receive the rewards.
     * @return rewardTokens Array of reward token addresses.
     * @return claimedAmounts Array of claimed amounts.
     */
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

    /**
     * @notice Transfers rewards to a recipient.
     * @param to Address to receive the rewards.
     * @param reward Address of the reward token.
     * @param amount Amount of rewards to transfer.
     */
    function _transferRewards(address to, address reward, uint256 amount) internal {
        bool success = __transferRewards(to, reward, amount);
        require(success == true, Errors.R_TRANSFER_ERROR);
    }

    /**
     * @notice Virtual function to implement reward token transfer logic.
     * @param to Address to receive the rewards.
     * @param reward Address of the reward token.
     * @param amount Amount of rewards to transfer.
     * @return success Boolean indicating if transfer was successful.
     */
    function __transferRewards(address to, address reward, uint256 amount)
        internal
        virtual
        returns (bool);
}
