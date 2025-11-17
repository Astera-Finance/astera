// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {
    RewardsController6909
} from "../../../../contracts/protocol/rewarder/minipool/RewardsController6909.sol";

/**
 * @title Rewarder6909
 * @author Conclave
 * @notice Contract for managing reward vaults and transferring rewards for ERC6909 tokens.
 * @dev Inherits from RewardsController6909 and implements reward vault management functionality.
 */
contract Rewarder6909 is RewardsController6909 {
    using SafeERC20 for IERC20;

    /**
     * @dev Mapping that associates reward token addresses with their corresponding vault addresses.
     */
    mapping(address => address) internal _rewardsVault;

    /**
     * @dev Constructor that initializes the contract with the deployer as owner.
     */
    constructor() RewardsController6909(msg.sender) {}

    /**
     * @notice Sets the vault address for a specific reward token.
     * @param vault The address of the vault to set.
     * @param reward The address of the reward token.
     */
    function setRewardsVault(address vault, address reward) external onlyOwner {
        _rewardsVault[reward] = vault;
        emit RewardsVaultUpdated(vault);
    }

    /**
     * @notice Returns the vault address for a specific reward token.
     * @param reward The address of the reward token.
     * @return The address of the corresponding reward vault.
     */
    function getRewardsVault(address reward) external view returns (address) {
        return _rewardsVault[reward];
    }

    /**
     * @notice Internal function to transfer rewards from vault to recipient.
     * @param to The address of the reward recipient.
     * @param reward The address of the reward token.
     * @param amount The amount of rewards to transfer.
     * @return A boolean indicating success of the transfer.
     */
    function __transferRewards(address to, address reward, uint256 amount)
        internal
        override
        returns (bool)
    {
        IERC20(reward).safeTransferFrom(_rewardsVault[reward], to, amount);
        return true;
    }
}
