// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IReserveInterestRateStrategy} from
    "../../../../../contracts/interfaces/IReserveInterestRateStrategy.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {ILendingPoolAddressesProvider} from
    "../../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title FixReserveInterestRateStrategy contract.
 * @notice Implements fix interest rate strategy.
 * @dev The rate is controlled by `updateBorrowRate` (an admin restricted function).
 * @author Conclave - Beirao
 */
contract FixReserveInterestRateStrategy is IReserveInterestRateStrategy {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    /// @dev Address of the lending pool addresses provider.
    ILendingPoolAddressesProvider public immutable addressesProvider_;

    /// @dev The interest rate.
    uint256 public borrowRate_;

    /// @dev Emitted when the borrow rate is updated.
    event BorrowRateUpdated(uint256 newBorrowRate);

    /**
     * @notice Initializes the interest rate strategy contract.
     * @param provider Address of the lending pool addresses provider.
     * @param initialBorrowRate The initial borrow rate.
     */
    constructor(ILendingPoolAddressesProvider provider, uint256 initialBorrowRate) {
        addressesProvider_ = provider;
        borrowRate_ = initialBorrowRate;
    }

    /**
     * @notice Updates the borrow rate.
     * @dev Only the pool admin can update the borrow rate.
     * @param newBorrowRate The new borrow rate.
     */
    function updateBorrowRate(uint256 newBorrowRate) external {
        if (msg.sender != addressesProvider_.getPoolAdmin()) {
            revert(Errors.VL_CALLER_NOT_POOL_ADMIN);
        }
        borrowRate_ = newBorrowRate;
        emit BorrowRateUpdated(newBorrowRate);
    }

    /// @notice Returns the base variable borrow rate.
    function baseVariableBorrowRate() external view override returns (uint256) {
        return borrowRate_;
    }

    /// @notice Returns the maximum variable borrow rate.
    function getMaxVariableBorrowRate() external view override returns (uint256) {
        return borrowRate_;
    }

    /**
     * @notice Calculates the interest rates depending on the reserve's state and configurations.
     * @param asset The address of the asset.
     * @param aToken The address of the reserve aToken.
     * @param liquidityAdded The liquidity added during the operation.
     * @param liquidityTaken The liquidity taken during the operation.
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate.
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market.
     * @return The liquidity rate and the variable borrow rate.
     */
    function calculateInterestRates(
        address asset,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external view override returns (uint256, uint256) {
        uint256 availableLiquidity = IAToken(aToken).getTotalManagedAssets();
        if (availableLiquidity + liquidityAdded < liquidityTaken) {
            revert(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW);
        }
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;

        return calculateInterestRates(asset, availableLiquidity, totalVariableDebt, reserveFactor);
    }

    /**
     * @notice Calculates the interest rates depending on the reserve's state and configurations.
     * @dev This function is kept for compatibility with the previous DefaultInterestRateStrategy interface.
     * New protocol implementation uses the new calculateInterestRates() interface.
     * @param availableLiquidity The liquidity available in the corresponding aToken.
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate.
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market.
     * @return The liquidity rate and the variable borrow rate.
     */
    function calculateInterestRates(
        address,
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) public view returns (uint256, uint256) {
        uint256 currentBorrowRate = borrowRate_;
        uint256 utilizationRate = totalVariableDebt == 0
            ? 0
            : totalVariableDebt.rayDiv(availableLiquidity + totalVariableDebt);

        uint256 currentLiquidityRate = currentBorrowRate.rayMul(utilizationRate).percentMul(
            PercentageMath.PERCENTAGE_FACTOR - reserveFactor
        );

        return (currentLiquidityRate, currentBorrowRate);
    }
}
