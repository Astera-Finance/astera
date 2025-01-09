// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title WadRayMath library
 * @author Cod3x
 * @notice Provides multiplication and division functions for wads (decimal numbers with 18 digits precision) and rays (decimals with 27 digits precision).
 * @dev Core math library for precise decimal calculations using wad (1e18) and ray (1e27) units.
 */
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant halfWAD = WAD / 2;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant halfRAY = RAY / 2;

    int256 internal constant RAYint = 1e27;
    int256 internal constant halfRAYint = RAYint / 2;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    /// @return One ray, `1e27`.
    function ray() internal pure returns (uint256) {
        return RAY;
    }

    /// @return One wad, `1e18`.
    function wad() internal pure returns (uint256) {
        return WAD;
    }

    /// @return Half ray, `1e27/2`.
    function halfRay() internal pure returns (uint256) {
        return halfRAY;
    }

    /// @return Half wad, `1e18/2`.
    function halfWad() internal pure returns (uint256) {
        return halfWAD;
    }

    /**
     * @notice Multiplies two wad numbers, rounding half up to the nearest wad.
     * @param a First wad number to multiply.
     * @param b Second wad number to multiply.
     * @return The result of `a*b`, in wad precision.
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        require(a <= (type(uint256).max - halfWAD) / b, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * b + halfWAD) / WAD;
    }

    /**
     * @notice Divides two wad numbers, rounding half up to the nearest wad.
     * @param a Wad number to divide (numerator).
     * @param b Wad number to divide by (denominator).
     * @return The result of `a/b`, in wad precision.
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);
        uint256 halfB = b / 2;

        require(a <= (type(uint256).max - halfB) / WAD, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * WAD + halfB) / b;
    }

    /**
     * @notice Divides two wad numbers, rounding half down to the nearest wad.
     * @param a Wad number to divide (numerator).
     * @param b Wad number to divide by (denominator).
     * @return The result of `a/b`, in wad precision.
     */
    function wadDivDown(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);

        require(a <= (type(uint256).max) / WAD, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return ((a * WAD) / b);
    }

    /**
     * @notice Multiplies two ray numbers, rounding half up to the nearest ray.
     * @param a First ray number to multiply.
     * @param b Second ray number to multiply.
     * @return The result of `a*b`, in ray precision.
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        require(a <= (type(uint256).max - halfRAY) / b, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * b + halfRAY) / RAY;
    }

    /**
     * @notice Divides two ray numbers, rounding half up to the nearest ray.
     * @param a Ray number to divide (numerator).
     * @param b Ray number to divide by (denominator).
     * @return The result of `a/b`, in ray precision.
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);
        uint256 halfB = b / 2;

        require(a <= (type(uint256).max - halfB) / RAY, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * RAY + halfB) / b;
    }

    /**
     * @notice Converts ray number down to wad precision.
     * @param a Ray number to convert.
     * @return The input `a` converted to wad, rounded half up to the nearest wad.
     */
    function rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfRatio = WAD_RAY_RATIO / 2;
        uint256 result = halfRatio + a;

        return result / WAD_RAY_RATIO;
    }

    /**
     * @notice Converts wad number up to ray precision.
     * @param a Wad number to convert.
     * @return The input `a` converted to ray precision.
     */
    function wadToRay(uint256 a) internal pure returns (uint256) {
        uint256 result = a * WAD_RAY_RATIO;
        return result;
    }

    // ------- int -------

    /**
     * @notice Multiplies two ray integers, rounding half up to the nearest ray.
     * @dev If `result` > 0 rounds up, if `result` < 0 rounds down.
     * @param a First ray integer to multiply.
     * @param b Second ray integer to multiply.
     * @return result The result of `a*b`, in ray precision.
     */
    function rayMulInt(int256 a, int256 b) internal pure returns (int256) {
        int256 rawMul = a * b;
        if (rawMul < 0) {
            return (rawMul - halfRAYint) / RAYint;
        } else if (rawMul > 0) {
            return (rawMul + halfRAYint) / RAYint;
        } else {
            // if (a == 0 || b == 0)
            return 0;
        }
    }

    /**
     * @notice Divides two ray integers, rounding half up to the nearest ray.
     * @dev If `result` > 0 rounds up, if `result` < 0 rounds down.
     * @param a Ray integer to divide (numerator).
     * @param b Ray integer to divide by (denominator).
     * @return The result of `a/b`, in ray precision.
     */
    function rayDivInt(int256 a, int256 b) internal pure returns (int256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);

        int256 halfB = b / 2;

        if (a >= 0 && b > 0 || a <= 0 && b < 0) {
            return (a * RAYint + halfB) / b;
        } else {
            return (a * RAYint - halfB) / b;
        }
    }

    /**
     * @notice Calculates the power of a ray integer base to an unsigned integer exponent.
     * @dev Uses `rayMulInt` and a for loop for the calculation.
     * @param base Ray integer base number.
     * @param exponent Power exponent (not in ray precision).
     * @return result The result of `base**exponent`, in ray precision.
     */
    function rayPowerInt(int256 base, uint256 exponent) internal pure returns (int256) {
        if (exponent == 0) {
            return 1;
        }
        int256 result = base;
        for (uint256 i = 1; i < exponent; i++) {
            result = rayMulInt(result, base);
        }
        return result;
    }
}
