//SPDX-License_Identifier: agpl-3.0
pragma solidity ^0.8.20;

import {Ownable} from "../../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";

contract AccessManager is Ownable {
    mapping(address => bool) flashloanWhitelistedUser;

    constructor() Ownable(msg.sender) {}

    function isFlashloanWhitelisted(address user) external view returns (bool) {
        return flashloanWhitelistedUser[user];
    }

    function setFlashloanWhitelistedUser(address user) external onlyOwner {}
}
