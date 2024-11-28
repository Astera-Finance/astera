// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {RewardsController6909} from
    "../../../../contracts/protocol/rewarder/minipool/RewardsController6909.sol";

/**
 * @title Rewarder6909
 * @author Cod3x
 */
contract Rewarder6909 is RewardsController6909 {
    using SafeERC20 for IERC20;

    // reward => reward vault
    mapping(address => address) internal _rewardsVault;

    constructor() RewardsController6909(msg.sender) {}

    function setRewardsVault(address vault, address reward) external onlyOwner {
        _rewardsVault[reward] = vault;
        emit RewardsVaultUpdated(vault);
    }

    function getRewardsVault(address reward) external view returns (address) {
        return _rewardsVault[reward];
    }

    function transferRewards(address to, address reward, uint256 amount)
        internal
        override
        returns (bool)
    {
        IERC20(reward).safeTransferFrom(_rewardsVault[reward], to, amount);
        return true;
    }
}
