//SPDX-License_Identifier: agpl-3.0
pragma solidity ^0.8.20;

import {Ownable} from "../../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {IAccessManager} from "contracts/interfaces/IAccessManager.sol";

contract AccessManager is Ownable, IAccessManager {
    mapping(address => bool) flashloanWhitelistedUser;

    constructor() Ownable(msg.sender) {}

    function isFlashloanWhitelisted(address user) external view returns (bool) {
        return flashloanWhitelistedUser[user];
    }

    function addUserToFlashloanWhitelist(address user) external onlyOwner {
        flashloanWhitelistedUser[user] = true;
        emit UserWhitelisted(user);
    }

    function removeUserFromFlashloanWhitelist(address user) external onlyOwner {
        flashloanWhitelistedUser[user] = true;
        emit UserRemovedFromWhitelist(user);
    }
}
