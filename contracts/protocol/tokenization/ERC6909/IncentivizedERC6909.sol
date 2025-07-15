// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IMiniPoolRewarder} from "../../../../contracts/interfaces/IMiniPoolRewarder.sol";
import {ERC6909} from "lib/solady/src/tokens/ERC6909.sol";

/**
 * @title IncentivizedERC6909
 * @notice Basic ERC6909 implementation with incentives functionality.
 * @author Conclave, inspired by the Solady ERC6909 implementation and AAVEs incentivized ERC20
 */
abstract contract IncentivizedERC6909 is ERC6909 /*, IAERC6909 */ {
    /// @dev Mapping from `id` to token name.
    mapping(uint256 => string) private _name;
    /// @dev Mapping from `id` to token symbol.
    mapping(uint256 => string) private _symbol;
    /// @dev Mapping from `id` to token decimals.
    mapping(uint256 => uint8) private _decimals;
    /// @dev Mapping from `id` to token URI.
    mapping(uint256 => string) private _tokenURI;
    /// @dev Mapping from `id` to total supply.
    mapping(uint256 => uint256) private _totalSupply;

    constructor() {}

    /**
     * @dev Returns the name of the token for a given `id`.
     * @param id The token identifier.
     * @return The name of the token.
     */
    function name(uint256 id) public view override returns (string memory) {
        return (_name[id]);
    }

    /**
     * @dev Returns the symbol of the token for a given `id`.
     * @param id The token identifier.
     * @return The symbol of the token.
     */
    function symbol(uint256 id) public view override returns (string memory) {
        return (_symbol[id]);
    }

    /**
     * @dev Returns the number of decimals for a given `id`.
     * @param id The token identifier.
     * @return The number of decimals.
     */
    function decimals(uint256 id) public view virtual override returns (uint8) {
        return (_decimals[id]);
    }

    /**
     * @dev Returns the URI for a given `id`.
     * @param id The token identifier.
     * @return The token URI.
     */
    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        return (_tokenURI[id]);
    }

    /**
     * @dev Returns the total supply for a given `id`.
     * @param id The token identifier.
     * @return The total supply of tokens.
     */
    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return _totalSupply[id];
    }

    /**
     * @dev Decrements the total supply for a given `id` by `amt`.
     * @param id The token identifier.
     * @param amt The amount to decrement.
     * @return oldTotalSupply The total supply before decrementing.
     */
    function _decrementTotalSupply(uint256 id, uint256 amt)
        internal
        virtual
        returns (uint256 oldTotalSupply)
    {
        oldTotalSupply = _totalSupply[id];
        _totalSupply[id] = oldTotalSupply - amt;
    }

    /**
     * @dev Increments the total supply for a given `id` by `amt`.
     * @param id The token identifier.
     * @param amt The amount to increment.
     * @return oldTotalSupply The total supply before incrementing.
     */
    function _incrementTotalSupply(uint256 id, uint256 amt)
        internal
        virtual
        returns (uint256 oldTotalSupply)
    {
        oldTotalSupply = _totalSupply[id];
        _totalSupply[id] = oldTotalSupply + amt;
    }

    /**
     * @dev Sets the token URI for a given `id`.
     * @param id The token identifier.
     * @param tokenURI_ The URI to set.
     */
    function _setTokenURI(uint256 id, string memory tokenURI_) internal virtual {
        _tokenURI[id] = tokenURI_;
    }

    /**
     * @dev Sets the number of decimals for a given `id`.
     * @param id The token identifier.
     * @param decimals_ The number of decimals to set.
     */
    function _setDecimals(uint256 id, uint8 decimals_) internal virtual {
        _decimals[id] = decimals_;
    }

    /**
     * @dev Sets the symbol for a given `id`.
     * @param id The token identifier.
     * @param symbol_ The symbol to set.
     */
    function _setSymbol(uint256 id, string memory symbol_) internal virtual {
        _symbol[id] = symbol_;
    }

    /**
     * @dev Sets the name for a given `id`.
     * @param id The token identifier.
     * @param name_ The name to set.
     */
    function _setName(uint256 id, string memory name_) internal virtual {
        _name[id] = name_;
    }
}
