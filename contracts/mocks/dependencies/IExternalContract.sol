// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IExternalContract {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external returns (uint256 returned);
    function withdrawAll() external returns (uint256 returned);

    //returns the balance of all tokens managed by the strategy
    function balance() external view returns (uint256);

    //returns the address of the token that the strategy needs to operate
    function want() external view returns (address);
}