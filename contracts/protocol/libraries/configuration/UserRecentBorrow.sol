// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {Errors} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title UserRecentBorrow library
 * @author Granary
 * @notice Implements the bitmap logic to handle data about a user's most recent borrow
 */
library UserRecentBorrow {
    uint256 constant AVERAGE_LTV_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000; // prettier-ignore
    uint256 constant AVERAGE_LIQUIDATION_THRESHOLD_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFF; // prettier-ignore
    uint256 constant TIMESTAMP_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000000FFFFFFFF; // prettier-ignore

    /// @dev For the Average LTV, the start bit is 0 (up to 15), hence no bitshifting is needed
    // uint256 constant AVERAGE_LTV_START_BIT_POSITION = 0; // 0 -> 15
    uint256 constant AVERAGE_LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16; // 16 -> 31
    uint256 constant TIMESTAMP_START_BIT_POSITION = 32; // 32 -> 79

    uint256 constant MAX_VALID_LTV = 65535;
    uint256 constant MAX_VALID_LIQUIDATION_THRESHOLD = 65535;
    uint256 constant MAX_VALID_TIMESTAMP = 281474976710655;

    function setAverageLtv(DataTypes.UserRecentBorrowMap memory self, uint256 averageLtv)
        internal
        pure
    {
        require(averageLtv <= MAX_VALID_LTV, Errors.RC_INVALID_LTV);

        self.data = (self.data & AVERAGE_LTV_MASK) | averageLtv;
    }

    function getAverageLtv(DataTypes.UserRecentBorrowMap storage self)
        internal
        view
        returns (uint256)
    {
        return self.data & ~AVERAGE_LTV_MASK;
    }

    function setAverageLiquidationThreshold(
        DataTypes.UserRecentBorrowMap memory self,
        uint256 averageLiquidationThreshold
    ) internal pure {
        require(
            averageLiquidationThreshold <= MAX_VALID_LIQUIDATION_THRESHOLD,
            Errors.RC_INVALID_LIQ_THRESHOLD
        );

        self.data = (self.data & AVERAGE_LIQUIDATION_THRESHOLD_MASK)
            | (averageLiquidationThreshold << AVERAGE_LIQUIDATION_THRESHOLD_START_BIT_POSITION);
    }

    function getAverageLiquidationThreshold(DataTypes.UserRecentBorrowMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~AVERAGE_LIQUIDATION_THRESHOLD_MASK)
            >> AVERAGE_LIQUIDATION_THRESHOLD_START_BIT_POSITION;
    }

    function setTimestamp(DataTypes.UserRecentBorrowMap memory self, uint256 averageTimestamp)
        internal
        pure
    {
        require(averageTimestamp <= MAX_VALID_TIMESTAMP, Errors.UB_INVALID_TIMESTAMP);

        self.data =
            (self.data & TIMESTAMP_MASK) | (averageTimestamp << TIMESTAMP_START_BIT_POSITION);
    }

    function getTimestamp(DataTypes.UserRecentBorrowMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~TIMESTAMP_MASK) >> TIMESTAMP_START_BIT_POSITION;
    }
}
