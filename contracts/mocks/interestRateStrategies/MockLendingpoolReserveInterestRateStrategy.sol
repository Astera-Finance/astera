// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IReserveInterestRateStrategy} from
    "../../../contracts/interfaces/IReserveInterestRateStrategy.sol";
import {WadRayMath} from "../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {ILendingPoolAddressesProvider} from
    "../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IERC20} from "../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IAToken} from "../../../contracts/interfaces/IAToken.sol";
import {Errors} from "../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title MockLendingpoolReserveInterestRateStrategy contract
 * @author Cod3x
 *
 */
contract MockLendingpoolReserveInterestRateStrategy {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    ILendingPoolAddressesProvider public immutable addressesProvider;

    uint256 public currentRate;

    constructor(ILendingPoolAddressesProvider provider_, uint256 initialRate_) {
        addressesProvider = provider_;
        currentRate = initialRate_;
    }

    function setRate(uint256 nextRate_) public {
        currentRate = nextRate_;
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations
     * @param reserve The address of the reserve
     * @param liquidityAdded The liquidity added during the operation
     * @param liquidityTaken The liquidity taken during the operation
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
     * @return The liquidity rate and the variable borrow rate
     *
     */
    function calculateInterestRates(
        address reserve,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external view returns (uint256, uint256) {
        uint256 availableLiquidity = IAToken(aToken).getTotalManagedAssets();
        if (availableLiquidity + liquidityAdded < liquidityTaken) {
            revert(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW);
        }
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;

        return calculateInterestRates(reserve, availableLiquidity, totalVariableDebt, reserveFactor);
    }

    struct CalcInterestRatesLocalVars {
        uint256 totalDebt;
        uint256 currentVariableBorrowRate;
        uint256 currentLiquidityRate;
        uint256 utilizationRate;
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations.
     * NOTE This function is kept for compatibility with the previous DefaultInterestRateStrategy interface.
     * New protocol implementation uses the new calculateInterestRates() interface
     * @param availableLiquidity The liquidity available in the corresponding aToken
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
     * @return The liquidity rateand the variable borrow rate
     *
     */
    function calculateInterestRates(
        address,
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) public view returns (uint256, uint256) {
        CalcInterestRatesLocalVars memory vars;

        vars.totalDebt = totalVariableDebt;
        vars.currentVariableBorrowRate = currentRate;
        vars.currentLiquidityRate = 0;

        vars.utilizationRate =
            vars.totalDebt == 0 ? 0 : vars.totalDebt.rayDiv(availableLiquidity + vars.totalDebt);

        vars.currentLiquidityRate = vars.currentVariableBorrowRate.rayMul(vars.utilizationRate)
            .percentMul(PercentageMath.PERCENTAGE_FACTOR - reserveFactor);

        return (vars.currentLiquidityRate, vars.currentVariableBorrowRate);
    }
}
