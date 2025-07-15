// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IRewardsController} from "../../../../contracts/interfaces/IRewardsController.sol";
import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title RewardForwarder
 * @author Conclave - 0xGoober
 * @notice Contract that manages the forwarding of rewards to registered claimees.
 * @dev Inherits from `Ownable` to restrict admin functions.
 */
contract RewardForwarder is Ownable {
    using SafeERC20 for IERC20;
    /// @dev The rewards controller contract interface.

    IRewardsController public rewardsController;

    /// @dev Array of tokens that can receive rewards (aTokens and variable debt tokens).
    address[] public rewardedPoolTokens;

    /// @dev Mapping to track if an address is a registered claimee.
    mapping(address => bool) public isRegisteredClaimee;

    /**
     * @dev Emitted when a forwarder is set for a specific claimee and reward token.
     * @param claimee The address of the claimee.
     * @param rewardTokenIndex The index of the reward token in the `rewardTokens` array.
     * @param forwarder The address that will receive forwarded rewards.
     */
    event ForwarderSet(
        address indexed claimee, uint256 indexed rewardTokenIndex, address indexed forwarder
    );

    /**
     * @dev Emitted when the rewarded tokens are set.
     * @param rewardedTokens The array of rewarded tokens.
     */
    event RewardedTokensSet(address[] rewardedTokens);

    /**
     * @dev Emitted when a claimee is registered.
     * @param claimee The address of the claimee.
     */
    event ClaimeeRegistered(address claimee);

    /**
     * @dev Emitted when rewards are forwarded to a forwarder.
     * @param claimee The address of the claimee.
     * @param rewardTokenIndex The index of the reward token in the `rewardTokens` array.
     * @param amount The amount of rewards.
     * @param forwarder The address that will receive forwarded rewards.
     */
    event RewardsForwarded(
        address claimee, uint256 rewardTokenIndex, uint256 amount, address forwarder
    );

    /**
     * @dev Mapping to track claimed rewards per claimee.
     * Maps `claimee` => `rewardTokensIndex` => `amount`.
     */
    mapping(address => mapping(uint256 => uint256)) public claimedRewards;

    /**
     * @dev Mapping to store reward forwarder addresses.
     * Maps `claimee` => `rewardTokensIndex` => `forwarder`.
     */
    mapping(address => mapping(uint256 => address)) public forwarders;

    /**
     * @dev Initializes the contract with a rewards controller address.
     * @param _rewardsController The address of the rewards controller contract.
     */
    constructor(address _rewardsController) Ownable(msg.sender) {
        rewardsController = IRewardsController(_rewardsController);
    }

    /**
     * @notice Sets the forwarder address for a specific claimee and reward token.
     * @dev Only callable by the contract owner.
     * @param claimee The address of the claimee.
     * @param rewardTokenIndex The index of the reward token in the `rewardTokens` array.
     * @param forwarder The address that will receive forwarded rewards.
     */
    function setForwarder(address claimee, uint256 rewardTokenIndex, address forwarder)
        external
        onlyOwner
    {
        forwarders[claimee][rewardTokenIndex] = forwarder;

        emit ForwarderSet(claimee, rewardTokenIndex, forwarder);
    }

    /**
     * @notice Sets the rewarded pool tokens that can receive rewards.
     * @dev Only callable by the contract owner.
     * @param _rewardedTokens Array of aToken and variable debt token addresses.
     */
    function setRewardedTokens(address[] memory _rewardedTokens) external onlyOwner {
        rewardedPoolTokens = _rewardedTokens;

        emit RewardedTokensSet(_rewardedTokens);
    }

    /**
     * @notice Registers a new claimee address.
     * @dev Only callable by the contract owner.
     * @param claimee The address to register as a claimee.
     */
    function registerClaimee(address claimee) external onlyOwner {
        isRegisteredClaimee[claimee] = true;

        emit ClaimeeRegistered(claimee);
    }

    /**
     * @notice Claims rewards for all rewarded tokens of a specified mini pool.
     * @param claimee The address of the mini pool to claim rewards for.
     */
    function claimRewardsForPool(address claimee) public {
        claimRewardsFor(claimee, rewardedPoolTokens);
    }

    /**
     * @notice Forwards all claimed rewards for a mini pool to their respective forwarders.
     * @param claimee The address of the mini pool to forward rewards for.
     */
    function forwardAllRewardsForPool(address claimee) public {
        for (uint256 idx = 0; idx < getRewardTokens().length; idx++) {
            forwardRewards(claimee, idx);
        }
    }

    /**
     * @notice Claims rewards for a specific claimee and rewarded tokens.
     * @dev Requires the claimee to be registered.
     * @param claimee The address of the claimee.
     * @param tokens Array of token addresses of the rewarded tokens.
     * @return Array of claimed reward amounts.
     */
    function claimRewardsFor(address claimee, address[] memory tokens)
        public
        returns (uint256[] memory)
    {
        require(isRegisteredClaimee[claimee], Errors.R_NOT_REGISTERED);

        (address[] memory rewardTokens_, uint256[] memory claimedAmounts_) =
            rewardsController.claimAllRewardsOnBehalf(tokens, claimee, address(this));

        require(getRewardTokens().length >= rewardTokens_.length, Errors.R_TOO_MANY_REWARD_TOKENS);

        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            claimedRewards[claimee][i] += claimedAmounts_[i];
        }
        return claimedAmounts_;
    }

    /**
     * @notice Forwards previously claimed rewards to the designated forwarder.
     * @dev Requires claimed rewards to exist and a forwarder to be set.
     * @param claimee The address of the claimee.
     * @param rewardTokenIndex The index of the reward token in the `rewardTokens` array.
     */
    function forwardRewards(address claimee, uint256 rewardTokenIndex) public {
        address rewardToken = getRewardTokens()[rewardTokenIndex];
        uint256 amount = claimedRewards[claimee][rewardTokenIndex];
        if (amount == 0) {
            return;
        }
        claimedRewards[claimee][rewardTokenIndex] = 0;
        address forwarder = forwarders[claimee][rewardTokenIndex];
        require(forwarder != address(0), Errors.R_NO_FORWARDER_SET);
        IERC20(rewardToken).safeTransfer(forwarder, amount);

        emit RewardsForwarded(claimee, rewardTokenIndex, amount, forwarder);
    }

    /**
     * @notice Function gets reward tokens from rewardController.
     * @dev Used where need to read rewardTokens
     * @return Array of rewardTokens configured in rewardController.
     */
    function getRewardTokens() private view returns (address[] memory) {
        return rewardsController.getRewardTokens();
    }
}
