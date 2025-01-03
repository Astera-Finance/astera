// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IRewardsController} from "../../../../contracts/interfaces/IRewardsController.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title RewardForwarder
 * @author Cod3x - 0xGoober
 * @notice Contract that manages the forwarding of rewards to registered claimees.
 * @dev Inherits from `Ownable` to restrict admin functions.
 */
contract RewardForwarder is Ownable {
    /// @dev The rewards controller contract interface.
    IRewardsController public rewardsController;

    /// @dev Array of tokens that can be claimed as rewards.
    address[] public rewardTokens;

    /// @dev Array of tokens that can receive rewards (aTokens and variable debt tokens).
    address[] public rewardedPoolTokens;

    /// @dev Mapping to track if an address is a registered claimee.
    mapping(address => bool) public isRegisteredClaimee;

    /**
     * @dev Mapping to track claimed rewards per claimee.
     * Maps `claimee` => `rewardedToken` => `rewardTokensIndex` => `amount`.
     */
    mapping(address => mapping(address => mapping(uint256 => uint256))) public claimedRewards;

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
    }

    /**
     * @notice Updates the reward tokens array by fetching from the rewards controller.
     * @dev Only callable by the contract owner.
     */
    function setRewardTokens() external onlyOwner {
        rewardTokens = rewardsController.getRewardTokens();
    }

    /**
     * @notice Sets the rewarded pool tokens that can receive rewards.
     * @dev Only callable by the contract owner.
     * @param _rewardedTokens Array of aToken and variable debt token addresses.
     */
    function setRewardedTokens(address[] memory _rewardedTokens) external onlyOwner {
        rewardedPoolTokens = _rewardedTokens;
    }

    /**
     * @notice Registers a new claimee address.
     * @dev Only callable by the contract owner.
     * @param claimee The address to register as a claimee.
     */
    function registerClaimee(address claimee) external onlyOwner {
        isRegisteredClaimee[claimee] = true;
    }

    /**
     * @notice Claims rewards for all rewarded tokens of a specified mini pool.
     * @param claimee The address of the mini pool to claim rewards for.
     */
    function claimRewardsForPool(address claimee) public {
        for (uint256 i = 0; i < rewardedPoolTokens.length; i++) {
            address token = rewardedPoolTokens[i];
            claimRewardsFor(claimee, token);
        }
    }

    /**
     * @notice Forwards all claimed rewards for a mini pool to their respective forwarders.
     * @param claimee The address of the mini pool to forward rewards for.
     */
    function forwardAllRewardsForPool(address claimee) public {
        for (uint256 idx = 0; idx < rewardTokens.length; idx++) {
            forwardRewardForPool(claimee, idx);
        }
    }

    /**
     * @notice Forwards specific claimed rewards for a mini pool to their respective forwarders.
     * @param claimee The address of the mini pool to forward rewards for.
     * @param rewardsIndex Index for reward.
     */
    function forwardRewardForPool(address claimee, uint256 rewardsIndex) public {
        for (uint256 i = 0; i < rewardedPoolTokens.length; i++) {
            address token = rewardedPoolTokens[i];
            forwardRewards(claimee, token, rewardsIndex);
        }
    }

    /**
     * @notice Claims rewards for a specific claimee and rewarded token.
     * @dev Requires the claimee to be registered.
     * @param claimee The address of the claimee.
     * @param token The address of the rewarded token.
     * @return Array of claimed reward amounts.
     */
    function claimRewardsFor(address claimee, address token) public returns (uint256[] memory) {
        require(isRegisteredClaimee[claimee], "Not registered");
        address[] memory assets = new address[](1);
        assets[0] = token;
        (address[] memory rewardTokens_, uint256[] memory claimedAmounts_) =
            rewardsController.claimAllRewardsOnBehalf(assets, claimee, address(this));
        require(rewardTokens.length >= rewardTokens_.length, "Too many rewardTokens");
        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            claimedRewards[claimee][token][i] += claimedAmounts_[i];
        }
        return claimedAmounts_;
    }

    /**
     * @notice Forwards previously claimed rewards to the designated forwarder.
     * @dev Requires claimed rewards to exist and a forwarder to be set.
     * @param claimee The address of the claimee.
     * @param token The address of the rewarded token.
     * @param rewardTokenIndex The index of the reward token in the `rewardTokens` array.
     */
    function forwardRewards(address claimee, address token, uint256 rewardTokenIndex) public {
        address rewardToken = rewardTokens[rewardTokenIndex];
        uint256 amount = claimedRewards[claimee][token][rewardTokenIndex];
        if (amount == 0) {
            return;
        }
        claimedRewards[claimee][token][rewardTokenIndex] = 0;
        address forwarder = forwarders[claimee][rewardTokenIndex];
        require(forwarder != address(0), "No forwarder set");
        IERC20(rewardToken).transfer(forwarder, amount);
    }
}
