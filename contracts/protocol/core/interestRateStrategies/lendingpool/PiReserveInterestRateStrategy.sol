// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "../../../../../contracts/interfaces/IVariableDebtToken.sol";
import {ILendingPool} from "../../../../../contracts/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from
    "../../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IReserveInterestRateStrategy} from
    "../../../../../contracts/interfaces/IReserveInterestRateStrategy.sol";
import "../../../../../contracts/protocol/core/interestRateStrategies/BasePiReserveRateStrategy.sol";
import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";

/**
 * @title PiReserveInterestRateStrategy contract
 * @notice Implements the calculation of the interest rates using control theory.
 * @dev The model of interest rate is based Proportional Integrator (PI).
 * Admin needs to set an optimal utilization rate and this strategy will automatically
 * automatically adjust the interest rate according to the `Kp` and `Ki` variables.
 * @dev ATTENTION, this contract must no be used as a library. One PiReserveInterestRateStrategy
 * needs to be associated with only one market.
 * @author Cod3x
 */
contract PiReserveInterestRateStrategy is
    BasePiReserveRateStrategy,
    IReserveInterestRateStrategy
{
    using WadRayMath for uint256;
    using WadRayMath for int256;
    using PercentageMath for uint256;

    constructor(
        address provider,
        address asset,
        bool assetReserveType,
        int256 minControllerError,
        int256 maxITimeAmp,
        uint256 optimalUtilizationRate,
        uint256 kp,
        uint256 ki
    )
        BasePiReserveRateStrategy(
            provider,
            asset,
            assetReserveType,
            minControllerError,
            maxITimeAmp,
            optimalUtilizationRate,
            kp,
            ki
        )
    {}

    function _getLendingPool() internal view override returns (address) {
        return ILendingPoolAddressesProvider(_addressProvider).getLendingPool();
    }

    function getAvailableLiquidity(address, address aToken)
        public
        view
        override
        returns (uint256, address, uint256)
    {
        return (IAToken(aToken).getTotalManagedAssets(), address(0), 0);
    }

    // ----------- view -----------

    /**
     * @notice The view version of `calculateInterestRates()`.
     * @return currentLiquidityRate
     * @return currentVariableBorrowRate
     * @return utilizationRate
     */
    function getCurrentInterestRates() public view override returns (uint256, uint256, uint256) {
        // utilization
        DataTypes.ReserveData memory reserve =
            ILendingPool(_getLendingPool()).getReserveData(_asset, _assetReserveType);
        (uint256 availableLiquidity,,) = getAvailableLiquidity(_asset, reserve.aTokenAddress);
        uint256 totalVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress)
            .scaledTotalSupply().rayMul(reserve.variableBorrowIndex);
        uint256 utilizationRate = totalVariableDebt == 0
            ? 0
            : totalVariableDebt.rayDiv(availableLiquidity + totalVariableDebt);

        // borrow rate
        uint256 currentVariableBorrowRate =
            transferFunction(getControllerError(getNormalizedError(utilizationRate)));

        // liquity rate
        uint256 currentLiquidityRate = getLiquidityRate(
            currentVariableBorrowRate, utilizationRate, getReserveFactor(reserve.configuration)
        );

        return (currentLiquidityRate, currentVariableBorrowRate, utilizationRate);
    }

    // ----------- view -----------

    function baseVariableBorrowRate() public view override returns (uint256) {
        return uint256(transferFunction(type(int256).min));
    }

    function getMaxVariableBorrowRate() external pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations
     * @param asset The address of the asset
     * @param aToken The address of the reserve aToken
     * @param liquidityAdded The liquidity added during the operation
     * @param liquidityTaken The liquidity taken during the operation
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
     * @return currentLiquidityRate The liquidity rate
     * @return currentVariableBorrowRate The variable borrow rate
     *
     */
    function calculateInterestRates(
        address asset,
        address aToken,
        uint256 liquidityAdded, //! since this function is not view anymore we need to make sure liquidityAdded is added at the end
        uint256 liquidityTaken, //! since this function is not view anymore we need to make sure liquidityTaken is removed at the end
        uint256 totalVariableDebt,
        uint256 reserveFactor
    )
        external
        override
        onlyLendingPool
        returns (uint256 currentLiquidityRate, uint256 currentVariableBorrowRate)
    {
        (currentLiquidityRate, currentVariableBorrowRate,,,) = _calculateInterestRates(
            asset, aToken, liquidityAdded, liquidityTaken, totalVariableDebt, reserveFactor
        );
    }
}
