// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IVariableDebtToken} from "../../../../contracts/interfaces/IVariableDebtToken.sol";
import {WadRayMath} from "../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {IRewarder} from "../../../../contracts/interfaces/IRewarder.sol";
import {VersionedInitializable} from
    "../../../../contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {IncentivizedERC20} from
    "../../../../contracts/protocol/tokenization/ERC20/IncentivizedERC20.sol";

/**
 * @title VariableDebtToken
 * @author Conclave
 * @notice Implements a variable debt token to track the borrowing positions of users at variable rate mode.
 */
contract VariableDebtToken is
    IncentivizedERC20("DEBTTOKEN_IMPL", "DEBTTOKEN_IMPL", 0),
    VersionedInitializable,
    IVariableDebtToken
{
    using WadRayMath for uint256;

    /// @notice The revision number of the debt token implementation.
    uint256 public constant DEBT_TOKEN_REVISION = 0x1;

    /// @notice The type of reserve this debt token represents.
    bool public RESERVE_TYPE;

    /// @notice The lending pool contract.
    ILendingPool internal _pool;

    /// @notice The address of the underlying asset.
    address internal _underlyingAsset;

    /// @notice The incentives controller contract.
    IRewarder internal _incentivesController;

    /// @notice Mapping of borrowing allowances between addresses.
    mapping(address => mapping(address => uint256)) internal _borrowAllowances;

    constructor() {
        _blockInitializing();
    }

    /**
     * @dev Only lending pool can call functions marked by this modifier.
     */
    modifier onlyLendingPool() {
        require(msg.sender == address(_getLendingPool()), Errors.AT_CALLER_MUST_BE_LENDING_POOL);
        _;
    }

    /**
     * @notice Initializes the debt token with its core configuration.
     * @dev Can only be called once due to initializer modifier.
     * @param pool The address of the lending pool where this token will be used.
     * @param underlyingAsset The address of the underlying asset of this token.
     * @param incentivesController The smart contract managing potential incentives distribution.
     * @param debtTokenDecimals The decimals of the debt token, same as the underlying asset's.
     * @param reserveType The type of reserve this debt token represents.
     * @param debtTokenName The name of the token.
     * @param debtTokenSymbol The symbol of the token.
     * @param params Additional initialization parameters.
     */
    function initialize(
        ILendingPool pool,
        address underlyingAsset,
        IRewarder incentivesController,
        uint8 debtTokenDecimals,
        bool reserveType,
        string memory debtTokenName,
        string memory debtTokenSymbol,
        bytes calldata params
    ) public override initializer {
        _setName(debtTokenName);
        _setSymbol(debtTokenSymbol);
        _setDecimals(debtTokenDecimals);

        _pool = pool;
        _underlyingAsset = underlyingAsset;
        _incentivesController = incentivesController;

        RESERVE_TYPE = reserveType;

        emit Initialized(
            underlyingAsset,
            address(pool),
            address(incentivesController),
            debtTokenDecimals,
            reserveType,
            debtTokenName,
            debtTokenSymbol,
            params
        );
    }

    /**
     * @notice Gets the revision of the variable debt token implementation.
     * @return The debt token implementation revision number.
     */
    function getRevision() internal pure virtual override returns (uint256) {
        return DEBT_TOKEN_REVISION;
    }

    /**
     * @notice Calculates the accumulated debt balance of the user.
     * @param user The address of the user to check balance for.
     * @return The current debt balance of the user.
     */
    function balanceOf(address user) public view virtual override(IncentivizedERC20, IERC20) returns (uint256) {
        uint256 scaledBalance = super.balanceOf(user);

        if (scaledBalance == 0) {
            return 0;
        }

        return scaledBalance.rayMul(
            _pool.getReserveNormalizedVariableDebt(_underlyingAsset, RESERVE_TYPE)
        );
    }

    /**
     * @notice Mints debt token to the `onBehalfOf` address.
     * @dev Only callable by the LendingPool.
     * @param user The address receiving the borrowed underlying, being the delegatee in case of credit delegate, or same as `onBehalfOf` otherwise.
     * @param onBehalfOf The address receiving the debt tokens.
     * @param amount The amount of debt being minted.
     * @param index The variable debt index of the reserve.
     * @return A boolean indicating if the previous balance of the user was 0.
     */
    function mint(address user, address onBehalfOf, uint256 amount, uint256 index)
        external
        override
        onlyLendingPool
        returns (bool)
    {
        if (user != onBehalfOf) {
            _decreaseBorrowAllowance(onBehalfOf, user, amount);
        }

        uint256 previousBalance = super.balanceOf(onBehalfOf);
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.AT_INVALID_MINT_AMOUNT);

        _mint(onBehalfOf, amountScaled);

        emit Transfer(address(0), onBehalfOf, amount);
        emit Mint(user, onBehalfOf, amount, index);

        return previousBalance == 0;
    }

    /**
     * @notice Burns user variable debt.
     * @dev Only callable by the LendingPool.
     * @param user The user whose debt is getting burned.
     * @param amount The amount getting burned.
     * @param index The variable debt index of the reserve.
     */
    function burn(address user, uint256 amount, uint256 index) external override onlyLendingPool {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.AT_INVALID_BURN_AMOUNT);

        _burn(user, amountScaled);

        emit Transfer(user, address(0), amount);
        emit Burn(user, amount, index);
    }

    /**
     * @notice Delegates borrowing power to a user on the specific debt token.
     * @param delegatee The address receiving the delegated borrowing power.
     * @param amount The maximum amount being delegated.
     * @dev Delegation will still respect the liquidation constraints (even if delegated, a delegatee cannot force a delegator HF to go below 1).
     */
    function approveDelegation(address delegatee, uint256 amount) external override {
        _borrowAllowances[msg.sender][delegatee] = amount;
        emit BorrowAllowanceDelegated(msg.sender, delegatee, _getUnderlyingAssetAddress(), amount);
    }

    /**
     * @notice Returns the borrow allowance of the user.
     * @param fromUser The user giving allowance.
     * @param toUser The user to give allowance to.
     * @return The current allowance of `toUser`.
     */
    function borrowAllowance(address fromUser, address toUser)
        external
        view
        override
        returns (uint256)
    {
        return _borrowAllowances[fromUser][toUser];
    }

    /**
     * @notice Being non transferrable, the debt token does not implement any of the standard ERC20 functions for transfer and allowance.
     * @dev This function reverts when called.
     */
    function transfer(address, uint256) public virtual override(IncentivizedERC20, IERC20) returns (bool) {
        revert("TRANSFER_NOT_SUPPORTED");
    }

    /**
     * @notice Being non transferrable, the debt token does not implement any of the standard ERC20 functions for transfer and allowance.
     * @dev This function reverts when called.
     */
    function allowance(address, address) public view virtual override(IncentivizedERC20, IERC20) returns (uint256) {
        revert("ALLOWANCE_NOT_SUPPORTED");
    }

    /**
     * @notice Being non transferrable, the debt token does not implement any of the standard ERC20 functions for transfer and allowance.
     * @dev This function reverts when called.
     */
    function approve(address, uint256) public virtual override(IncentivizedERC20, IERC20) returns (bool) {
        revert("APPROVAL_NOT_SUPPORTED");
    }

    /**
     * @notice Being non transferrable, the debt token does not implement any of the standard ERC20 functions for transfer and allowance.
     * @dev This function reverts when called.
     */
    function transferFrom(address, address, uint256) public virtual override(IncentivizedERC20, IERC20) returns (bool) {
        revert("TRANSFER_NOT_SUPPORTED");
    }

    /**
     * @notice Being non transferrable, the debt token does not implement any of the standard ERC20 functions for transfer and allowance.
     * @dev This function reverts when called.
     */
    function increaseAllowance(address, uint256) public virtual override returns (bool) {
        revert("ALLOWANCE_NOT_SUPPORTED");
    }

    /**
     * @notice Being non transferrable, the debt token does not implement any of the standard ERC20 functions for transfer and allowance.
     * @dev This function reverts when called.
     */
    function decreaseAllowance(address, uint256) public virtual override returns (bool) {
        revert("ALLOWANCE_NOT_SUPPORTED");
    }

    /**
     * @notice Returns the principal debt balance of the user.
     * @param user The address of the user.
     * @return The debt balance of the user since the last burn/mint action.
     */
    function scaledBalanceOf(address user) public view virtual override returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @notice Returns the total supply of the variable debt token.
     * @return The total supply representing the total debt accrued by users.
     */
    function totalSupply() public view virtual override(IncentivizedERC20, IERC20) returns (uint256) {
        return super.totalSupply().rayMul(
            _pool.getReserveNormalizedVariableDebt(_underlyingAsset, RESERVE_TYPE)
        );
    }

    /**
     * @notice Returns the scaled total supply of the variable debt token.
     * @return The scaled total supply representing sum(debt/index).
     */
    function scaledTotalSupply() public view virtual override returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @notice Returns the principal balance of the user and principal total supply.
     * @param user The address of the user.
     * @return The principal balance of the user.
     * @return The principal total supply.
     */
    function getScaledUserBalanceAndSupply(address user)
        external
        view
        override
        returns (uint256, uint256)
    {
        return (super.balanceOf(user), super.totalSupply());
    }

    /**
     * @notice Returns the address of the underlying asset of this debt token.
     * @return The address of the underlying asset.
     */
    function UNDERLYING_ASSET_ADDRESS() public view returns (address) {
        return _underlyingAsset;
    }

    /**
     * @notice Returns the address of the incentives controller contract.
     * @return The incentives controller address.
     */
    function getIncentivesController() external view override returns (IRewarder) {
        return _getIncentivesController();
    }

    /**
     * @notice Returns the address of the lending pool where this debt token is used.
     * @return The lending pool address.
     */
    function POOL() public view returns (ILendingPool) {
        return _pool;
    }

    /**
     * @notice Internal function to get the incentives controller.
     * @return The incentives controller interface.
     */
    function _getIncentivesController() internal view override returns (IRewarder) {
        return _incentivesController;
    }

    /**
     * @notice Internal function to get the underlying asset address.
     * @return The address of the underlying asset.
     */
    function _getUnderlyingAssetAddress() internal view returns (address) {
        return _underlyingAsset;
    }

    /**
     * @notice Internal function to get the lending pool.
     * @return The lending pool interface.
     */
    function _getLendingPool() internal view returns (ILendingPool) {
        return _pool;
    }

    /**
     * @notice Decreases the borrow allowance for a delegatee.
     * @param delegator The address of the delegator.
     * @param delegatee The address of the delegatee.
     * @param amount The amount to decrease the allowance by.
     */
    function _decreaseBorrowAllowance(address delegator, address delegatee, uint256 amount)
        internal
    {
        uint256 oldAllowance = _borrowAllowances[delegator][delegatee];
        require(oldAllowance >= amount, Errors.AT_BORROW_ALLOWANCE_NOT_ENOUGH);
        uint256 newAllowance = oldAllowance - amount;

        _borrowAllowances[delegator][delegatee] = newAllowance;

        emit BorrowAllowanceDelegated(
            delegator, delegatee, _getUnderlyingAssetAddress(), newAllowance
        );
    }

    /**
     * @notice Sets a new incentives controller.
     * @dev Only callable by the LendingPool.
     * @param newController The address of the new controller.
     */
    function setIncentivesController(address newController) external override onlyLendingPool {
        require(newController != address(0), Errors.AT_INVALID_CONTROLLER);
        _incentivesController = IRewarder(newController);

        emit IncentivesControllerSet(newController);
    }
}
