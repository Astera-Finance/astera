// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC4626.sol)

pragma solidity ^0.8.20;

import {ERC20} from "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {MockReaperVault2} from "./MockVault.sol";
import {IStrategy} from "../dependencies/IStrategy.sol";

contract MockStrategy is IStrategy {
    uint256 wantBalance;
    ERC20 wantContract;
    MockReaperVault2 vaultContract;

    constructor(address _want, address _vault) {
        wantContract = ERC20(_want);
        vaultContract = MockReaperVault2(_vault);
        wantBalance = wantContract.balanceOf(address(this));
    }

    function harvest() external returns (int256) {
        int256 roi = wantContract.balanceOf(address(this)) >= wantBalance
            ? int256(wantContract.balanceOf(address(this)) - wantBalance)
            : -int256(wantBalance - wantContract.balanceOf(address(this)));
        wantContract.approve(address(vaultContract), uint256(roi));
        vaultContract.report(roi, 0);
        wantBalance = wantContract.balanceOf(address(this));
        return roi;
    }

    //vault only - withdraws funds from the strategy
    function withdraw(uint256 _amount) external returns (uint256) {
        uint256 loss = wantContract.balanceOf(address(this)) >= wantBalance
            ? 0
            : wantBalance - wantContract.balanceOf(address(this));
        wantContract.transfer(msg.sender, _amount);
        return loss;
    }

    //returns the balance of all tokens managed by the strategy
    function balanceOf() external view returns (uint256) {
        return wantBalance;
    }

    //returns the address of the vault that the strategy is serving
    function vault() external view returns (address) {
        return address(vaultContract);
    }

    //returns the address of the token that the strategy needs to operate
    function want() external view returns (address) {
        return address(wantContract);
    }
}
