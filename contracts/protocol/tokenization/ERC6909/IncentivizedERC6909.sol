// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {Context} from "contracts/dependencies/openzeppelin/contracts/Context.sol";
import {IMiniPoolRewarder} from "contracts/interfaces/IMiniPoolRewarder.sol";
import {ERC6909} from "lib/solady/src/tokens/ERC6909.sol";

/**
 * @title ERC6909
 * @notice Basic ERC6909 implementation
 * @author Cod3x, inspired by the Solady ERC6909 implementation and AAVEs incentivized ERC20
 *
 */
abstract contract IncentivizedERC6909 is Context, ERC6909 {
    ///     id      => name

    mapping(uint256 => string) private _name;
    ///     id      => symbol
    mapping(uint256 => string) private _symbol;
    ///     id      => decimals
    mapping(uint256 => uint8) private _decimals;
    ///     id      => tokenURI
    mapping(uint256 => string) private _tokenURI;
    ///     id      => totalSupply
    mapping(uint256 => uint256) private _totalSupply;

    constructor() {}

    function name(uint256 id) public view override returns (string memory) {
        return (_name[id]);
    }

    function symbol(uint256 id) public view override returns (string memory) {
        return (_symbol[id]);
    }

    function decimals(uint256 id) public view virtual override returns (uint8) {
        return (_decimals[id]);
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        return (_tokenURI[id]);
    }

    function _getIncentivesController() internal view virtual returns (IMiniPoolRewarder);

    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return _totalSupply[id];
    }

    function _decrementTotalSupply(uint256 id, uint256 amt)
        internal
        virtual
        returns (uint256 oldTotalSupply)
    {
        oldTotalSupply = _totalSupply[id];
        _totalSupply[id] = _totalSupply[id] - amt;
    }

    function _incrementTotalSupply(uint256 id, uint256 amt)
        internal
        virtual
        returns (uint256 oldTotalSupply)
    {
        oldTotalSupply = _totalSupply[id];
        _totalSupply[id] = _totalSupply[id] + amt;
    }

    function _setTokenURI(uint256 id, string memory tokenURI_) internal virtual {
        _tokenURI[id] = tokenURI_;
    }

    function _setDecimals(uint256 id, uint8 decimals_) internal virtual {
        _decimals[id] = decimals_;
    }

    function _setSymbol(uint256 id, string memory symbol_) internal virtual {
        _symbol[id] = symbol_;
    }

    function _setName(uint256 id, string memory name_) internal virtual {
        _name[id] = name_;
    }
}
