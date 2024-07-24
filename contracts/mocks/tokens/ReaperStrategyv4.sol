// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {IStrategy} from "../dependencies/IStrategy.sol";
import {IVault} from "../dependencies/IVault.sol";
import {SafeERC20} from "../dependencies/SafeERC20.sol";
import {IERC20} from "../dependencies/IERC20.sol";

abstract contract ReaperBaseStrategyv4 is
    IStrategy
{
    using SafeERC20 for IERC20;

    uint256 public constant PERCENT_DIVISOR = 10_000;
    uint256 public constant FUTURE_NEXT_PROPOSAL_TIME = 365 days * 100;

    // The token the strategy wants to operate
    address public want;

    bool public emergencyExit;
    uint256 public lastHarvestTimestamp;

    /**
     * @dev Reaper contracts:
     * {vault} - Address of the vault that controls the strategy's funds.
     */
    address public vault;

    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    // constructor() initializer {}

    function __ReaperBaseStrategy_init(
        address _vault,
        address _want
    ) internal {

        vault = _vault;
        want = _want;
        IERC20(want).forceApprove(vault, type(uint256).max);
    }

    /**
     * @dev Withdraws funds and sends them back to the vault. Can only
     *      be called by the vault. _amount must be valid and security fee
     *      is deducted up-front.
     */
    function withdraw(uint256 _amount) external override returns (uint256 loss) {
        require(msg.sender == vault, "Only vault can withdraw");

        uint256 amountFreed = 0;
        (amountFreed, loss) = _liquidatePosition(_amount);
        IERC20(want).safeTransfer(msg.sender, amountFreed);
    }

    /**
     * @dev harvest() function that takes care of logging. Subcontracts should
     *      override _harvestCore() and implement their specific logic in it.
     *
     * This method returns any realized profits and/or realized losses
     * incurred, and should return the total amounts of profits/losses/debt
     * payments (in `want` tokens) for the Vault's accounting.
     *
     * `debt` will be 0 if the Strategy is not past the configured
     * allocated capital, otherwise its value will be how far past the allocation
     * the Strategy is. The Strategy's allocation is configured in the Vault.
     *
     * NOTE: `repayment` should be less than or equal to `debt`.
     *       It is okay for it to be less than `debt`, as that
     *       should only used as a guide for how much is left to pay back.
     *       Payments should be made to minimize loss from slippage, debt,
     *       withdrawal fees, etc.
     */
    function harvest() public override returns (int256 roi) {
        int256 availableCapital = IVault(vault).availableCapital();
        uint256 debt = 0;
        if (availableCapital < 0) {
            debt = uint256(-availableCapital);
        }

        uint256 repayment = 0;
        if (emergencyExit) {
            uint256 amountFreed = _liquidateAllPositions();
            if (amountFreed < debt) {
                roi = -int256(debt - amountFreed);
            } else if (amountFreed > debt) {
                roi = int256(amountFreed - debt);
            }

            repayment = debt;
            if (roi < 0) {
                repayment -= uint256(-roi);
            }
        } else {
            _harvestCore();

            uint256 allocated = IVault(vault).strategies(address(this)).allocated;
            uint256 totalAssets = _estimatedTotalAssets();
            uint256 toFree = debt > totalAssets ? totalAssets : debt;

            if (totalAssets > allocated) {
                uint256 profit = totalAssets - allocated;
                toFree += profit;
                roi = int256(profit);
            } else if (totalAssets < allocated) {
                roi = -int256(allocated - totalAssets);
            }

            (uint256 amountFreed, uint256 loss) = _liquidatePosition(toFree);
            repayment = debt > amountFreed ? amountFreed : debt;
            roi -= int256(loss);
        }

        debt = IVault(vault).report(roi, repayment);
        _adjustPosition(debt);

        lastHarvestTimestamp = block.timestamp;
    }

    function _harvestCore() internal virtual {
        _beforeHarvestSwapSteps();
        _executeHarvestSwapSteps();
        _afterHarvestSwapSteps();
    }

    /**
     * @dev This is a non-view function used to calculate the strategy's total
     *      estimated holdings (in hand + in external contracts). It is invoked
     *      during harvest() for PnL calculation purposes.
     *
     *      Typically this wouldn't need to be overridden as it just acts as a
     *      pass-through to balanceOf(). But in case an implementation requires
     *      special calculations (that may need state-changing operations) to
     *      estimate the strategy's total holdings during harvest, this
     *      function can be overridden.
     */
    function _estimatedTotalAssets() internal virtual returns (uint256) {
        return balanceOf();
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It only takes into account funds in hand.
     */
    function balanceOfWant() public view virtual returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     * @dev Function to calculate the total {want} in external contracts only.
     */
    function balanceOfPool() public view virtual returns (uint256);

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It takes into account both the funds in hand, plus the funds in external contracts.
     */
    function balanceOf() public view virtual override returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    /**
     * @notice
     *  Activates emergency exit. Once activated, the Strategy will exit its
     *  position upon the next harvest, depositing all funds into the Vault as
     *  quickly as is reasonable given on-chain conditions.
     *
     *  This may only be called by GUARDIAN or higher privileged roles.
     * @dev
     *  See `vault.setEmergencyShutdown()` and `harvest()` for further details.
     */
    function setEmergencyExit() external {
        emergencyExit = true;
        IVault(vault).revokeStrategy(address(this));
    }

    /**
     * Perform any adjustments to the core position(s) of this Strategy given
     * what change the Vault made in the "investable capital" available to the
     * Strategy. Note that all "free capital" in the Strategy after the report
     * was made is available for reinvestment. Also note that this number
     * could be 0, and you should handle that scenario accordingly.
     */
    function _adjustPosition(uint256 _debt) internal virtual {
        if (emergencyExit) {
            return;
        }

        uint256 wantBalance = balanceOfWant();
        if (wantBalance > _debt) {
            uint256 toReinvest = wantBalance - _debt;
            _deposit(toReinvest);
        }
    }

    /**
     * Liquidate up to `_amountNeeded` of `want` of this strategy's positions,
     * irregardless of slippage. Any excess will be re-invested with `_adjustPosition()`.
     * This function should return the amount of `want` tokens made available by the
     * liquidation. If there is a difference between them, `loss` indicates whether the
     * difference is due to a realized loss, or if there is some other sitution at play
     * (e.g. locked funds) where the amount made available is less than what is needed.
     *
     * NOTE: The invariant `liquidatedAmount + loss <= _amountNeeded` should always be maintained
     */
    function _liquidatePosition(uint256 _amountNeeded)
        internal
        virtual
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        uint256 wantBal = balanceOfWant();
        if (wantBal < _amountNeeded) {
            _withdraw(_amountNeeded - wantBal);
            liquidatedAmount = balanceOfWant();
        } else {
            liquidatedAmount = _amountNeeded;
        }

        if (_amountNeeded > liquidatedAmount) {
            loss = _amountNeeded - liquidatedAmount;
        }
    }

    /**
     * Liquidate everything and returns the amount that got freed.
     * This function is used during emergency exit instead of `_harvestCore()` to
     * liquidate all of the Strategy's positions back to the Vault.
     */
    function _liquidateAllPositions() internal virtual returns (uint256 amountFreed);

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever the vault has allocated more free want to this strategy that can be
     * deposited in external contracts to generate yield.
     */
    function _deposit(uint256 toReinvest) internal virtual;

    /**
     * @dev Withdraws funds from external contracts and brings them back to the strategy.
     */
    function _withdraw(uint256 _amount) internal virtual;

    /**
     * @dev Override this hook for taking actions before the harvest swap steps are executed.
     *      For example, claiming rewards.
     *
     *      If you're not using the harvest steps at all, but you still need to take certain actions
     *      as part of the harvest, you have two options:
     *      1. Override _harvestCore() and execute your actions inside of it
     *      2. Override one of _beforeHarvestSwapSteps() or _afterHarvestSwapSteps() and ensure
     *         no steps are registered in this strategy.
     *
     */
    function _beforeHarvestSwapSteps() internal virtual {}

    /**
     * @dev Override this hook for taking actions after the harvest swap steps are executed.
     *      For example, adding liquidity, or anything else that cannot be accomplished with a dex swap.
     */
    function _afterHarvestSwapSteps() internal virtual {}

    /**
     * @dev Runs through all the harvest swap steps defined in {swapSteps}
     */
    function _executeHarvestSwapSteps() internal {
        // uint256 numSteps = swapSteps.length;
        // for (uint256 i = 0; i < numSteps; i = i.uncheckedInc()) {
        //     SwapStep storage step = swapSteps[i];
        //     IERC20 startToken = IERC20(step.start);
        //     uint256 amount = startToken.balanceOf(address(this));
        //     if (amount == 0) {
        //         continue;
        //     }

        //     startToken.safeApprove(address(swapper), 0);
        //     startToken.safeIncreaseAllowance(address(swapper), amount);
        //     if (step.exType == ExchangeType.UniV2) {
        //         swapper.swapUniV2(step.start, step.end, amount, step.minAmountOutData, step.exchangeAddress);
        //     } else if (step.exType == ExchangeType.Bal) {
        //         swapper.swapBal(step.start, step.end, amount, step.minAmountOutData, step.exchangeAddress);
        //     } else if (step.exType == ExchangeType.VeloSolid) {
        //         swapper.swapVelo(step.start, step.end, amount, step.minAmountOutData, step.exchangeAddress);
        //     } else if (step.exType == ExchangeType.UniV3) {
        //         swapper.swapUniV3(step.start, step.end, amount, step.minAmountOutData, step.exchangeAddress);
        //     } else {
        //         revert InvalidExchangeType(uint256(step.exType));
        //     }
        // }
    }

    /**
     * @notice For doing an unchecked increment of an index for gas optimization purposes
     * @param _i - The number to increment
     * @return The incremented number
     */
    function uncheckedInc(uint256 _i) internal pure returns (uint256) {
        unchecked {
            return _i + 1;
        }
    }
}