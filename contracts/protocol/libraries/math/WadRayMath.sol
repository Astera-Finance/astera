// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {Errors} from "../helpers/Errors.sol";

/**
 * @title WadRayMath library
 * @author Aave
 * @dev Provides mul and div function for wads (decimal numbers with 18 digits precision) and rays (decimals with 27 digits)
 *
 */
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant halfWAD = WAD / 2;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant halfRAY = RAY / 2;

    int256 internal constant RAYint = 1e27;
    int256 internal constant halfRAYint = RAYint / 2;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    /**
     * @return One ray, 1e27
     *
     */
    function ray() internal pure returns (uint256) {
        return RAY;
    }

    /**
     * @return One wad, 1e18
     *
     */
    function wad() internal pure returns (uint256) {
        return WAD;
    }

    /**
     * @return Half ray, 1e27/2
     *
     */
    function halfRay() internal pure returns (uint256) {
        return halfRAY;
    }

    /**
     * @return Half ray, 1e18/2
     *
     */
    function halfWad() internal pure returns (uint256) {
        return halfWAD;
    }

    /**
     * @dev Multiplies two wad, rounding half up to the nearest wad
     * @param a Wad
     * @param b Wad
     * @return The result of a*b, in wad
     *
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        require(a <= (type(uint256).max - halfWAD) / b, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * b + halfWAD) / WAD;
    }

    /**
     * @dev Divides two wad, rounding half up to the nearest wad
     * @param a Wad
     * @param b Wad
     * @return The result of a/b, in wad
     *
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);
        uint256 halfB = b / 2;

        require(a <= (type(uint256).max - halfB) / WAD, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * WAD + halfB) / b;
    }

    /**
     * @dev Divides two wad, rounding half down to the nearest wad
     * @param a Wad
     * @param b Wad
     * @return The result of a/b, in wad
     *
     */
    function wadDivDown(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);

        require(a <= (type(uint256).max) / WAD, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return ((a * WAD) / b);
    }

    /**
     * @dev Multiplies two ray, rounding half up to the nearest ray
     * @param a Ray
     * @param b Ray
     * @return The result of a*b, in ray
     *
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        require(a <= (type(uint256).max - halfRAY) / b, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * b + halfRAY) / RAY;
    }

    /**
     * @dev Divides two ray, rounding half up to the nearest ray
     * @param a Ray
     * @param b Ray
     * @return The result of a/b, in ray
     *
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);
        uint256 halfB = b / 2;

        require(a <= (type(uint256).max - halfB) / RAY, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * RAY + halfB) / b;
    }

    /**
     * @dev Casts ray down to wad
     * @param a Ray
     * @return a casted to wad, rounded half up to the nearest wad
     *
     */
    function rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfRatio = WAD_RAY_RATIO / 2;
        uint256 result = halfRatio + a;
        require(result >= halfRatio, Errors.MATH_ADDITION_OVERFLOW);

        return result / WAD_RAY_RATIO;
    }

    /**
     * @dev Converts wad up to ray
     * @param a Wad
     * @return a converted in ray
     *
     */
    function wadToRay(uint256 a) internal pure returns (uint256) {
        uint256 result = a * WAD_RAY_RATIO;
        require(result / WAD_RAY_RATIO == a, Errors.MATH_MULTIPLICATION_OVERFLOW);
        return result;
    }

    // ------- int -------

    /**
     * @dev Multiplies two ray int, rounding half up to the nearest ray.
     * If `result` > 0 round up, if `result` < 0 round down.
     * @param a Ray int
     * @param b Ray int
     * @return result The result of a*b, in ray
     *
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
     * @dev Divides two ray, rounding half up to the nearest ray
     * If `result` > 0 round up, if `result` < 0 round down.
     * @param a Ray int
     * @param b Ray int
     * @return The result of a/b, in ray
     *
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
     * @dev `base` to the power of `exponent`, using rayMulInt and a for loop.
     * @param base Ray int
     * @param exponent power exponent, not ray
     * @return result The result of base**exponent, in ray
     *
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
