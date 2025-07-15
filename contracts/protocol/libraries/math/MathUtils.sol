// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {WadRayMath} from "./WadRayMath.sol";

/**
 * @title MathUtils library
 * @author Conclave
 * @notice Provides functions to perform linear and compounded interest rate calculations.
 * @dev Contains helper functions for interest calculations using both linear and compound formulas.
 */
library MathUtils {
    using WadRayMath for uint256;

    /// @dev Ignoring leap years in calculations.
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /**
     * @dev Function to calculate the interest accumulated using a linear interest rate formula.
     * @param rate The interest rate, in ray units.
     * @param lastUpdateTimestamp The timestamp of the last update of the interest.
     * @return The interest rate linearly accumulated during the time delta, in ray units.
     */
    function calculateLinearInterest(uint256 rate, uint40 lastUpdateTimestamp)
        internal
        view
        returns (uint256)
    {
        uint256 result = rate * (block.timestamp - uint256(lastUpdateTimestamp));
        unchecked {
            result = result / SECONDS_PER_YEAR;
        }

        return WadRayMath.RAY + result;
    }

    /**
     * @dev Function to calculate the interest using a compounded interest rate formula.
     * @dev To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
     *
     * (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)*x^3...
     *
     * @dev The approximation slightly underpays liquidity providers and undercharges borrowers, with the advantage of great
     * gas cost reductions. The whitepaper contains reference to the approximation and a table showing the margin of
     * error per different time periods.
     *
     * @param rate The interest rate, in ray units.
     * @param lastUpdateTimestamp The timestamp of the last update of the interest.
     * @param currentTimestamp The current timestamp reference.
     * @return The interest rate compounded during the time delta, in ray units.
     */
    function calculateCompoundedInterest(
        uint256 rate,
        uint40 lastUpdateTimestamp,
        uint256 currentTimestamp
    ) internal pure returns (uint256) {
        uint256 exp = currentTimestamp - uint256(lastUpdateTimestamp);

        if (exp == 0) {
            return WadRayMath.RAY;
        }

        uint256 expMinusOne;
        uint256 expMinusTwo;
        uint256 basePowerTwo;
        uint256 basePowerThree;
        unchecked {
            expMinusOne = exp - 1;

            expMinusTwo = exp > 2 ? exp - 2 : 0;

            basePowerTwo = rate.rayMul(rate) / (SECONDS_PER_YEAR * SECONDS_PER_YEAR);
            basePowerThree = basePowerTwo.rayMul(rate) / SECONDS_PER_YEAR;
        }

        uint256 secondTerm = exp * expMinusOne * basePowerTwo;
        unchecked {
            secondTerm /= 2;
        }
        uint256 thirdTerm = exp * expMinusOne * expMinusTwo * basePowerThree;
        unchecked {
            thirdTerm /= 6;
        }

        return WadRayMath.RAY + (rate * exp) / SECONDS_PER_YEAR + secondTerm + thirdTerm;
    }

    /**
     * @dev Calculates the compounded interest between the timestamp of the last update and the current block timestamp.
     * @param rate The interest rate, in ray units.
     * @param lastUpdateTimestamp The timestamp from which the interest accumulation needs to be calculated.
     * @return The interest rate compounded between `lastUpdateTimestamp` and current block timestamp, in ray units.
     */
    function calculateCompoundedInterest(uint256 rate, uint40 lastUpdateTimestamp)
        internal
        view
        returns (uint256)
    {
        return calculateCompoundedInterest(rate, lastUpdateTimestamp, block.timestamp);
    }
}
