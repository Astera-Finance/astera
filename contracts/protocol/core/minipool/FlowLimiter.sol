// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {ILendingPoolAddressesProvider} from
    "../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IMiniPool} from "../../../../contracts/interfaces/IMiniPool.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {IFlowLimiter} from "../../../../contracts/interfaces/base/IFlowLimiter.sol";

/**
 * @title FlowLimiter
 * @notice This contract is used to limit and facilitate the flow of funds into miniPools
 * from the main Lending Pool.
 * @dev Implements flow control mechanisms to manage fund transfers between the main
 * Lending Pool and miniPools.
 * @author Cod3x
 */
contract FlowLimiter is IFlowLimiter {
    /// @notice The addresses provider for the mini pool.
    IMiniPoolAddressesProvider public immutable _miniPoolAddressesProvider;

    /// @notice The main lending pool contract.
    ILendingPool public immutable _lendingPool;

    /// @notice Mapping to track maximum debt limits for each miniPool per asset.
    mapping(address => mapping(address => uint256)) public _miniPoolMaxDebt;

    /**
     * @dev Constructor to initialize the FlowLimiter contract.
     * @param miniPoolAddressesProvider The address of the MiniPoolAddressesProvider contract.
     */
    constructor(IMiniPoolAddressesProvider miniPoolAddressesProvider) {
        _miniPoolAddressesProvider = miniPoolAddressesProvider;
        _lendingPool = ILendingPool(miniPoolAddressesProvider.getLendingPool());
    }

    /**
     * @dev Sets the flow limit for a specific asset and miniPool.
     * @param asset The address of the asset to set the limit for.
     * @param miniPool The address of the miniPool to set the limit for.
     * @param limit The maximum amount of debt allowed.
     */
    function setFlowLimit(address asset, address miniPool, uint256 limit) external {
        require(msg.sender == address(_miniPoolAddressesProvider), Errors.CALLER_NOT_POOL_ADMIN);
        require(currentFlow(asset, miniPool) < limit, Errors.VL_INVALID_AMOUNT); // To avoid overflow in interest calculation.
        _miniPoolMaxDebt[asset][miniPool] = limit;

        emit FlowLimitUpdated(asset, miniPool, limit);
    }

    /**
     * @dev Returns the current flow limit for a specific asset and miniPool.
     * @param asset The address of the asset to check.
     * @param miniPool The address of the miniPool to check.
     * @return The current flow limit, which is the maximum of current flow and set limit.
     */
    function getFlowLimit(address asset, address miniPool) public view returns (uint256) {
        uint256 currentFlow_ = currentFlow(asset, miniPool);
        uint256 miniPoolMaxDebt_ = _miniPoolMaxDebt[asset][miniPool];

        return currentFlow_ > miniPoolMaxDebt_ ? currentFlow_ : miniPoolMaxDebt_;
    }

    /**
     * @dev Returns the current flow amount for a specific asset and miniPool.
     * @param asset The address of the asset to check.
     * @param miniPool The address of the miniPool to check.
     * @return The current amount of debt flow.
     */
    function currentFlow(address asset, address miniPool) public view returns (uint256) {
        //`reserveType` always true since miniPool internal borrow is basically rehypothecation.
        return IERC20(_lendingPool.getReserveData(asset, true).variableDebtTokenAddress).balanceOf(
            address(miniPool)
        );
    }

    function revertIfFlowLimitReached(address asset, address miniPool, uint256 amount)
        external
        view
    {
        require(
            currentFlow(asset, miniPool) + amount <= getFlowLimit(asset, miniPool),
            Errors.VL_BORROW_FLOW_LIMIT_REACHED
        );
    }
}
