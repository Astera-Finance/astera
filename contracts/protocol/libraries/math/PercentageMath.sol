// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title PercentageMath library
 * @author Conclave
 * @notice Provides functions to perform percentage calculations.
 * @dev Percentages are defined by default with 2 decimals of precision (100.00). The precision is indicated by `PERCENTAGE_FACTOR`.
 * @dev Operations are rounded half up.
 */
library PercentageMath {
    uint256 internal constant PERCENTAGE_FACTOR = 1e4; // Percentage plus two decimals.
    uint256 internal constant HALF_PERCENT = PERCENTAGE_FACTOR / 2;

    /**
     * @dev Executes a percentage multiplication.
     * @param value The value of which the percentage needs to be calculated.
     * @param percentage The percentage of the value to be calculated.
     * @return The percentage of `value`.
     */
    function percentMul(uint256 value, uint256 percentage) internal pure returns (uint256) {
        if (value == 0 || percentage == 0) {
            return 0;
        }

        require(
            value <= (type(uint256).max - HALF_PERCENT) / percentage,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        );

        return (value * percentage + HALF_PERCENT) / PERCENTAGE_FACTOR;
    }

    /**
     * @dev Executes a percentage division.
     * @param value The value of which the percentage needs to be calculated.
     * @param percentage The percentage of the value to be calculated.
     * @return The `value` divided by the `percentage`.
     */
    function percentDiv(uint256 value, uint256 percentage) internal pure returns (uint256) {
        require(percentage != 0, Errors.MATH_DIVISION_BY_ZERO);
        uint256 halfPercentage = percentage / 2;

        require(
            value <= (type(uint256).max - halfPercentage) / PERCENTAGE_FACTOR,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        );

        return (value * PERCENTAGE_FACTOR + halfPercentage) / percentage;
    }

    /**
     * @dev Executes a percentage division, rounding up.
     * @param value The value of which the percentage needs to be calculated.
     * @param percentage The percentage of the value to be calculated.
     * @return The `value` divided by the `percentage`, rounded up.
     */
    function percentDivUp(uint256 value, uint256 percentage) internal pure returns (uint256) {
        require(percentage != 0, Errors.MATH_DIVISION_BY_ZERO);

        require(
            value <= (type(uint256).max - percentage) / PERCENTAGE_FACTOR,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        );

        return (value * PERCENTAGE_FACTOR + percentage) / percentage;
    }
}
