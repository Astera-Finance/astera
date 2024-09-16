// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IERC20} from "contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IAERC6909} from "contracts/interfaces/IAERC6909.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";
import {IMiniPoolReserveInterestRateStrategy} from
    "contracts/interfaces/IMiniPoolReserveInterestRateStrategy.sol";
import {
    BasePiReserveRateStrategy,
    WadRayMath,
    PercentageMath,
    DataTypes
} from "contracts/protocol/lendingpool/interestRateStrategies/BasePiReserveRateStrategy.sol";

/**
 * @title PiReserveInterestRateStrategy contract
 * @notice Implements the calculation of the interest rates using control theory.
 * @dev The model of interest rate is based Proportional Integrator (PI).
 * Admin needs to set an optimal utilization rate and this strategy will automatically
 * automatically adjust the interest rate according to the `Kp` and `Ki` variables.
 * @dev ATTENTION, this contract must no be used as a library. One PiReserveInterestRateStrategy
 * needs to be associated with only one market.
 * @author ByteMasons
 */
contract MiniPoolPiReserveInterestRateStrategy is
    BasePiReserveRateStrategy,
    IMiniPoolReserveInterestRateStrategy
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
        return IMiniPoolAddressesProvider(_addressProvider).getMiniPool(0);
    }

    function getAvailableLiquidity(address asset, address aToken)
        public
        view
        override
        returns (uint256)
    {
        uint256 availableLiquidity = IERC20(asset).balanceOf(aToken);

        // IAERC6909 aErc6909Token =
        //     IAERC6909(IMiniPoolAddressesProvider(_provider).getMiniPoolToAERC6909(_getLendingPool()));
        // uint256 availableLiquidity = aErc6909Token.totalSupply(reserve.variableDebtTokenID);
        return availableLiquidity;
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
        IAERC6909 aErc6909Token = IAERC6909(
            IMiniPoolAddressesProvider(_addressProvider).getMiniPoolToAERC6909(_getLendingPool())
        );
        DataTypes.MiniPoolReserveData memory reserve =
            IMiniPool(_getLendingPool()).getReserveData(_asset, _assetReserveType);
        uint256 availableLiquidity = IERC20(_asset).balanceOf(reserve.aTokenAddress);
        uint256 totalVariableDebt = aErc6909Token.totalSupply(reserve.variableDebtTokenID);
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

    function calculateInterestRates(
        address reserve,
        address aToken,
        uint256 liquidityAdded, //! since this function is not view anymore we need to make sure liquidityAdded is added at the end
        uint256 liquidityTaken, //! since this function is not view anymore we need to make sure liquidityTaken is removed at the end
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external override onlyLendingPool returns (uint256, uint256) {
        return _calculateInterestRates(
            reserve, aToken, liquidityAdded, liquidityTaken, totalVariableDebt, reserveFactor
        );
    }

    function calculateInterestRates(
        address,
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) internal returns (uint256, uint256) {
        return _calculateInterestRates(address(0), availableLiquidity, totalVariableDebt, reserveFactor);
    }
}
