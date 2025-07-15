// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IERC20Detailed} from
    "../../../../contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {IRewarder} from "../../../../contracts/interfaces/IRewarder.sol";

/**
 * @title IncentivizedERC20
 * @notice Implementation of the basic ERC20 standard with incentives functionality.
 * @author Conclave
 * @dev This contract extends the basic ERC20 implementation with incentives tracking capabilities.
 */
abstract contract IncentivizedERC20 is IERC20, IERC20Detailed {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 internal _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Constructor that sets the token details.
     * @param name_ The name of the token.
     * @param symbol_ The symbol of the token.
     * @param decimals_ The number of decimals for token precision.
     */
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    /**
     * @dev Returns the name of the token.
     * @return The name of the token as a string.
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token.
     * @return The symbol of the token as a string.
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used for token precision.
     * @return The decimal places of the token.
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the total supply of the token.
     * @return The total token supply.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Returns the token balance of a given account.
     * @param account The address to query the balance for.
     * @return The token balance of the `account`.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev Abstract function to get the incentives controller.
     * @return The IRewarder interface of the incentives controller.
     * @dev Implemented by child aToken/debtToken to maintain backward compatibility.
     */
    function _getIncentivesController() internal view virtual returns (IRewarder);

    /**
     * @dev Transfers tokens from sender to recipient.
     * @param recipient The address receiving the tokens.
     * @param amount The amount of tokens to transfer.
     * @return A boolean indicating the success of the transfer.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    /**
     * @dev Returns the spending allowance of `spender` for `owner`'s tokens.
     * @param owner The address owning the tokens.
     * @param spender The address authorized to spend the tokens.
     * @return The remaining allowance of tokens.
     */
    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     * @param spender The address authorized to spend the tokens.
     * @param amount The amount of tokens to be approved for spending.
     * @return A boolean indicating the success of the approval.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev Transfers tokens from one address to another using the allowance mechanism.
     * @param sender The address to transfer tokens from.
     * @param recipient The address to transfer tokens to.
     * @param amount The amount of tokens to transfer.
     * @return A boolean indicating the success of the transfer.
     */
    function transferFrom(address sender, address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(sender, recipient, amount);
        uint256 oldAllowance = _allowances[sender][msg.sender];
        require(oldAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, msg.sender, oldAllowance - amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender`.
     * @param spender The address being authorized to spend tokens.
     * @param addedValue The amount by which to increase the allowance.
     * @return A boolean indicating the success of the operation.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender`.
     * @param spender The address being authorized to spend tokens.
     * @param subtractedValue The amount by which to decrease the allowance.
     * @return A boolean indicating the success of the operation.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        uint256 oldAllowance = _allowances[msg.sender][spender];
        require(oldAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(msg.sender, spender, oldAllowance - subtractedValue);
        return true;
    }

    /**
     * @dev Internal function to execute token transfers.
     * @param sender The address sending the tokens.
     * @param recipient The address receiving the tokens.
     * @param amount The amount of tokens to transfer.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 oldSenderBalance = _balances[sender];
        require(oldSenderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = oldSenderBalance - amount;
        uint256 oldRecipientBalance = _balances[recipient];
        _balances[recipient] = _balances[recipient] + amount;

        if (address(_getIncentivesController()) != address(0)) {
            uint256 currentTotalSupply = _totalSupply;
            _getIncentivesController().handleAction(sender, currentTotalSupply, oldSenderBalance);
            if (sender != recipient) {
                _getIncentivesController().handleAction(
                    recipient, currentTotalSupply, oldRecipientBalance
                );
            }
        }
    }

    /**
     * @dev Internal function to mint new tokens.
     * @param account The address receiving the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        uint256 oldTotalSupply = _totalSupply;
        _totalSupply = oldTotalSupply + amount;

        uint256 oldAccountBalance = _balances[account];
        _balances[account] = oldAccountBalance + amount;

        if (address(_getIncentivesController()) != address(0)) {
            _getIncentivesController().handleAction(account, oldTotalSupply, oldAccountBalance);
        }
    }

    /**
     * @dev Internal function to burn tokens.
     * @param account The address from which tokens will be burned.
     * @param amount The amount of tokens to burn.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 oldTotalSupply = _totalSupply;
        _totalSupply = oldTotalSupply - amount;

        uint256 oldAccountBalance = _balances[account];
        require(oldAccountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = oldAccountBalance - amount;

        if (address(_getIncentivesController()) != address(0)) {
            _getIncentivesController().handleAction(account, oldTotalSupply, oldAccountBalance);
        }
    }

    /**
     * @dev Internal function to handle token approvals.
     * @param owner The address granting the approval.
     * @param spender The address receiving the approval.
     * @param amount The amount of tokens approved.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Internal function to update the token name.
     * @param newName The new name to set.
     */
    function _setName(string memory newName) internal {
        _name = newName;
    }

    /**
     * @dev Internal function to update the token symbol.
     * @param newSymbol The new symbol to set.
     */
    function _setSymbol(string memory newSymbol) internal {
        _symbol = newSymbol;
    }

    /**
     * @dev Internal function to update the token decimals.
     * @param newDecimals The new number of decimals to set.
     */
    function _setDecimals(uint8 newDecimals) internal {
        _decimals = newDecimals;
    }

    /**
     * @dev Hook that is called before any transfer of tokens.
     * @param from The address tokens are transferred from.
     * @param to The address tokens are transferred to.
     * @param amount The amount of tokens being transferred.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}
