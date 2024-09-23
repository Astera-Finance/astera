// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {AToken} from "../../../../contracts/protocol/tokenization/ERC20/AToken.sol";

/**
 * @title ERC20 Non Rebasing AToken wrapper
 * @author Cod3x - Beirao
 */
contract ATokenNonRebasing {
    AToken internal immutable _aToken;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    constructor(address aToken) {
        _aToken = AToken(aToken);
    }

    /**
     * @return The name of the share
     *
     */
    function name() public view returns (string memory) {
        return _aToken.name();
    }

    /**
     * @return The symbol of the share
     *
     */
    function symbol() public view returns (string memory) {
        return _aToken.symbol();
    }

    /**
     * @return The decimals of the share
     *
     */
    function decimals() public view returns (uint8) {
        return _aToken.decimals();
    }

    /**
     * @return The total supply of the share
     *
     */
    function totalSupply() public view virtual returns (uint256) {
        return _aToken.scaledTotalSupply();
    }

    /**
     * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     */
    function ATOKEN_ADDRESS() public view returns (address) {
        return address(_aToken);
    }

    /**
     * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     */
    function UNDERLYING_ASSET_ADDRESS() public view returns (address) {
        return _aToken.UNDERLYING_ASSET_ADDRESS();
    }

    /**
     * @dev Returns the address of the LendingPool address associated with the aToken.
     */
    function getPool() external view returns (address) {
        return _aToken.getPool();
    }

    /**
     * @return The balance of the share
     *
     */
    function balanceOf(address account) public view virtual returns (uint256) {
        return _aToken.scaledBalanceOf(account);
    }

    /**
     * @dev Executes a transfer of shares from msg.sender to recipient
     * @param recipient The recipient of the tokens
     * @param amountShare The amount of shares being transferred
     * @return `true` if the transfer succeeds, `false` otherwise
     *
     */
    function transfer(address recipient, uint256 amountShare) public virtual returns (bool) {
        _aToken.transferShare(msg.sender, recipient, amountShare);

        emit Transfer(msg.sender, recipient, amountShare);
        return true;
    }

    /**
     * @dev Returns the allowance of spender on the tokens owned by owner
     * @param owner The owner of the tokens
     * @param spender The user allowed to spend the owner's tokens
     * @return The amount of owner's shares spender is allowed to spend
     *
     */
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _aToken.shareAllowances(owner, spender);
    }

    /**
     * @dev Allows `spender` to spend the tokens owned by msg.sender
     * @param spender The user allowed to spend msg.sender tokens
     * @param amountShare The amount of shares being approved
     * @return `true`
     *
     */
    function approve(address spender, uint256 amountShare) public virtual returns (bool) {
        _approve(msg.sender, spender, amountShare);
        return true;
    }

    /**
     * @dev Executes a transfer of token from sender to recipient, if msg.sender is allowed to do so
     * @param sender The owner of the tokens
     * @param recipient The recipient of the tokens
     * @param amountShare The amount of shares being transferred
     * @return `true` if the transfer succeeds, `false` otherwise
     *
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
     * @dev Increases the allowance of spender to spend msg.sender tokens
     * @param spender The user allowed to spend on behalf of msg.sender
     * @param addedValue The amount being added to the allowance
     * @return `true`
     *
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _aToken.shareAllowances(msg.sender, spender) + addedValue);
        return true;
    }

    /**
     * @dev Decreases the allowance of spender to spend msg.sender tokens
     * @param spender The user allowed to spend on behalf of msg.sender
     * @param subtractedValue The amount being subtracted to the allowance
     * @return `true`
     *
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

    function convertToShares(uint256 assetAmount) external view returns (uint256) {
        return _aToken.convertToShares(assetAmount);
    }

    function convertToAssets(uint256 shareAmount) external view returns (uint256) {
        return _aToken.convertToAssets(shareAmount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _aToken.shareApprove(owner, spender, amount);

        emit Approval(owner, spender, amount);
    }
}
