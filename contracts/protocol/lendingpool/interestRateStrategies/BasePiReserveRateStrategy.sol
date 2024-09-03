// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

// import {IReserveInterestRateStrategy} from "contracts/interfaces/IReserveInterestRateStrategy.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {Ownable} from "contracts/dependencies/openzeppelin/contracts/Ownable.sol";

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
abstract contract BasePiReserveRateStrategy is Ownable {
    using WadRayMath for uint256;
    using WadRayMath for int256;
    using PercentageMath for uint256;

    address public immutable _addressProvider;
    address public immutable _asset; // This strategy contract needs to be associated to a unique market.
    bool public immutable _assetReserveType; // This strategy contract needs to be associated to a unique market.

    int256 public constant M_FACTOR = 213e25;
    uint256 public constant N_FACTOR = 4;
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

    // Errors
    error PiReserveInterestRateStrategy__ACCESS_RESTRICTED_TO_LENDING_POOL();
    error PiReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
    error PiReserveInterestRateStrategy__U0_GREATER_THAN_RAY();

    // Events
    event PidLog(
        uint256 utilizationRate,
        uint256 currentLiquidityRate,
        uint256 currentVariableBorrowRate,
        int256 err,
        int256 controllerErr
    );

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
            revert PiReserveInterestRateStrategy__U0_GREATER_THAN_RAY();
        }
        _optimalUtilizationRate = optimalUtilizationRate;
        _asset = asset;
        _assetReserveType = assetReserveType;
        _addressProvider = provider;
        _kp = kp;
        _ki = ki;
        _lastTimestamp = block.timestamp;
        _minControllerError = minControllerError;
        _maxErrIAmp = int256(_ki).rayMulInt(-RAY * maxITimeAmp);

        if (transferFunction(type(int256).min) < 0) {
            revert PiReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
        }
    }

    modifier onlyLendingPool() {
        if (msg.sender != _getLendingPool()) {
            revert PiReserveInterestRateStrategy__ACCESS_RESTRICTED_TO_LENDING_POOL();
        }
        _;
    }

    /* Virtual functions */
    /**
     * @notice Returns lending pool address for main pool or mini pool.
     * @return lendingPoolAddress
     */
    function _getLendingPool() internal view virtual returns (address) {}
    /**
     * @notice Returns available liquidity in the pool for specific asset.
     * @param asset - address of asset
     * @param aToken - address of aToken
     * @return availableLiquidity
     */
    function getAvailableLiquidity(address asset, address aToken)
        public
        view
        virtual
        returns (uint256)
    {}
    /**
     * @notice The view version of `calculateInterestRates()`.
     * @return currentLiquidityRate
     * @return currentVariableBorrowRate
     * @return utilizationRate
     */
    function getCurrentInterestRates() public view virtual returns (uint256, uint256, uint256) {}

    // ----------- admin -----------

    function setOptimalUtilizationRate(uint256 optimalUtilizationRate) external onlyOwner {
        if (optimalUtilizationRate >= uint256(RAY)) {
            revert PiReserveInterestRateStrategy__U0_GREATER_THAN_RAY();
        }
        _optimalUtilizationRate = optimalUtilizationRate;
    }

    function setMinControllerError(int256 minControllerError) external onlyOwner {
        _minControllerError = minControllerError;
        if (transferFunction(type(int256).min) < 0) {
            revert PiReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
        }
    }

    function setPidValues(uint256 kp, uint256 ki, int256 maxITimeAmp) external onlyOwner {
        _kp = kp;
        _ki = ki;
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
    function _calculateInterestRates(
        address reserve,
        address aToken,
        uint256 liquidityAdded, //! since this function is not view anymore we need to make sure liquidityAdded is added at the end
        uint256 liquidityTaken, //! since this function is not view anymore we need to make sure liquidityTaken is removed at the end
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) internal returns (uint256, uint256) {
        uint256 availableLiquidity = getAvailableLiquidity(reserve, aToken);
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;
        return
            _calculateInterestRates(reserve, availableLiquidity, totalVariableDebt, reserveFactor);
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
    function _calculateInterestRates(
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
            _errI = 0;
            _lastTimestamp = block.timestamp;
            return (0, 0);
        }

        // PID state update
        int256 err = getNormalizedError(utilizationRate);
        _errI += int256(_ki).rayMulInt(err * int256(block.timestamp - _lastTimestamp));
        if (_errI < _maxErrIAmp) _errI = _maxErrIAmp; // Limit _errI negative accumulation.
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
        return errP + _errI;
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
