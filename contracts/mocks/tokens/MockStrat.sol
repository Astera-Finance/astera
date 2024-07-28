// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {ReaperBaseStrategyv4} from "./ReaperStrategyv4.sol";
import {IVault} from "../dependencies/IVault.sol";
import {IExternalContract} from "../dependencies/IExternalContract.sol";
import {SafeERC20} from "../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IERC20} from "../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";

/**
 * @dev This strategy will deposit and leverage a token on Cod3x Lend to maximize yield
 */
contract ReaperStrategy is ReaperBaseStrategyv4 {
    using SafeERC20 for IERC20;

    IExternalContract externalContract;

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    constructor(address _vault, address _want, address _externalContract) {
        want = _want;
        externalContract = IExternalContract(_externalContract);
        __ReaperBaseStrategy_init(_vault, want);
    }

    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        _withdrawUnderlying(_getExternalBalance());
        return balanceOfWant();
    }

    /**
     * @dev Core function of the strat, in charge of collecting rewards
     */
    function _beforeHarvestSwapSteps() internal override {}

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * !audit we increase the allowance in the balance amount but we deposit the amount specified
     */
    function _deposit(uint256 toReinvest) internal override {
        IERC20(want).safeIncreaseAllowance(address(externalContract), toReinvest);
        externalContract.deposit(toReinvest);
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        if (_amount == 0) {
            return;
        }

        _withdrawUnderlying(_amount);
    }

    /**
     * @dev Attempts to Withdraw {_withdrawAmount} from pool. Withdraws max amount that can be
     *      safely withdrawn if {_withdrawAmount} is too high.
     */
    function _withdrawUnderlying(uint256 _withdrawAmount) internal {
        uint256 withdrawable = _getExternalBalance();
        _withdrawAmount = _withdrawAmount > withdrawable ? withdrawable : _withdrawAmount;

        if (_withdrawAmount != 0) {
            externalContract.withdraw(_withdrawAmount);
        }
    }

    /**
     * @dev Attempts to safely withdraw {_amount} from the pool and optionally sends it
     *      to the vault.
     */
    function authorizedWithdrawUnderlying(uint256 _amount) external {
        _withdrawUnderlying(_amount);
    }

    function _getExternalBalance() internal view returns (uint256) {
        externalContract.balance();
    }

    function balanceOfPool() public view override returns (uint256) {
        _getExternalBalance();
    }
}
