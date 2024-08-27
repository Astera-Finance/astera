// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IERC20} from "../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {IVariableDebtToken} from "contracts/interfaces/IVariableDebtToken.sol";
import {IAERC6909} from "contracts/interfaces/IAERC6909.sol";
import {VariableDebtToken} from "contracts/protocol/tokenization/VariableDebtToken.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";
import {IMiniPoolReserveInterestRateStrategy} from
    "../../../interfaces/IMiniPoolReserveInterestRateStrategy.sol";
import "./BasePiReserveRateStrategy.sol";

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

    function getAvailableLiquidity(address asset) public view override returns (uint256) {
        DataTypes.MiniPoolReserveData memory reserve =
            IMiniPool(_getLendingPool()).getReserveData(asset, _assetReserveType);
        uint256 availableLiquidity = IERC20(asset).balanceOf(reserve.aTokenAddress);

        // IAERC6909 aErc6909Token =
        //     IAERC6909(IMiniPoolAddressesProvider(_provider).getMiniPoolToAERC6909(_getLendingPool()));
        // uint256 availableLiquidity = aErc6909Token.totalSupply(reserve.variableDebtTokenID);
        return availableLiquidity;
    }

    function getCurrentDebt(address asset) public view override returns (uint256) {
        IAERC6909 aErc6909Token = IAERC6909(
            IMiniPoolAddressesProvider(_addressProvider).getMiniPoolToAERC6909(_getLendingPool())
        );
        DataTypes.MiniPoolReserveData memory reserve =
            IMiniPool(_getLendingPool()).getReserveData(asset, _assetReserveType);
        uint256 totalVariableDebt = aErc6909Token.totalSupply(reserve.variableDebtTokenID);
        return totalVariableDebt;
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

    struct CalcAugmentedInterestRatesLocalVars {
        uint256 interestRateDelta;
        uint256 currentVariableBorrowRate;
        uint256 currentLiquidityRate;
        uint256 utilizationRate;
        uint256 backstopUtilizationRate;
    }

    function calculateAugmentedInterestRate(augmentedInterestRateParams memory params)
        external
        returns (uint256, uint256)
    {
        CalcAugmentedInterestRatesLocalVars memory vars;
        vars.interestRateDelta =
            uint256(params.underlyingVarRate) - uint256(params.underlyingLiqRate);
        vars.utilizationRate = params.totalVariableDebt == 0
            ? 0
            : params.totalVariableDebt.rayDiv(params.availableLiquidity + params.totalVariableDebt);
        vars.backstopUtilizationRate = params.utilizedBackstopLiquidity == 0
            ? 0
            : params.utilizedBackstopLiquidity.rayDiv(params.totalAvailableBackstopLiquidity);

        if (vars.backstopUtilizationRate > 0) {
            // PID state update
            int256 err = getNormalizedError(vars.backstopUtilizationRate);
            _errI += int256(_ki).rayMulInt(err * int256(block.timestamp - _lastTimestamp));
            if (_errI < _maxErrIAmp) _errI = _maxErrIAmp; // Limit _errI negative accumulation.
            _lastTimestamp = block.timestamp;

            int256 controllerErr = getControllerError(err);
            vars.currentVariableBorrowRate = transferFunction(controllerErr);
            vars.currentLiquidityRate = getLiquidityRate(
                vars.currentVariableBorrowRate, vars.backstopUtilizationRate, params.reserveFactor
            );

            emit PidLog(
                vars.backstopUtilizationRate,
                vars.currentLiquidityRate,
                vars.currentVariableBorrowRate,
                err,
                controllerErr
            );
        } else {
            // backstopUtilizationRate is 0
            if (vars.utilizationRate == 0) {
                _errI = 0;
                _lastTimestamp = block.timestamp;
                return (0, 0);
            }
            // PID state update
            int256 err = getNormalizedError(vars.utilizationRate);
            _errI += int256(_ki).rayMulInt(err * int256(block.timestamp - _lastTimestamp));
            if (_errI < _maxErrIAmp) _errI = _maxErrIAmp; // Limit _errI negative accumulation.
            _lastTimestamp = block.timestamp;

            int256 controllerErr = getControllerError(err);
            vars.currentVariableBorrowRate = transferFunction(controllerErr);
            vars.currentLiquidityRate = getLiquidityRate(
                vars.currentVariableBorrowRate, vars.utilizationRate, params.reserveFactor
            );

            emit PidLog(
                vars.backstopUtilizationRate,
                vars.currentLiquidityRate,
                vars.currentVariableBorrowRate,
                err,
                controllerErr
            );
        }

        return (vars.currentLiquidityRate, vars.currentVariableBorrowRate);
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
        _calculateInterestRates(
            reserve, aToken, liquidityAdded, liquidityTaken, totalVariableDebt, reserveFactor
        );
    }
}
