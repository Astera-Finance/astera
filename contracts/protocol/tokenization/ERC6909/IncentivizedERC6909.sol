// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {Context} from '../../../dependencies/openzeppelin/contracts/Context.sol';
import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IRewarder} from '../../../interfaces/IRewarder.sol';
import {ERC6909} from '../../../dependencies/solady/ERC6909.sol';

/**
 * @title ERC6909
 * @notice Basic ERC6909 implementation
 * @author Granary, inspired by the Solady ERC6909 implementation and AAVEs incentivized ERC20
 **/
abstract contract IncentivizedERC6909 is Context, ERC6909{
    using SafeMath for uint256;
    ///     id      => name
    mapping(uint256 => string)  private _name;
    ///     id      => symbol   
    mapping(uint256 => string)  private _symbol;
    ///     id      => decimals
    mapping(uint256 => uint8)   private _decimals;
    ///     id      => tokenURI
    mapping(uint256 => string)  private _tokenURI;

    function name(uint256 id) public view override returns (string memory){
        return(_name[id]);
    }

    function symbol(uint256 id) public view override returns (string memory){
        return(_symbol[id]);
    }

    function decimals(uint256 id) public view override returns (uint8){
        return(_decimals[id]);
    }

    function tokenURI(uint256 id) public view override returns(string memory){
        return(_tokenURI[id]);
    }



}
