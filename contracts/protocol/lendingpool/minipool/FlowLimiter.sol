// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ILendingPoolAddressesProvider} from "../../../interfaces/ILendingPoolAddressesProvider.sol";
import {IMiniPoolAddressesProvider} from "../../../interfaces/IMiniPoolAddressesProvider.sol";
import {IMiniPool} from "../../../interfaces/IMiniPool.sol";
import {ILendingPool} from "../../../interfaces/ILendingPool.sol";
import {IVariableDebtToken} from "../../../interfaces/IVariableDebtToken.sol";
import {IERC20} from "../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {Errors} from "../../libraries/helpers/Errors.sol";

/**
 *
 * @title FlowLimiter
 * @notice This contract is used to Limit AND Facilitate the flow of funds into miniPools from the main Lending Pool
 *
 */
contract flowLimiter {
    ILendingPoolAddressesProvider public addressesProvider;
    IMiniPoolAddressesProvider public miniPoolAddressesProvider;
    ILendingPool public lendingPool;

    mapping(address => mapping(address => uint256)) public miniPoolMaxDebt;

    constructor(
        ILendingPoolAddressesProvider _addressesProvider,
        IMiniPoolAddressesProvider _miniPoolAddressesProvider,
        ILendingPool _lendingPool
    ) {
        lendingPool = _lendingPool;
        miniPoolAddressesProvider = _miniPoolAddressesProvider;
        addressesProvider = _addressesProvider;
    }

    function setFlowLimit(address asset, address miniPool, uint256 limit) external {
        require(msg.sender == address(miniPoolAddressesProvider), Errors.CALLER_NOT_POOL_ADMIN);
        miniPoolMaxDebt[asset][miniPool] = limit;
    }

    function getFlowLimit(address asset, address miniPool) external view returns (uint256) {
        return miniPoolMaxDebt[asset][miniPool];
    }

    function currentFlow(address asset, address miniPool) external view returns (uint256) {
        // `reserveType` always true since miniPool internal borrow is basically rehypothecation.
        return IERC20(lendingPool.getReserveData(asset, true).variableDebtTokenAddress).balanceOf(
            address(miniPool)
        );
    }
}
