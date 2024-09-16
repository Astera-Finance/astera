// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IRewardsController} from "contracts/interfaces/IRewardsController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DistributionTypes} from "contracts/protocol/rewarder/DistributionTypes.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title RewardForwarder
 * @author 0xGoober
 * @dev This contract manages the forwarding of rewards to registered claimees.
 */
contract RewardForwarder is Ownable {
    IRewardsController public rewardsController;
    address[] public rewardTokens; // tokens that can be claimed as rewards
    address[] public rewardedPoolTokens; // tokens that can be recieve rewards
    address[] public registeredClaimees;
    mapping(address => bool) public isRegisteredClaimee;
    //      claimee => rewardedToken => rewardTokensIndex => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public claimedRewards;
    //      claimee => rewardTokensIndex => forwarder
    mapping(address => mapping(uint256 => address)) public forwarders;

    constructor(address _rewardsController) Ownable(msg.sender) {
        rewardsController = IRewardsController(_rewardsController);
    }

    /**
     * @dev Sets the forwarder address for a specific claimee and reward token index.
     * @param claimee The address of the claimee.
     * @param rewardTokenIndex The index of the reward token.
     * @param forwarder The address of the forwarder.
     */
    function setForwarder(address claimee, uint256 rewardTokenIndex, address forwarder)
        external
        onlyOwner
    {
        forwarders[claimee][rewardTokenIndex] = forwarder;
    }

    /**
     * @dev Sets the reward tokens by fetching them from the rewards controller.
     */
    function setRewardTokens() external onlyOwner {
        rewardTokens = rewardsController.getRewardTokens();
    }

    /**
     * @dev Sets the rewarded tokens. An array of aTokens and variable debt tokens.
     */
    function setRewardedTokens(address[] memory _rewardedTokens) external onlyOwner {
        rewardedPoolTokens = _rewardedTokens;
    }

    /**
     * @dev Registers a claimee.
     * @param claimee The address of the claimee.
     */
    function registerClaimee(address claimee) external onlyOwner {
        isRegisteredClaimee[claimee] = true;
        registeredClaimees.push(claimee);
    }
    /**
     * @dev Claims rewards for a specified mini pool.
     * @param claimee The address of the mini pool.
     */

    function claimRewardsForPool(address claimee) public {
        for (uint256 i = 0; i < rewardedPoolTokens.length; i++) {
            address token = rewardedPoolTokens[i];
            claimRewardsFor(claimee, token);
        }
    }

    function forwardRewardsForPool(address claimee) public {
        for (uint256 i = 0; i < rewardedPoolTokens.length; i++) {
            address token = rewardedPoolTokens[i];
            forwardRewards(claimee, token, i);
        }
    }

    /**
     * @dev Claims rewards for a specific claimee and rewardedtoken.
     * @param claimee The address of the claimee.
     * @param token The address of the rewarded token.
     */
    function claimRewardsFor(address claimee, address token) public returns (uint256[] memory) {
        require(isRegisteredClaimee[claimee], "Not registered");
        address[] memory assets = new address[](1);
        assets[0] = token;
        (address[] memory rewardTokens_, uint256[] memory claimedAmounts_) =
            rewardsController.claimAllRewardsOnBehalf(assets, claimee, address(this));
        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            claimedRewards[claimee][token][i] += claimedAmounts_[i];
        }
        return claimedAmounts_;
    }

    /**
     * @dev Forwards the claimed rewards to the specified forwarder.
     * @param claimee The address of the claimee.
     * @param token The address of the rewarded token.
     * @param rewardTokenIndex The index of the reward token.
     */
    function forwardRewards(address claimee, address token, uint256 rewardTokenIndex) public {
        address rewardToken = rewardTokens[rewardTokenIndex];
        uint256 amount = claimedRewards[claimee][token][rewardTokenIndex];
        require(amount != 0, "No rewards to forward");
        claimedRewards[claimee][token][rewardTokenIndex] = 0;
        address forwarder = forwarders[claimee][rewardTokenIndex];
        require(forwarder != address(0), "No forwarder set");
        IERC20(rewardToken).transfer(forwarder, amount);
    }
}
