// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {WadRayMath} from "../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {Ownable} from "../../../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title PiReserveInterestRateStrategy contract.
 * @notice Implements the calculation of the interest rates using control theory.
 * @dev The model of interest rate is based on Proportional Integrator (PI).
 * Admin needs to set an optimal utilization rate and this strategy will automatically
 * adjust the interest rate according to the `_kp` and `_ki` variables.
 * @dev ATTENTION: This contract must not be used as a library. One PiReserveInterestRateStrategy
 * needs to be associated with only one market.
 * @author Cod3x
 */
abstract contract BasePiReserveRateStrategy is Ownable {
    using WadRayMath for uint256;
    using WadRayMath for int256;
    using PercentageMath for uint256;

    /// @dev Multiplier factor used in interest rate calculations.
    int256 public constant M_FACTOR = 213e25;
    /// @dev Power factor used in interest rate calculations.
    uint256 public constant N_FACTOR = 4;
    /// @dev Ray precision constant (1e27).
    int256 public constant RAY = 1e27;

    /// @dev Address of the lending pool address provider.
    address public immutable _addressProvider;
    /// @dev Address of the asset this strategy is associated with.
    address public immutable _asset;
    /// @dev Type of the asset reserve (true/false).
    bool public immutable _assetReserveType;

    /// @dev Minimum error value allowed for the controller.
    int256 public _minControllerError;
    /// @dev Maximum amplitude for the integral error term.
    int256 public _maxErrIAmp;
    /// @dev Target utilization rate for the reserve.
    uint256 public _optimalUtilizationRate;

    /// @dev Proportional gain coefficient in RAY units.
    uint256 public _kp;

    /// @dev Integral gain coefficient in RAY units.
    uint256 public _ki;
    /// @dev Timestamp of the last interest rate update.
    uint256 public _lastTimestamp;
    /// @dev Accumulated integral error term.
    int256 public _errI;

    /**
     * @notice Emitted when interest rates are calculated using the PI controller.
     * @param utilizationRate The current utilization rate of the reserve.
     * @param currentLiquidityRate The calculated liquidity rate.
     * @param currentVariableBorrowRate The calculated variable borrow rate.
     * @param err The error between current and optimal utilization rate.
     * @param controllerErr The error used by the PI controller.
     */
    event PidLog(
        uint256 utilizationRate,
        uint256 currentLiquidityRate,
        uint256 currentVariableBorrowRate,
        int256 err,
        int256 controllerErr
    );

    /**
     * @notice Initializes the interest rate strategy contract.
     * @param provider Address of the lending pool provider.
     * @param asset Address of the asset this strategy is for.
     * @param assetReserveType Type of the asset reserve.
     * @param minControllerError Minimum allowed controller error.
     * @param maxITimeAmp Maximum integral time amplitude.
     * @param optimalUtilizationRate Target utilization rate.
     * @param kp Proportional gain coefficient.
     * @param ki Integral gain coefficient.
     */
    constructor(
        address provider,
        address asset,
        bool assetReserveType,
        int256 minControllerError,
        int256 maxITimeAmp,
        uint256 optimalUtilizationRate,
        uint256 kp,
        uint256 ki
    ) Ownable(msg.sender) {
        if (optimalUtilizationRate >= uint256(RAY)) {
            revert(Errors.IR_U0_GREATER_THAN_RAY);
        }

        _setOptimalUtilizationRate(optimalUtilizationRate);
        _asset = asset;
        _assetReserveType = assetReserveType;
        _addressProvider = provider;
        _kp = kp;
        _ki = ki;
        _lastTimestamp = block.timestamp;
        _minControllerError = minControllerError;
        _maxErrIAmp = int256(_ki).rayMulInt(-RAY * maxITimeAmp);

        if (transferFunctionReturnInt(type(int256).min) < 0) {
            revert(Errors.IR_BASE_BORROW_RATE_CANT_BE_NEGATIVE);
        }
    }

    /// @dev Restricts function access to lending pool only.
    modifier onlyLendingPool() {
        if (msg.sender != _getLendingPool()) {
            revert(Errors.IR_ACCESS_RESTRICTED_TO_LENDING_POOL);
        }
        _;
    }

    /**
     * @notice Returns lending pool address.
     * @return lendingPoolAddress The address of the lending pool.
     */
    function _getLendingPool() internal view virtual returns (address) {}

    /**
     * @notice Returns available liquidity in the pool for specific asset.
     * @param asset Address of asset.
     * @param aToken Address of aToken.
     * @return availableLiquidity The available liquidity.
     * @return underlying The underlying asset address if tranched.
     * @return currentFlow The current flow if tranched.
     */
    function getAvailableLiquidity(address asset, address aToken)
        public
        view
        virtual
        returns (uint256, address, uint256)
    {}

    /**
     * @notice The view version of `calculateInterestRates()`.
     * @dev Returns the current interest rates without modifying state.
     * @return currentLiquidityRate The current liquidity rate.
     * @return currentVariableBorrowRate The current variable borrow rate.
     * @return utilizationRate The current utilization rate.
     */
    function getCurrentInterestRates() public view virtual returns (uint256, uint256, uint256) {}

    /**
     * @notice Sets the optimal utilization rate for the reserve.
     * @param optimalUtilizationRate The new optimal utilization rate.
     */
    function setOptimalUtilizationRate(uint256 optimalUtilizationRate) external onlyOwner {
        _setOptimalUtilizationRate(optimalUtilizationRate);
    }

    /**
     * @notice Internal function to set the optimal utilization rate.
     * @param optimalUtilizationRate The new optimal utilization rate.
     */
    function _setOptimalUtilizationRate(uint256 optimalUtilizationRate) internal {
        if (optimalUtilizationRate >= uint256(RAY)) {
            revert(Errors.IR_U0_GREATER_THAN_RAY);
        }
        _optimalUtilizationRate = optimalUtilizationRate;
    }

    /**
     * @notice Sets the minimum controller error value.
     * @param minControllerError The new minimum controller error.
     */
    function setMinControllerError(int256 minControllerError) external onlyOwner {
        _minControllerError = minControllerError;
        if (transferFunctionReturnInt(type(int256).min) < 0) {
            revert(Errors.IR_BASE_BORROW_RATE_CANT_BE_NEGATIVE);
        }
    }

    /**
     * @notice Sets the PID controller parameters.
     * @param kp The proportional gain coefficient.
     * @param ki The integral gain coefficient.
     * @param maxITimeAmp The maximum integral time amplitude.
     */
    function setPidValues(uint256 kp, uint256 ki, int256 maxITimeAmp) external onlyOwner {
        _kp = kp;
        _ki = ki;
        _maxErrIAmp = int256(_ki).rayMulInt(-RAY * maxITimeAmp);
    }

    /**
     * @notice Calculates the interest rates based on the reserve's state and configurations.
     * @param asset The address of the asset.
     * @param aToken The address of the aToken.
     * @param liquidityAdded The liquidity added during the operation.
     * @param liquidityTaken The liquidity taken during the operation.
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate.
     * @param reserveFactor The reserve portion of the interest that goes to the treasury.
     * @return currentLiquidityRate The calculated liquidity rate.
     * @return currentVariableBorrowRate The calculated variable borrow rate.
     * @return utilization The calculated utilization rate.
     * @return underlying The underlying asset address if tranched.
     * @return currentFlow The current flow if tranched.
     */
    function _calculateInterestRates(
        address asset,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    )
        internal
        returns (
            uint256 currentLiquidityRate,
            uint256 currentVariableBorrowRate,
            uint256 utilization,
            address underlying,
            uint256 currentFlow
        )
    {
        uint256 availableLiquidity;
        (availableLiquidity, underlying, currentFlow) = getAvailableLiquidity(asset, aToken);
        if (availableLiquidity + liquidityAdded < liquidityTaken) {
            revert(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW);
        }
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;
        (currentLiquidityRate, currentVariableBorrowRate, utilization) =
            _calculateInterestRates(asset, availableLiquidity, totalVariableDebt, reserveFactor);
    }

    /**
     * @notice Calculates the interest rates based on the reserve's state.
     * @dev This function is kept for compatibility with the previous DefaultInterestRateStrategy interface.
     * @param availableLiquidity The liquidity available in the corresponding aToken.
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate.
     * @param reserveFactor The reserve portion of the interest that goes to the treasury.
     * @return The liquidity rate, variable borrow rate, and utilization rate.
     */
    function _calculateInterestRates(
        address,
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) internal returns (uint256, uint256, uint256) {
        uint256 utilizationRate = totalVariableDebt == 0
            ? 0
            : totalVariableDebt.rayDiv(availableLiquidity + totalVariableDebt);

        // If no borrowers we reset the strategy
        if (utilizationRate == 0) {
            _errI = 0;
            _lastTimestamp = block.timestamp;
            return (0, 0, 0);
        }

        // PID state update
        int256 err = _getNormalizedError(utilizationRate);
        _errI += int256(_ki).rayMulInt(err * int256(block.timestamp - _lastTimestamp));
        if (_errI < _maxErrIAmp) _errI = _maxErrIAmp; // Limit _errI negative accumulation.
        _lastTimestamp = block.timestamp;
        int256 controllerErr = _getControllerError(err);
        uint256 currentVariableBorrowRate = transferFunction(controllerErr);
        uint256 currentLiquidityRate =
            _getLiquidityRate(currentVariableBorrowRate, utilizationRate, reserveFactor);

        emit PidLog(
            utilizationRate, currentLiquidityRate, currentVariableBorrowRate, err, controllerErr
        );
        return (currentLiquidityRate, currentVariableBorrowRate, utilizationRate);
    }

    /**
     * @notice Normalizes the error value based on utilization rate.
     * @dev For utilizationRate ⊂ [0, Uo] => err ⊂ [-RAY, 0].
     * For utilizationRate ⊂ [Uo, RAY] => err ⊂ [0, RAY].
     * Where Uo is the optimal rate.
     * @param utilizationRate The current utilization rate.
     * @return The normalized error value.
     */
    function _getNormalizedError(uint256 utilizationRate) internal view returns (int256) {
        int256 err = int256(utilizationRate) - int256(_optimalUtilizationRate);
        if (int256(utilizationRate) < int256(_optimalUtilizationRate)) {
            return err.rayDivInt(int256(_optimalUtilizationRate));
        } else {
            return err.rayDivInt(RAY - int256(_optimalUtilizationRate));
        }
    }

    /**
     * @notice Calculates the liquidity rate from the variable borrow rate.
     * @param currentVariableBorrowRate The current variable borrow rate.
     * @param utilizationRate The current utilization rate.
     * @param reserveFactor The reserve factor.
     * @return The calculated liquidity rate.
     */
    function _getLiquidityRate(
        uint256 currentVariableBorrowRate,
        uint256 utilizationRate,
        uint256 reserveFactor
    ) internal pure returns (uint256) {
        return currentVariableBorrowRate.rayMul(utilizationRate).percentMul(
            PercentageMath.PERCENTAGE_FACTOR - reserveFactor
        );
    }

    /**
     * @notice Processes the controller error from the normalized error.
     * @param err The normalized error value.
     * @return The processed controller error.
     */
    function _getControllerError(int256 err) internal view returns (int256) {
        int256 errP = int256(_kp).rayMulInt(err);
        return errP + _errI;
    }

    /**
     * @notice Transfer Function for calculation of currentVariableBorrowRate.
     * @dev See https://www.desmos.com/calculator/d9baparlv3 for the mathematical model.
     * @param controllerError The controller error input.
     * @return The calculated variable borrow rate.
     */
    function transferFunction(int256 controllerError) public view returns (uint256) {
        return uint256(transferFunctionReturnInt(controllerError));
    }

    /**
     * @notice "Returni Int" version of Transfer `transferFunction()`.
     */
    function transferFunctionReturnInt(int256 controllerError) internal view returns (int256) {
        int256 ce = controllerError > _minControllerError ? controllerError : _minControllerError;
        return int256(M_FACTOR.rayMulInt((ce + RAY).rayDivInt(2 * RAY).rayPowerInt(N_FACTOR)));
    }

    /**
     * @notice Gets the Cod3x reserve factor from reserve configuration.
     * @dev This is a redefined version of ReserveConfiguration.getCod3xReserveFactor() for memory usage.
     * @param self The reserve configuration.
     * @return The Cod3x reserve factor.
     */
    function _getCod3xReserveFactor(DataTypes.ReserveConfigurationMap memory self)
        internal
        pure
        returns (uint256)
    {
        return (self.data & ~ReserveConfiguration.COD3X_RESERVE_FACTOR_MASK)
            >> ReserveConfiguration.COD3X_RESERVE_FACTOR_START_BIT_POSITION;
    }

    /**
     * @notice Gets the minipool owner reserve factor from reserve configuration.
     * @param self The reserve configuration.
     * @return The minipool owner reserve factor.
     */
    function _getMinipoolOwnerReserveFactor(DataTypes.ReserveConfigurationMap memory self)
        internal
        pure
        returns (uint256)
    {
        return (self.data & ~ReserveConfiguration.MINIPOOL_OWNER_RESERVE_FACTOR_MASK)
            >> ReserveConfiguration.MINIPOOL_OWNER_FACTOR_START_BIT_POSITION;
    }
}
