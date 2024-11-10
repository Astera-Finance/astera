// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {ERC20} from "../../../contracts/dependencies/openzeppelin/contracts/ERC20.sol";

/**
 * @title ERC20Mintable
 * @dev ERC20 minting logic
 */
contract MintableERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_)
    {
        _setupDecimals(decimals_);
    }

    /**
     * @dev Function to mint tokens
     * @param value The amount of tokens to mint.
     */
    function mint(uint256 value) public {
        _mint(_msgSender(), value);
    }

    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
