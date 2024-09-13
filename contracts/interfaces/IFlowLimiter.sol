// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IMiniPool} from "./IMiniPool.sol";

interface IFlowLimiter {
    function setFlowLimit(address asset, address miniPool, uint256 limit) external;
    function getFlowLimit(address asset, address miniPool) external view returns (uint256);
    function currentFlow(address asset, address miniPool) external view returns (uint256);
}
