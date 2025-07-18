// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {ERC20} from "../../../contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {IERC20} from "../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IERC20Metadata} from
    "../../../contracts/dependencies/openzeppelin/contracts/IERC20Metadata.sol";
import {SafeERC20} from "../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IStrategy} from "../../../contracts/mocks/dependencies/IStrategy.sol";
import {IERC4626Events} from "./IERC4626Events.sol";

/**
 * @title MockReaperVault2
 * @dev MockReaperVault2 emulate vault behaviour, nearing 1:1 copy of live vaults, minus access control
 */
contract MockReaperVault2 is ERC20, IERC4626Events {
    using SafeERC20 for IERC20Metadata;

    struct StrategyParams {
        uint256 activation; // Activation block.timestamp
        uint256 feeBPS; // Performance fee taken from profit, in BPS
        uint256 allocBPS; // Allocation in BPS of vault's total assets
        uint256 allocated; // Amount of capital allocated to this strategy
        uint256 gains; // Total returns that Strategy has realized for Vault
        uint256 losses; // Total losses that Strategy has realized for Vault
        uint256 lastReport; // block.timestamp of the last time a report occured
    }

    mapping(address => StrategyParams) public strategies;

    // Ordering that `withdraw` uses to determine which strategies to pull funds from
    address[] public withdrawalQueue;

    uint256 public constant DEGRADATION_COEFFICIENT = 10 ** 18; // The unit for calculating profit degradation.
    uint256 public constant PERCENT_DIVISOR = 10000;
    uint256 public tvlCap;

    uint256 public totalIdle; // Amount of tokens in the vault
    uint256 public totalAllocBPS; // Sum of allocBPS across all strategies (in BPS, <= 10k)
    uint256 public totalAllocated; // Amount of tokens that have been allocated to all strategies
    uint256 public lastReport; // block.timestamp of last report from any strategy

    uint256 public immutable constructionTime;
    bool public emergencyShutdown;

    // The token the vault accepts and looks to maximize.
    IERC20Metadata public immutable token;

    // Max slippage(loss) allowed when withdrawing, in BPS (0.01%)
    uint256 public withdrawMaxLoss = 1;
    uint256 public lockedProfitDegradation; // rate per block of degradation. DEGRADATION_COEFFICIENT is 100% per block
    uint256 public lockedProfit; // how much profit is locked and cant be withdrawn

    address public treasury; // address to whom performance fee is remitted in the form of vault shares

    event StrategyAdded(address indexed strategy, uint256 feeBPS, uint256 allocBPS);
    event StrategyFeeBPSUpdated(address indexed strategy, uint256 feeBPS);
    event StrategyAllocBPSUpdated(address indexed strategy, uint256 allocBPS);
    event StrategyRevoked(address indexed strategy);
    event UpdateWithdrawalQueue(address[] withdrawalQueue);
    event WithdrawMaxLossUpdated(uint256 withdrawMaxLoss);
    event EmergencyShutdown(bool active);
    event InCaseTokensGetStuckCalled(address token, uint256 amount);
    event TvlCapUpdated(uint256 newTvlCap);
    event LockedProfitDegradationUpdated(uint256 degradation);
    event StrategyReported(
        address indexed strategy,
        uint256 gain,
        uint256 loss,
        uint256 debtPaid,
        uint256 gains,
        uint256 losses,
        uint256 allocated,
        uint256 allocationAdded,
        uint256 allocBPS
    );

    /**
     * @notice Initializes the vault's own 'RF' token.
     * This token is minted when someone does a deposit. It is burned in order
     * to withdraw the corresponding portion of the underlying assets.
     * @param _token the token to maximize.
     * @param _name the name of the vault token.
     * @param _symbol the symbol of the vault token.
     * @param _tvlCap initial deposit cap for scaling TVL safely
     */
    constructor(
        address _token,
        string memory _name,
        string memory _symbol,
        uint256 _tvlCap,
        address _treasury
    ) ERC20(string(_name), string(_symbol)) {
        token = IERC20Metadata(_token);
        constructionTime = block.timestamp;
        lastReport = block.timestamp;
        tvlCap = _tvlCap;
        treasury = _treasury;
        lockedProfitDegradation = (DEGRADATION_COEFFICIENT * 46) / 10 ** 6; // 6 hours in blocks
    }

    /**
     * @notice Adds a new strategy to the vault with a given allocation amount in basis points.
     * @param _strategy The strategy to add.
     * @param _feeBPS The performance fee (taken from profit) in basis points
     * @param _allocBPS The strategy allocation in basis points
     */
    function addStrategy(address _strategy, uint256 _feeBPS, uint256 _allocBPS) external {
        require(!emergencyShutdown, "Cannot add strategy during emergency shutdown");
        require(_strategy != address(0), "Invalid strategy address");
        require(strategies[_strategy].activation == 0, "Strategy already added");
        require(address(this) == IStrategy(_strategy).vault(), "Strategy's vault does not match");
        require(address(token) == IStrategy(_strategy).want(), "Strategy's want does not match");
        require(_feeBPS <= PERCENT_DIVISOR / 5, "Fee cannot be higher than 20 BPS");
        require(_allocBPS + totalAllocBPS <= PERCENT_DIVISOR, "Invalid allocBPS value");

        strategies[_strategy] = StrategyParams({
            activation: block.timestamp,
            feeBPS: _feeBPS,
            allocBPS: _allocBPS,
            allocated: 0,
            gains: 0,
            losses: 0,
            lastReport: block.timestamp
        });

        totalAllocBPS += _allocBPS;
        withdrawalQueue.push(_strategy);
        emit StrategyAdded(_strategy, _feeBPS, _allocBPS);
    }

    /**
     * @notice Updates the strategy's performance fee.
     * @param _strategy The strategy to update.
     * @param _feeBPS The new performance fee in basis points.
     */
    function updateStrategyFeeBPS(address _strategy, uint256 _feeBPS) external {
        require(strategies[_strategy].activation != 0, "Invalid strategy address");
        require(_feeBPS <= PERCENT_DIVISOR / 5, "Fee cannot be higher than 20 BPS");
        strategies[_strategy].feeBPS = _feeBPS;
        emit StrategyFeeBPSUpdated(_strategy, _feeBPS);
    }

    /**
     * @notice Updates the allocation points for a given strategy.
     * @param _strategy The strategy to update.
     * @param _allocBPS The strategy allocation in basis points
     */
    function updateStrategyAllocBPS(address _strategy, uint256 _allocBPS) external {
        require(strategies[_strategy].activation != 0, "Invalid strategy address");
        uint256 currentStrategyAllocBPS = strategies[_strategy].allocBPS;
        totalAllocBPS -= currentStrategyAllocBPS;
        strategies[_strategy].allocBPS = _allocBPS;
        totalAllocBPS += _allocBPS;
        require(totalAllocBPS <= PERCENT_DIVISOR, "Invalid BPS value");
        emit StrategyAllocBPSUpdated(_strategy, _allocBPS);
    }

    /**
     * @notice Removes any allocation to a given strategy.
     * @param _strategy The strategy to revoke.
     */
    function revokeStrategy(address _strategy) external {
        if (strategies[_strategy].allocBPS == 0) {
            return;
        }

        totalAllocBPS -= strategies[_strategy].allocBPS;
        strategies[_strategy].allocBPS = 0;
        emit StrategyRevoked(_strategy);
    }

    /**
     * @notice Called by a strategy to determine the amount of capital that the vault is
     * able to provide it. A positive amount means that vault has excess capital to provide
     * the strategy, while a negative amount means that the strategy has a balance owing to
     * the vault.
     */
    function availableCapital() public view returns (int256) {
        address stratAddr = msg.sender;
        if (totalAllocBPS == 0 || emergencyShutdown) {
            return -int256(strategies[stratAddr].allocated);
        }

        uint256 stratMaxAllocation = (strategies[stratAddr].allocBPS * balance()) / PERCENT_DIVISOR;
        uint256 stratCurrentAllocation = strategies[stratAddr].allocated;

        if (stratCurrentAllocation > stratMaxAllocation) {
            return -int256(stratCurrentAllocation - stratMaxAllocation);
        } else if (stratCurrentAllocation < stratMaxAllocation) {
            uint256 vaultMaxAllocation = (totalAllocBPS * balance()) / PERCENT_DIVISOR;
            uint256 vaultCurrentAllocation = totalAllocated;

            if (vaultCurrentAllocation >= vaultMaxAllocation) {
                return 0;
            }

            uint256 available = stratMaxAllocation - stratCurrentAllocation;
            available = available > (vaultMaxAllocation - vaultCurrentAllocation)
                ? (vaultMaxAllocation - vaultCurrentAllocation)
                : available;
            available = available > totalIdle ? totalIdle : available;

            return int256(available);
        } else {
            return 0;
        }
    }

    /**
     * @notice Updates the withdrawalQueue to match the addresses and order specified.
     * @param _withdrawalQueue The new withdrawalQueue to update to.
     */
    function setWithdrawalQueue(address[] memory _withdrawalQueue) external {
        uint256 queueLength = _withdrawalQueue.length;
        require(queueLength != 0, "Queue must not be empty");

        delete withdrawalQueue;
        for (uint256 i = 0; i < queueLength; i = uncheckedInc(i)) {
            address strategy = _withdrawalQueue[i];
            StrategyParams storage params = strategies[strategy];
            require(params.activation != 0, "Invalid strategy address");
            withdrawalQueue.push(strategy);
        }
        emit UpdateWithdrawalQueue(_withdrawalQueue);
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the vault contract idle funds, and the capital deployed across
     * all the strategies.
     */
    function balance() public view returns (uint256) {
        return totalIdle + totalAllocated;
    }

    /**
     * @notice It calculates the amount of free funds available after profit locking.
     * For calculating share price, issuing shares during deposit, or burning shares during withdrawal.
     * @return freeFunds - the total amount of free funds available.
     */
    function _freeFunds() internal view returns (uint256) {
        return balance() - _calculateLockedProfit();
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0
            ? 10 ** decimals()
            : (_freeFunds() * 10 ** decimals()) / totalSupply();
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external {
        _deposit(token.balanceOf(msg.sender), msg.sender);
    }

    /**
     * @notice The entrypoint of funds into the system. People deposit with this function
     * into the vault.
     * @param _amount The amount of assets to deposit
     */
    function deposit(uint256 _amount, address _receiver) external returns (uint256 shares) {
        shares = _deposit(_amount, _receiver);
    }

    // Internal helper function to deposit {_amount} of assets and mint corresponding
    // shares to {_receiver}. Returns the number of shares that were minted.
    function _deposit(uint256 _amount, address _receiver) internal returns (uint256 shares) {
        require(!emergencyShutdown, "Cannot deposit during emergency shutdown");
        require(_amount != 0, "Invalid amount");
        require(balance() + _amount <= tvlCap, "Vault is full");

        uint256 supply = totalSupply();
        if (supply == 0) {
            shares = _amount;
        } else {
            shares = (_amount * supply) / _freeFunds(); // use "freeFunds" instead of "balance"
        }

        _mint(_receiver, shares);
        totalIdle += _amount;
        token.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(msg.sender, _receiver, _amount, shares);
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        _withdraw(balanceOf(msg.sender), msg.sender, msg.sender);
    }

    /**
     * @notice Function to exit the system. The vault will withdraw the required tokens
     * from the strategies and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     * @param _shares the number of shares to burn
     */
    function withdraw(uint256 _shares) external {
        _withdraw(_shares, msg.sender, msg.sender);
    }

    // Internal helper function to burn {_shares} of vault shares belonging to {_owner}
    // and return corresponding assets to {_receiver}. Returns the number of assets that were returned.
    function _withdraw(uint256 _shares, address _receiver, address _owner)
        internal
        returns (uint256 value)
    {
        require(_shares != 0, "Invalid amount");
        value = (_freeFunds() * _shares) / totalSupply();

        uint256 vaultBalance = totalIdle;
        if (value > vaultBalance) {
            uint256 totalLoss = 0;
            uint256 queueLength = withdrawalQueue.length;
            for (uint256 i = 0; i < queueLength; i = uncheckedInc(i)) {
                if (value <= vaultBalance) {
                    break;
                }

                address stratAddr = withdrawalQueue[i];
                uint256 strategyBal = strategies[stratAddr].allocated;
                if (strategyBal == 0) {
                    continue;
                }

                uint256 remaining = value - vaultBalance;
                uint256 preWithdrawBal = token.balanceOf(address(this));
                uint256 withdrawFromStrat = remaining > strategyBal ? strategyBal : remaining;
                uint256 loss = IStrategy(stratAddr).withdraw(withdrawFromStrat);
                uint256 actualWithdrawn = token.balanceOf(address(this)) - preWithdrawBal;
                vaultBalance += actualWithdrawn;

                // Withdrawer incurs any losses from withdrawing as reported by strat
                if (loss != 0) {
                    value -= loss;
                    totalLoss += loss;
                    _reportLoss(stratAddr, loss);
                }

                strategies[stratAddr].allocated -= actualWithdrawn;
                totalAllocated -= actualWithdrawn;
            }

            totalIdle = vaultBalance;
            if (value > vaultBalance) {
                value = vaultBalance;
                _shares = ((value + totalLoss) * totalSupply()) / _freeFunds();
            }

            require(
                totalLoss <= ((value + totalLoss) * withdrawMaxLoss) / PERCENT_DIVISOR,
                "Withdraw loss exceeds slippage"
            );
        }

        _burn(_owner, _shares);
        totalIdle -= value;
        token.safeTransfer(_receiver, value);
        emit Withdraw(msg.sender, _receiver, _owner, value, _shares);
    }

    /**
     * @notice It calculates the amount of locked profit from recent harvests.
     * @return the amount of locked profit.
     */
    function _calculateLockedProfit() internal view returns (uint256) {
        uint256 lockedFundsRatio = (block.timestamp - lastReport) * lockedProfitDegradation;
        if (lockedFundsRatio < DEGRADATION_COEFFICIENT) {
            return lockedProfit - ((lockedFundsRatio * lockedProfit) / DEGRADATION_COEFFICIENT);
        }

        return 0;
    }

    /**
     * @notice Helper function to report a loss by a given strategy.
     * @param strategy The strategy to report the loss for.
     * @param loss The amount lost.
     */
    function _reportLoss(address strategy, uint256 loss) internal {
        StrategyParams storage stratParams = strategies[strategy];
        // Loss can only be up the amount of capital allocated to the strategy
        uint256 allocation = stratParams.allocated;
        require(loss <= allocation, "Strategy loss cannot be greater than allocation");

        if (totalAllocBPS != 0) {
            // reduce strat's allocBPS proportional to loss
            uint256 lossProportion = (loss * totalAllocBPS) / totalAllocated;
            uint256 bpsChange =
                lossProportion > stratParams.allocBPS ? stratParams.allocBPS : lossProportion;

            // If the loss is too small, bpsChange will be 0
            if (bpsChange != 0) {
                stratParams.allocBPS -= bpsChange;
                totalAllocBPS -= bpsChange;
            }
        }

        // Finally, adjust our strategy's parameters by the loss
        stratParams.losses += loss;
        stratParams.allocated -= loss;
        totalAllocated -= loss;
    }

    /**
     * @notice Helper function to charge fees from the gain reported by a strategy.
     * Fees is charged by issuing the corresponding amount of vault shares to the treasury.
     * @param strategy The strategy that reported gain.
     * @param gain The amount of profit reported.
     * @return The fee amount in assets.
     */
    function _chargeFees(address strategy, uint256 gain) internal returns (uint256) {
        uint256 performanceFee = (gain * strategies[strategy].feeBPS) / PERCENT_DIVISOR;
        if (performanceFee != 0) {
            uint256 supply = totalSupply();
            uint256 shares = supply == 0 ? performanceFee : (performanceFee * supply) / _freeFunds();
            _mint(treasury, shares);
        }
        return performanceFee;
    }

    // To avoid "stack too deep" errors
    struct LocalVariables_report {
        address stratAddr;
        uint256 loss;
        uint256 gain;
        uint256 fees;
        int256 available;
        uint256 debt;
        uint256 credit;
        uint256 debtPayment;
        uint256 freeWantInStrat;
        uint256 lockedProfitBeforeLoss;
    }

    /**
     * @notice Main contact point where each strategy interacts with the vault during its harvest
     * to report profit/loss as well as any repayment of debt.
     * @param _roi The return on investment (positive or negative) given as the total amount
     * gained or lost from the harvest.
     * @param _repayment The repayment of debt by the strategy.
     */
    function report(int256 _roi, uint256 _repayment) external returns (uint256) {
        LocalVariables_report memory vars;
        vars.stratAddr = msg.sender;
        StrategyParams storage strategy = strategies[vars.stratAddr];
        require(strategy.activation != 0, "Unauthorized strategy");

        if (_roi < 0) {
            vars.loss = uint256(-_roi);
            _reportLoss(vars.stratAddr, vars.loss);
        } else if (_roi > 0) {
            vars.gain = uint256(_roi);
            vars.fees = _chargeFees(vars.stratAddr, vars.gain);
            strategy.gains += vars.gain;
        }

        vars.available = availableCapital();
        if (vars.available < 0) {
            vars.debt = uint256(-vars.available);
            vars.debtPayment = vars.debt > _repayment ? _repayment : vars.debt;

            if (vars.debtPayment != 0) {
                strategy.allocated -= vars.debtPayment;
                totalAllocated -= vars.debtPayment;
                vars.debt -= vars.debtPayment; // tracked for return value
            }
        } else if (vars.available > 0) {
            vars.credit = uint256(vars.available);
            strategy.allocated += vars.credit;
            totalAllocated += vars.credit;
        }

        vars.freeWantInStrat = vars.gain + vars.debtPayment;
        if (vars.credit > vars.freeWantInStrat) {
            totalIdle -= (vars.credit - vars.freeWantInStrat);
            token.safeTransfer(vars.stratAddr, vars.credit - vars.freeWantInStrat);
        } else if (vars.credit < vars.freeWantInStrat) {
            totalIdle += (vars.freeWantInStrat - vars.credit);
            token.safeTransferFrom(
                vars.stratAddr, address(this), vars.freeWantInStrat - vars.credit
            );
        }

        // Profit is locked and gradually released per block
        // NOTE: compute current locked profit and replace with sum of current and new
        vars.lockedProfitBeforeLoss = _calculateLockedProfit() + vars.gain - vars.fees;
        if (vars.lockedProfitBeforeLoss > vars.loss) {
            lockedProfit = vars.lockedProfitBeforeLoss - vars.loss;
        } else {
            lockedProfit = 0;
        }

        strategy.lastReport = block.timestamp;
        lastReport = block.timestamp;

        emit StrategyReported(
            vars.stratAddr,
            vars.gain,
            vars.loss,
            vars.debtPayment,
            strategy.gains,
            strategy.losses,
            strategy.allocated,
            vars.credit,
            strategy.allocBPS
        );

        if (strategy.allocBPS == 0 || emergencyShutdown) {
            return IStrategy(vars.stratAddr).balanceOf();
        }

        return vars.debt;
    }

    /**
     * @notice Updates the withdrawMaxLoss which is the maximum allowed slippage.
     * @param _withdrawMaxLoss The new value, in basis points.
     */
    function updateWithdrawMaxLoss(uint256 _withdrawMaxLoss) external {
        require(_withdrawMaxLoss <= PERCENT_DIVISOR, "Invalid BPS value");
        withdrawMaxLoss = _withdrawMaxLoss;
        emit WithdrawMaxLossUpdated(_withdrawMaxLoss);
    }

    /**
     * @notice Updates the vault tvl cap (the max amount of assets held by the vault).
     * @dev pass in max value of uint to effectively remove TVL cap.
     * @param _newTvlCap The new tvl cap.
     */
    function updateTvlCap(uint256 _newTvlCap) public {
        tvlCap = _newTvlCap;
        emit TvlCapUpdated(tvlCap);
    }

    /**
     * @dev helper function to remove TVL cap
     */
    function removeTvlCap() external {
        updateTvlCap(type(uint256).max);
    }

    /**
     * Activates or deactivates Vault mode where all Strategies go into full
     * withdrawal.
     * During Emergency Shutdown:
     * 1. No Users may deposit into the Vault (but may withdraw as usual.)
     * 2. New Strategies may not be added.
     * 3. Each Strategy must pay back their debt as quickly as reasonable to
     * minimally affect their position.
     *
     * If true, the Vault goes into Emergency Shutdown. If false, the Vault
     * goes back into Normal Operation.
     */
    function setEmergencyShutdown(bool _active) external {
        emergencyShutdown = _active;
        emit EmergencyShutdown(_active);
    }

    /**
     * @notice Changes the locked profit degradation.
     * @param degradation - The rate of degradation in percent per second scaled to 1e18.
     */
    function setLockedProfitDegradation(uint256 degradation) external {
        require(degradation <= DEGRADATION_COEFFICIENT, "Degradation cannot be more than 100%");
        lockedProfitDegradation = degradation;
        emit LockedProfitDegradationUpdated(degradation);
    }

    /**
     * @notice Only DEFAULT_ADMIN_ROLE can update treasury address.
     */
    function updateTreasury(address newTreasury) external {
        require(newTreasury != address(0), "Invalid address");
        treasury = newTreasury;
    }

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param _token address of the token to rescue.
     */
    function inCaseTokensGetStuck(address _token) external {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        if (_token == address(token)) {
            amount -= totalIdle;
        }
        require(amount != 0, "Zero amount");

        IERC20Metadata(_token).safeTransfer(msg.sender, amount);
        emit InCaseTokensGetStuckCalled(_token, amount);
    }

    /**
     * @dev Overrides the default 18 decimals for the vault ERC20 to
     * match the same decimals as the underlying token used
     */
    function decimals() public view override returns (uint8) {
        return token.decimals();
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

    function asset() external view returns (address) {
        return address(token);
    }

    // The amount of assets that the Vault would exchange for the amount of shares provided,
    // in an ideal scenario where all the conditions are met.
    //
    // MUST NOT be inclusive of any fees that are charged against assets in the Vault.
    // MUST NOT show any variations depending on the caller.
    // MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
    // MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
    // MUST round down towards 0.
    // This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect
    // the “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and from.
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        if (totalSupply() == 0) return shares;
        return (shares * _freeFunds()) / totalSupply();
    }

    // function convertToAssets(uint256 shares) external view returns (uint256 assets);
    // function convertToShares(uint256 assets) external view returns (uint256 shares);
    // function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    // function maxDeposit(address receiver) external view returns (uint256 maxAssets);
    // function maxMint(address receiver) external view returns (uint256 maxShares);
    // function maxRedeem(address owner) external view returns (uint256 maxShares);
    // function maxWithdraw(address owner) external view returns (uint256 maxAssets);
    // function mint(uint256 shares, address receiver) external returns (uint256 assets);
    // function previewDeposit(uint256 assets) external view returns (uint256 shares);
    // function previewMint(uint256 shares) external view returns (uint256 assets);
    // function previewRedeem(uint256 shares) external view returns (uint256 assets);
    // function previewWithdraw(uint256 assets) external view returns (uint256 shares);
}
