// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IScaledBalanceToken} from "../../contracts/interfaces/base/IScaledBalanceToken.sol";
import {IInitializableDebtToken} from "../../contracts/interfaces/base/IInitializableDebtToken.sol";
import {IRewarder} from "../../contracts/interfaces/IRewarder.sol";

/**
 * @title IVariableDebtToken interface.
 * @author Conclave
 */
interface IVariableDebtToken is IScaledBalanceToken, IInitializableDebtToken {
    /**
     * @dev Emitted after the mint action
     * @param user The address performing the mint
     * @param onBehalfOf The address of the user on which behalf minting has been performed
     * @param amount The amount to be minted
     * @param index The last index of the reserve
     */
    event Mint(address indexed user, address indexed onBehalfOf, uint256 amount, uint256 index);

    /**
     * @dev Emitted when variable debt is burnt
     * @param user The user which debt has been burned
     * @param amount The amount of debt being burned
     * @param index The index of the user
     */
    event Burn(address indexed user, uint256 amount, uint256 index);

    /**
     * @dev Emitted when a borrower delegates borrowing power to a delegatee
     * @param fromUser The address of the delegator
     * @param toUser The address of the delegatee receiving the borrowing power
     * @param asset The address of the underlying asset being delegated
     * @param amount The amount of borrowing power being delegated
     */
    event BorrowAllowanceDelegated(
        address indexed fromUser, address indexed toUser, address asset, uint256 amount
    );

    /**
     * @dev Emitted when the incentives controller is set.
     * @param newController The new incentives controller address.
     */
    event IncentivesControllerSet(address newController);

    function mint(address user, address onBehalfOf, uint256 amount, uint256 index)
        external
        returns (bool);

    function burn(address user, uint256 amount, uint256 index) external;

    function getIncentivesController() external view returns (IRewarder);

    function setIncentivesController(address newController) external;

    function approveDelegation(address delegatee, uint256 amount) external;

    function borrowAllowance(address fromUser, address toUser) external view returns (uint256);
}
