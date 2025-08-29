// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

interface ITwapOracle {
    function getAssetPrice(address _asset) external view returns (uint256);
    function getTokens() external view returns (address token0, address token1);
}
