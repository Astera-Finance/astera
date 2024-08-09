// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IReserveInterestRateStrategy} from "contracts/interfaces/IReserveInterestRateStrategy.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "contracts/interfaces/IVariableDebtToken.sol";
import {VariableDebtToken} from "contracts/protocol/tokenization/VariableDebtToken.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {Ownable} from "contracts/dependencies/openzeppelin/contracts/Ownable.sol";

/**
 * @title PidReserveInterestRateStrategy contract
 * @notice Implements the calculation of the interest rates using control theory.
 * @dev The model of interest rate is based Proportional Integrator (PI).
 * Admin needs to set an optimal utilization rate and this strategy will automatically
 * automatically adjust the interest rate according to the `Kp` and `Ki` variables.
 * @dev ATTENTION, this contract must no be used as a library. One PidReserveInterestRateStrategy
 * needs to be associated with only one market.
 * @author ByteMasons
 */
contract PidReserveInterestRateStrategy is IReserveInterestRateStrategy, Ownable {
    using WadRayMath for uint256;
    using WadRayMath for int256;
    using PercentageMath for uint256;

    ILendingPoolAddressesProvider public immutable _addressesProvider;
    address public immutable _asset; // This strategy contract needs to be associated to a unique market.
    bool public immutable _assetReserveType; // This strategy contract needs to be associated to a unique market.

    int256 public constant M_FACTOR = 192e25;
    uint256 public constant N_FACTOR = 4;
    uint256 public constant PERIOD = 12 hours;
    int256 public constant RAY = 1e27;

    int256 public _minControllerError;
    int256 public _maxErrIAmp;
    uint256 public _optimalUtilizationRate;

    // P
    uint256 public _kp; // in RAY

    // I
    uint256 public _ki; // in RAY
    uint256 public _lastTimestamp;
    int256 public _errI;

    // D
    uint256 public _kd; // in RAY
    int256 public _cumulativeErr;
    int256 public _cumulativeErrDelayed;
    int256 public _cumulativeErrPrevious;
    uint256 public _twaeTimestampDelayed;
    uint256 public _twaeTimestampPrevious;

    // Errors
    error PidReserveInterestRateStrategy__ACCESS_RESTRICTED_TO_LENDING_POOL();
    error PidReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
    error PidReserveInterestRateStrategy__U0_GREATER_THAN_RAY();

    // Events
    event PidLog(
        uint256 utilizationRate,
        uint256 currentLiquidityRate,
        uint256 currentVariableBorrowRate,
        int256 err,
        int256 controllerErr
    );

    constructor(
        ILendingPoolAddressesProvider provider,
        address asset,
        bool assetReserveType,
        int256 minControllerError,
        int256 maxITimeAmp,
        uint256 optimalUtilizationRate,
        uint256 kp,
        uint256 ki,
        uint256 kd
    ) Ownable(msg.sender) {
        if (optimalUtilizationRate >= uint256(RAY)) {
            revert PidReserveInterestRateStrategy__U0_GREATER_THAN_RAY();
        }
        _optimalUtilizationRate = optimalUtilizationRate;
        _asset = asset;
        _assetReserveType = assetReserveType;
        _addressesProvider = provider;
        _kp = kp;
        _ki = ki;
        _kd = kd;
        _lastTimestamp = block.timestamp;
        _minControllerError = minControllerError;
        _maxErrIAmp = int256(_ki).rayMulInt(-RAY * maxITimeAmp);

        if (transferFunction(type(int256).min) < 0) {
            revert PidReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
        }
    }

    modifier onlyLendingPool() {
        if (msg.sender != _addressesProvider.getLendingPool()) {
            revert PidReserveInterestRateStrategy__ACCESS_RESTRICTED_TO_LENDING_POOL();
        }
        _;
    }

    // ----------- admin -----------

    function setOptimalUtilizationRate(uint256 optimalUtilizationRate) external onlyOwner {
        if (optimalUtilizationRate >= uint256(RAY)) {
            revert PidReserveInterestRateStrategy__U0_GREATER_THAN_RAY();
        }
        _optimalUtilizationRate = optimalUtilizationRate;
    }

    function setMinControllerError(int256 minControllerError) external onlyOwner {
        _minControllerError = minControllerError;
        if (transferFunction(type(int256).min) < 0) {
            revert PidReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
        }
    }

    function setPidValues(uint256 kp, uint256 ki, uint256 kd, int256 maxITimeAmp)
        external
        onlyOwner
    {
        _kp = kp;
        _ki = ki;
        _kd = kd;
        _maxErrIAmp = int256(_ki).rayMulInt(-RAY * maxITimeAmp);
    }

    // ----------- external -----------

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
        uint256 liquidityAdded, //! since this function is not view anymore we need to make sure liquidityAdded is added at the end
        uint256 liquidityTaken, //! since this function is not view anymore we need to make sure liquidityTaken is removed at the end
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external override onlyLendingPool returns (uint256, uint256) {
        uint256 availableLiquidity = IAToken(aToken).getTotalManagedAssets();
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;
        return calculateInterestRates(reserve, availableLiquidity, totalVariableDebt, reserveFactor);
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
    ) internal returns (uint256, uint256) {
        uint256 utilizationRate = totalVariableDebt == 0
            ? 0
            : totalVariableDebt.rayDiv(availableLiquidity + totalVariableDebt);

        // If no borrowers we reset the strategy
        if (utilizationRate == 0) {
            _cumulativeErr = 0;
            _cumulativeErrPrevious = 0;
            _cumulativeErrDelayed = 0;
            _errI = 0;
            _lastTimestamp = block.timestamp;
            _twaeTimestampDelayed = block.timestamp;
            _twaeTimestampPrevious = block.timestamp;
            return (0, 0);
        }

        // PID state update
        if (block.timestamp - _twaeTimestampDelayed > PERIOD) {
            _cumulativeErrPrevious = _cumulativeErrDelayed;
            _twaeTimestampPrevious = _twaeTimestampDelayed;
            _cumulativeErrDelayed = _cumulativeErr;
            _twaeTimestampDelayed = block.timestamp;
        }
        int256 err = getNormalizedError(utilizationRate);
        _errI += int256(_ki).rayMulInt(err * int256(block.timestamp - _lastTimestamp));
        if (_errI < _maxErrIAmp) _errI = _maxErrIAmp; // Limit _errI negative accumulation.
        _cumulativeErr += err * int256(block.timestamp - _lastTimestamp);
        _lastTimestamp = block.timestamp;

        int256 controllerErr = getControllerError(err);
        uint256 currentVariableBorrowRate = transferFunction(controllerErr);
        uint256 currentLiquidityRate =
            getLiquidityRate(currentVariableBorrowRate, utilizationRate, reserveFactor);

        emit PidLog(
            utilizationRate, currentLiquidityRate, currentVariableBorrowRate, err, controllerErr
        );

        return (currentLiquidityRate, currentVariableBorrowRate);
    }

    // ----------- view -----------

    /**
     * @notice The view version of `calculateInterestRates()`.
     * @return currentLiquidityRate
     * @return currentVariableBorrowRate
     * @return utilizationRate
     */
    function getCurrentInterestRates() public view returns (uint256, uint256, uint256) {
        // utilization
        DataTypes.ReserveData memory reserve = ILendingPool(_addressesProvider.getLendingPool())
            .getReserveData(_asset, _assetReserveType);
        uint256 availableLiquidity = IAToken(reserve.aTokenAddress).getTotalManagedAssets();
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

    function baseVariableBorrowRate() public view override returns (uint256) {
        return uint256(transferFunction(type(int256).min));
    }

    function getMaxVariableBorrowRate() external pure override returns (uint256) {
        return type(uint256).max;
    }

    // ----------- helpers -----------

    /**
     * @dev normalize the err:
     * utilizationRate ⊂ [0, Uo]   => err ⊂ [-RAY, 0]
     * utilizationRate ⊂ [Uo, RAY] => err ⊂ [0, RAY]
     * With Uo = optimal rate
     */
    function getNormalizedError(uint256 utilizationRate) internal view returns (int256) {
        int256 err = int256(utilizationRate) - int256(_optimalUtilizationRate);
        if (int256(utilizationRate) < int256(_optimalUtilizationRate)) {
            return err.rayDivInt(int256(_optimalUtilizationRate));
        } else {
            return err.rayDivInt(RAY - int256(_optimalUtilizationRate));
        }
    }

    /// @dev Process the liquidity rate from the variable borrow rate.
    function getLiquidityRate(
        uint256 currentVariableBorrowRate,
        uint256 utilizationRate,
        uint256 reserveFactor
    ) internal pure returns (uint256) {
        return currentVariableBorrowRate.rayMul(utilizationRate).percentMul(
            PercentageMath.PERCENTAGE_FACTOR - reserveFactor
        );
    }

    /// @dev Process the controller error from the normalized error.
    function getControllerError(int256 err) internal view returns (int256) {
        int256 errP = int256(_kp).rayMulInt(err);
        int256 deltaT = int256(_twaeTimestampDelayed - _twaeTimestampPrevious);
        int256 errD;
        if (deltaT != 0) {
            errD = int256(_kd).rayMulInt(_cumulativeErrDelayed - _cumulativeErrPrevious) / deltaT;
        }
        return errP + _errI + errD;
    }

    /// @dev Transfer Function for calculation of _currentVariableBorrowRate (https://www.desmos.com/calculator/dj5puy23wz)
    function transferFunction(int256 controllerError) public view returns (uint256) {
        int256 ce = controllerError > _minControllerError ? controllerError : _minControllerError;
        return uint256(M_FACTOR.rayMulInt((ce + RAY).rayDivInt(2 * RAY).rayPowerInt(N_FACTOR)));
    }

    /**
     * @notice getReserveFactor() from ReserveConfiguration can't be used with memory.
     * So we need to redefine this function here using memory.
     * @dev Gets the reserve factor of the reserve
     * @param self The reserve configuration
     * @return The reserve factor
     */
    function getReserveFactor(DataTypes.ReserveConfigurationMap memory self)
        internal
        pure
        returns (uint256)
    {
        return (self.data & ~ReserveConfiguration.RESERVE_FACTOR_MASK)
            >> ReserveConfiguration.RESERVE_FACTOR_START_BIT_POSITION;
    }
}
