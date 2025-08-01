// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {ERC20} from "contracts/dependencies/openzeppelin/contracts/ERC20.sol";

/**
 * @title ERC20Mintable
 * @dev ERC20 minting logic
 */
contract MintableERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _setupDecimals(decimals_);
    }

    /**
     * @dev Function to mint tokens
     * @param value The amount of tokens to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(address user, uint256 value) public returns (bool) {
        _mint(user, value);
        return true;
    }

    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
