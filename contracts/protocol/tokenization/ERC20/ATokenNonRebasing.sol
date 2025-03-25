// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {AToken} from "../../../../contracts/protocol/tokenization/ERC20/AToken.sol";

/**
 * @title ERC20 Non Rebasing AToken wrapper
 * @author Cod3x - Beirao
 * @notice This contract wraps an AToken to provide a non-rebasing ERC20 interface.
 * @dev All operations are performed in terms of shares rather than underlying assets.
 */
contract ATokenNonRebasing {
    /**
     * @dev The underlying AToken contract that this wrapper interacts with.
     */
    AToken internal immutable _aToken;

    /**
     * @dev Emitted when `_value` tokens are moved from `_from` to `_to`.
     * @param from The address tokens are transferred from.
     * @param to The address tokens are transferred to.
     * @param value The amount of tokens transferred.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when `_owner` approves `_spender` to spend `_value` tokens.
     * @param owner The address granting the allowance.
     * @param spender The address receiving the allowance.
     * @param value The amount of tokens approved to spend.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Constructor that sets the wrapped AToken.
     * @param aToken The address of the AToken to wrap.
     */
    constructor(address aToken) {
        _aToken = AToken(aToken);
    }

    /**
     * @dev Returns the name of the token.
     * @return The name of the token.
     */
    function name() public view returns (string memory) {
        return string.concat("Wrapped ", _aToken.name());
    }

    /**
     * @dev Returns the symbol of the token.
     * @return The symbol of the token.
     */
    function symbol() public view returns (string memory) {
        return string.concat("w", _aToken.symbol());
    }

    /**
     * @dev Returns the number of decimals used for token precision.
     * @return The number of decimals.
     */
    function decimals() public view returns (uint8) {
        return _aToken.decimals();
    }

    /**
     * @dev Returns the total supply of shares.
     * @return The total supply of shares.
     */
    function totalSupply() public view virtual returns (uint256) {
        return _aToken.scaledTotalSupply();
    }

    /**
     * @dev Returns the address of the wrapped AToken.
     * @return The address of the wrapped AToken.
     */
    function ATOKEN_ADDRESS() public view returns (address) {
        return address(_aToken);
    }

    /**
     * @dev Returns the address of the underlying asset.
     * @return The address of the underlying asset.
     */
    function UNDERLYING_ASSET_ADDRESS() public view returns (address) {
        return _aToken.UNDERLYING_ASSET_ADDRESS();
    }

    /**
     * @dev Returns the reserve type of the underlying asset.
     * @return The reserve type (true for stable, false for variable).
     */
    function RESERVE_TYPE() public view returns (bool) {
        return _aToken.RESERVE_TYPE();
    }

    /**
     * @dev Returns the address of the LendingPool associated with the AToken.
     * @return The address of the LendingPool.
     */
    function getPool() external view returns (address) {
        return _aToken.getPool();
    }

    /**
     * @dev Returns the balance of shares for an account.
     * @param account The address to query the balance of.
     * @return The number of shares owned by `account`.
     */
    function balanceOf(address account) public view virtual returns (uint256) {
        return _aToken.scaledBalanceOf(account);
    }

    /**
     * @dev Transfers shares from sender to recipient.
     * @param recipient The address to receive the shares.
     * @param amountShare The amount of shares to transfer.
     * @return A boolean indicating whether the transfer was successful.
     */
    function transfer(address recipient, uint256 amountShare) public virtual returns (bool) {
        _aToken.transferShare(msg.sender, recipient, amountShare);

        emit Transfer(msg.sender, recipient, amountShare);
        return true;
    }

    /**
     * @dev Returns the remaining shares that `spender` is allowed to spend on behalf of `owner`.
     * @param owner The address that owns the shares.
     * @param spender The address that can spend the shares.
     * @return The number of shares `spender` can spend on behalf of `owner`.
     */
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _aToken.shareAllowances(owner, spender);
    }

    /**
     * @dev Sets `amountShare` as the allowance of `spender` over the caller's shares.
     * @param spender The address authorized to spend the shares.
     * @param amountShare The amount of shares to allow.
     * @return A boolean indicating whether the approval was successful.
     */
    function approve(address spender, uint256 amountShare) public virtual returns (bool) {
        _approve(msg.sender, spender, amountShare);
        return true;
    }

    /**
     * @dev Transfers shares from one address to another using the allowance mechanism.
     * @param sender The address to transfer shares from.
     * @param recipient The address to transfer shares to.
     * @param amountShare The amount of shares to transfer.
     * @return A boolean indicating whether the transfer was successful.
     */
    function transferFrom(address sender, address recipient, uint256 amountShare)
        public
        virtual
        returns (bool)
    {
        _aToken.transferShare(sender, recipient, amountShare);
        _approve(sender, msg.sender, _aToken.shareAllowances(sender, msg.sender) - amountShare);

        emit Transfer(sender, recipient, amountShare);

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     * @param spender The address being authorized to spend shares.
     * @param addedValue The amount of shares to increase the allowance by.
     * @return A boolean indicating whether the increase was successful.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _aToken.shareAllowances(msg.sender, spender) + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     * @param spender The address being authorized to spend shares.
     * @param subtractedValue The amount of shares to decrease the allowance by.
     * @return A boolean indicating whether the decrease was successful.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            msg.sender, spender, _aToken.shareAllowances(msg.sender, spender) - subtractedValue
        );
        return true;
    }

    /**
     * @dev Converts an amount of underlying assets to shares.
     * @param assetAmount The amount of assets to convert.
     * @return The equivalent amount in shares.
     */
    function convertToShares(uint256 assetAmount) external view returns (uint256) {
        return _aToken.convertToShares(assetAmount);
    }

    /**
     * @dev Converts an amount of shares to underlying assets.
     * @param shareAmount The amount of shares to convert.
     * @return The equivalent amount in assets.
     */
    function convertToAssets(uint256 shareAmount) external view returns (uint256) {
        return _aToken.convertToAssets(shareAmount);
    }

    /**
     * @dev Internal function to set the allowance for a spender.
     * @param owner The owner of the shares.
     * @param spender The spender being approved.
     * @param amount The amount of shares to approve.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _aToken.shareApprove(owner, spender, amount);

        emit Approval(owner, spender, amount);
    }
}
