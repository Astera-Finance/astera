// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title ReserveConfiguration library
 * @author Cod3x
 * @notice Implements the bitmap logic to handle the reserve configuration
 */
library ReserveConfiguration {
    uint256 internal constant LTV_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000;
    uint256 internal constant LIQUIDATION_THRESHOLD_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFF;
    uint256 internal constant LIQUIDATION_BONUS_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFF;
    uint256 internal constant DECIMALS_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF;
    uint256 internal constant ACTIVE_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF;
    uint256 internal constant FROZEN_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF;
    uint256 internal constant BORROWING_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBFFFFFFFFFFFFFF;
    uint256 internal constant FLASHLOAN_ENABLED_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF7FFFFFFFFFFFFFF;
    uint256 internal constant RESERVE_FACTOR_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFF;
    uint256 internal constant DEPOSIT_CAP_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFFFFFFFFF;

    /// @dev For the LTV, the start bit is 0 (up to 15), hence no bitshifting is needed
    uint256 internal constant LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16;
    uint256 internal constant LIQUIDATION_BONUS_START_BIT_POSITION = 32;
    uint256 internal constant RESERVE_DECIMALS_START_BIT_POSITION = 48;
    uint256 internal constant IS_ACTIVE_START_BIT_POSITION = 56;
    uint256 internal constant IS_FROZEN_START_BIT_POSITION = 57;
    uint256 internal constant BORROWING_ENABLED_START_BIT_POSITION = 58;
    uint256 internal constant RESERVE_FACTOR_START_BIT_POSITION = 64;
    uint256 internal constant DEPOSIT_CAP_START_BIT_POSITION = 80;
    uint256 internal constant FLASHLOAN_ENABLED_START_BIT_POSITION = 63;

    uint256 internal constant MAX_VALID_LTV = 65535;
    uint256 internal constant MAX_VALID_LIQUIDATION_THRESHOLD = 65535;
    uint256 internal constant MAX_VALID_LIQUIDATION_BONUS = 65535;
    uint256 internal constant MAX_VALID_DECIMALS = 255;
    uint256 internal constant MAX_VALID_RESERVE_FACTOR = 65535;
    uint256 internal constant MAX_VALID_DEPOSIT_CAP = 255;

    /**
     * @dev Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param ltv the new ltv
     *
     */
    function setLtv(DataTypes.ReserveConfigurationMap memory self, uint256 ltv) internal pure {
        require(ltv <= MAX_VALID_LTV, Errors.RC_INVALID_LTV);

        self.data = (self.data & LTV_MASK) | ltv;
    }

    /**
     * @dev Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     *
     */
    function getLtv(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return self.data & ~LTV_MASK;
    }

    /**
     * @dev Sets the liquidation threshold of the reserve
     * @param self The reserve configuration
     * @param threshold The new liquidation threshold
     *
     */
    function setLiquidationThreshold(
        DataTypes.ReserveConfigurationMap memory self,
        uint256 threshold
    ) internal pure {
        require(threshold <= MAX_VALID_LIQUIDATION_THRESHOLD, Errors.RC_INVALID_LIQ_THRESHOLD);

        self.data = (self.data & LIQUIDATION_THRESHOLD_MASK)
            | (threshold << LIQUIDATION_THRESHOLD_START_BIT_POSITION);
    }

    /**
     * @dev Gets the liquidation threshold of the reserve
     * @param self The reserve configuration
     * @return The liquidation threshold
     *
     */
    function getLiquidationThreshold(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION;
    }

    /**
     * @dev Sets the liquidation bonus of the reserve
     * @param self The reserve configuration
     * @param bonus The new liquidation bonus
     *
     */
    function setLiquidationBonus(DataTypes.ReserveConfigurationMap memory self, uint256 bonus)
        internal
        pure
    {
        require(bonus <= MAX_VALID_LIQUIDATION_BONUS, Errors.RC_INVALID_LIQ_BONUS);

        self.data =
            (self.data & LIQUIDATION_BONUS_MASK) | (bonus << LIQUIDATION_BONUS_START_BIT_POSITION);
    }

    /**
     * @dev Gets the liquidation bonus of the reserve
     * @param self The reserve configuration
     * @return The liquidation bonus
     *
     */
    function getLiquidationBonus(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~LIQUIDATION_BONUS_MASK) >> LIQUIDATION_BONUS_START_BIT_POSITION;
    }

    /**
     * @dev Sets the decimals of the underlying asset of the reserve
     * @param self The reserve configuration
     * @param decimals The decimals
     *
     */
    function setDecimals(DataTypes.ReserveConfigurationMap memory self, uint256 decimals)
        internal
        pure
    {
        require(decimals <= MAX_VALID_DECIMALS, Errors.RC_INVALID_DECIMALS);

        self.data = (self.data & DECIMALS_MASK) | (decimals << RESERVE_DECIMALS_START_BIT_POSITION);
    }

    /**
     * @dev Gets the decimals of the underlying asset of the reserve
     * @param self The reserve configuration
     * @return The decimals of the asset
     *
     */
    function getDecimals(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~DECIMALS_MASK) >> RESERVE_DECIMALS_START_BIT_POSITION;
    }

    /**
     * @dev Sets the active state of the reserve
     * @param self The reserve configuration
     * @param active The active state
     *
     */
    function setActive(DataTypes.ReserveConfigurationMap memory self, bool active) internal pure {
        self.data =
            (self.data & ACTIVE_MASK) | (uint256(active ? 1 : 0) << IS_ACTIVE_START_BIT_POSITION);
    }

    /**
     * @dev Gets the active state of the reserve
     * @param self The reserve configuration
     * @return The active state
     *
     */
    function getActive(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (bool)
    {
        return (self.data & ~ACTIVE_MASK) != 0;
    }

    /**
     * @dev Sets the frozen state of the reserve
     * @param self The reserve configuration
     * @param frozen The frozen state
     *
     */
    function setFrozen(DataTypes.ReserveConfigurationMap memory self, bool frozen) internal pure {
        self.data =
            (self.data & FROZEN_MASK) | (uint256(frozen ? 1 : 0) << IS_FROZEN_START_BIT_POSITION);
    }

    /**
     * @dev Gets the frozen state of the reserve
     * @param self The reserve configuration
     * @return The frozen state
     *
     */
    function getFrozen(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (bool)
    {
        return (self.data & ~FROZEN_MASK) != 0;
    }

    /**
     * @dev Enables or disables borrowing on the reserve
     * @param self The reserve configuration
     * @param enabled True if the borrowing needs to be enabled, false otherwise
     *
     */
    function setBorrowingEnabled(DataTypes.ReserveConfigurationMap memory self, bool enabled)
        internal
        pure
    {
        self.data = (self.data & BORROWING_MASK)
            | (uint256(enabled ? 1 : 0) << BORROWING_ENABLED_START_BIT_POSITION);
    }

    /**
     * @dev Gets the borrowing state of the reserve
     * @param self The reserve configuration
     * @return The borrowing state
     *
     */
    function getBorrowingEnabled(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (bool)
    {
        return (self.data & ~BORROWING_MASK) != 0;
    }

    /**
     * @dev Sets the reserve factor of the reserve
     * @param self The reserve configuration
     * @param reserveFactor The reserve factor
     *
     */
    function setReserveFactor(DataTypes.ReserveConfigurationMap memory self, uint256 reserveFactor)
        internal
        pure
    {
        require(reserveFactor <= MAX_VALID_RESERVE_FACTOR, Errors.RC_INVALID_RESERVE_FACTOR);

        self.data =
            (self.data & RESERVE_FACTOR_MASK) | (reserveFactor << RESERVE_FACTOR_START_BIT_POSITION);
    }

    /**
     * @dev Gets the reserve factor of the reserve
     * @param self The reserve configuration
     * @return The reserve factor
     *
     */
    function getReserveFactor(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_START_BIT_POSITION;
    }

    function setDepositCap(DataTypes.ReserveConfigurationMap memory self, uint256 depositCap)
        internal
        pure
    {
        require(depositCap <= MAX_VALID_DEPOSIT_CAP, Errors.RC_INVALID_DEPOSIT_CAP);

        self.data = (self.data & DEPOSIT_CAP_MASK) | (depositCap << DEPOSIT_CAP_START_BIT_POSITION);
    }

    function getDepositCap(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~DEPOSIT_CAP_MASK) >> DEPOSIT_CAP_START_BIT_POSITION;
    }

    /**
     * @dev Gets the configuration flags of the reserve
     * @param self The reserve configuration
     * @return The state flags representing active, frozen, borrowing enabled
     *
     */
    function getFlags(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (bool, bool, bool)
    {
        uint256 dataLocal = self.data;

        return (
            (dataLocal & ~ACTIVE_MASK) != 0,
            (dataLocal & ~FROZEN_MASK) != 0,
            (dataLocal & ~BORROWING_MASK) != 0
        );
    }

    /**
     * @dev Gets the configuration paramters of the reserve
     * @param self The reserve configuration
     * @return The state params representing ltv, liquidation threshold, liquidation bonus, the reserve decimals
     *
     */
    function getParams(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        uint256 dataLocal = self.data;

        return (
            dataLocal & ~LTV_MASK,
            (dataLocal & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION,
            (dataLocal & ~LIQUIDATION_BONUS_MASK) >> LIQUIDATION_BONUS_START_BIT_POSITION,
            (dataLocal & ~DECIMALS_MASK) >> RESERVE_DECIMALS_START_BIT_POSITION,
            (dataLocal & ~RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_START_BIT_POSITION
        );
    }

    /**
     * @dev Gets the configuration paramters of the reserve from a memory object
     * @param self The reserve configuration
     * @return The state params representing ltv, liquidation threshold, liquidation bonus, the reserve decimals
     *
     */
    function getParamsMemory(DataTypes.ReserveConfigurationMap memory self)
        internal
        pure
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        return (
            self.data & ~LTV_MASK,
            (self.data & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION,
            (self.data & ~LIQUIDATION_BONUS_MASK) >> LIQUIDATION_BONUS_START_BIT_POSITION,
            (self.data & ~DECIMALS_MASK) >> RESERVE_DECIMALS_START_BIT_POSITION,
            (self.data & ~RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_START_BIT_POSITION
        );
    }

    /**
     * @dev Gets the configuration flags of the reserve from a memory object
     * @param self The reserve configuration
     * @return The state flags representing active, frozen, borrowing enabled
     *
     */
    function getFlagsMemory(DataTypes.ReserveConfigurationMap memory self)
        internal
        pure
        returns (bool, bool, bool)
    {
        return (
            (self.data & ~ACTIVE_MASK) != 0,
            (self.data & ~FROZEN_MASK) != 0,
            (self.data & ~BORROWING_MASK) != 0
        );
    }

    /**
     * @notice Sets the flashloanable flag for the reserve
     * @param self The reserve configuration
     * @param flashLoanEnabled True if the asset is flashloanable, false otherwise
     */
    function setFlashLoanEnabled(
        DataTypes.ReserveConfigurationMap memory self,
        bool flashLoanEnabled
    ) internal pure {
        self.data = (self.data & FLASHLOAN_ENABLED_MASK)
            | (uint256(flashLoanEnabled ? 1 : 0) << FLASHLOAN_ENABLED_START_BIT_POSITION);
    }

    /**
     * @notice Gets the flashloanable flag for the reserve
     * @param self The reserve configuration
     * @return The flashloanable flag
     */
    function getFlashLoanEnabled(DataTypes.ReserveConfigurationMap memory self)
        internal
        pure
        returns (bool)
    {
        return (self.data & ~FLASHLOAN_ENABLED_MASK) != 0;
    }
}
