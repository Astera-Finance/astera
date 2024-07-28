// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./properties/ATokenERC6909Prop.sol";
import "./properties/ATokenProp.sol";
import "./properties/DebtTokenProp.sol";
import "./properties/LendingPoolProp.sol";
import "./properties/MiniPoolProp.sol";

// Users are defined in users
// Admin is address(this)
contract PropertiesMain is
    ATokenERC6909Prop,
    ATokenProp,
    DebtTokenProp,
    LendingPoolProp,
    MiniPoolProp
{
    constructor() payable {}
}
