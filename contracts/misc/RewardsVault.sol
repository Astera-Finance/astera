// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {Ownable} from "contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";

contract RewardsVault is Ownable {
    ILendingPoolAddressesProvider public ADDRESSES_PROVIDER;
    address public INCENTIVES_CONTROLLER;
    address public REWARD_TOKEN;

    modifier onlyPoolAdmin() {
        require(ADDRESSES_PROVIDER.getPoolAdmin() == _msgSender(), Errors.CALLER_NOT_POOL_ADMIN);
        _;
    }

    constructor(
        address incentivesController,
        ILendingPoolAddressesProvider provider,
        address rewardToken
    ) Ownable(msg.sender) {
        INCENTIVES_CONTROLLER = incentivesController;
        ADDRESSES_PROVIDER = provider;
        REWARD_TOKEN = rewardToken;
    }

    function approveIncentivesController(uint256 value) external onlyPoolAdmin {
        IERC20(REWARD_TOKEN).approve(INCENTIVES_CONTROLLER, value);
    }

    function emergencyEtherTransfer(address to, uint256 amount) external onlyOwner {
        (bool success,) = to.call{value: amount}(new bytes(0));
        require(success, "ETH_TRANSFER_FAILED");
    }

    function emergencyTokenTransfer(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}
