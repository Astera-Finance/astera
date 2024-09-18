// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";

interface IFlowLimiter {
    function setFlowLimit(address asset, address miniPool, uint256 limit) external;
    function getFlowLimit(address asset, address miniPool) external view returns (uint256);
    function currentFlow(address asset, address miniPool) external view returns (uint256);
}
