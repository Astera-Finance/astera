// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {Errors} from '../helpers/Errors.sol';
import {DataTypes} from '../types/DataTypes.sol';

/**
 * @title ReserveConfiguration library
 * @author Aave
 * @notice Implements the bitmap logic to handle the reserve configuration regarding borrows and isolated markets
 */
library ReserveBorrowConfiguration {
  uint256 constant LOW_VOLATILITY_LTV_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000; // prettier-ignore
  uint256 constant LOW_VOLATILITY_LIQUIDATION_THRESHOLD_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFF; // prettier-ignore
  uint256 constant MEDIUM_VOLATILITY_LTV_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFF; // prettier-ignore
  uint256 constant MEDIUM_VOLATILITY_LIQUIDATION_THRESHOLD_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFF; // prettier-ignore
  uint256 constant HIGH_VOLATILITY_LTV_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFF; // prettier-ignore
  uint256 constant HIGH_VOLATILITY_LIQUIDATION_THRESHOLD_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFFFFFF; // prettier-ignore
  uint256 constant VOLATILITY_TIER_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore

  /// @dev For the Low Volatility, the start bit is 0 (up to 15), hence no bitshifting is needed
//   uint256 constant LOW_VOLATILITY_LTV_START_BIT_POSITION = 0;
  uint256 constant LOW_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16;
  uint256 constant MEDIUM_VOLATILITY_LTV_START_BIT_POSITION = 32;
  uint256 constant MEDIUM_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION = 48;
  uint256 constant HIGH_VOLATILITY_LTV_START_BIT_POSITION = 64;
  uint256 constant HIGH_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION = 80;
  uint256 constant VOLATILITY_TIER_START_BIT_POSITION = 96;

  uint256 constant MAX_VALID_LTV = 65535;
  uint256 constant MAX_VALID_LIQUIDATION_THRESHOLD = 65535;
  uint256 constant MAX_VALID_VOLATILITY_TIER = 4;

    function setLowVolatilityLtv(DataTypes.ReserveConfigurationMap memory self, uint256 lowVolatilityLtv) internal pure {
        require(lowVolatilityLtv <= MAX_VALID_LTV, Errors.RC_INVALID_LTV);

        self.data = (self.data & LOW_VOLATILITY_LTV_MASK) | lowVolatilityLtv;
    }

    function getLowVolatilityLtv(DataTypes.ReserveConfigurationMap storage self) internal view returns (uint256) {
        return self.data & ~LOW_VOLATILITY_LTV_MASK;
    }

    function setLowVolatilityLiquidationThreshold(DataTypes.ReserveConfigurationMap memory self, uint256 threshold)
        internal
        pure
    {
        require(threshold <= MAX_VALID_LIQUIDATION_THRESHOLD, Errors.RC_INVALID_LIQ_THRESHOLD);

        self.data =
        (self.data & LOW_VOLATILITY_LIQUIDATION_THRESHOLD_MASK) |
        (threshold << LOW_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION);
    }

    function getLowVolatilityLiquidationThreshold(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~LOW_VOLATILITY_LIQUIDATION_THRESHOLD_MASK) >> LOW_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION;
    }

    function setMediumVolatilityLtv(DataTypes.ReserveConfigurationMap memory self, uint256 mediumVolatilityLtv) internal pure {
        require(mediumVolatilityLtv <= MAX_VALID_LTV, Errors.RC_INVALID_LTV);

        self.data = (self.data & MEDIUM_VOLATILITY_LTV_MASK) | (mediumVolatilityLtv << MEDIUM_VOLATILITY_LTV_START_BIT_POSITION);
    }

    function getMediumVolatilityLtv(DataTypes.ReserveConfigurationMap storage self) internal view returns (uint256) {
        return (self.data & ~MEDIUM_VOLATILITY_LTV_MASK) >> MEDIUM_VOLATILITY_LTV_START_BIT_POSITION;
    }

    function setMediumVolatilityLiquidationThreshold(DataTypes.ReserveConfigurationMap memory self, uint256 threshold)
        internal
        pure
    {
        require(threshold <= MAX_VALID_LIQUIDATION_THRESHOLD, Errors.RC_INVALID_LIQ_THRESHOLD);

        self.data =
        (self.data & MEDIUM_VOLATILITY_LIQUIDATION_THRESHOLD_MASK) |
        (threshold << MEDIUM_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION);
    }

    function getMediumVolatilityLiquidationThreshold(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~MEDIUM_VOLATILITY_LIQUIDATION_THRESHOLD_MASK) >> MEDIUM_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION;
    }

    function setHighVolatilityLtv(DataTypes.ReserveConfigurationMap memory self, uint256 highVolatilityLtv) internal pure {
        require(highVolatilityLtv <= MAX_VALID_LTV, Errors.RC_INVALID_LTV);

        self.data = (self.data & HIGH_VOLATILITY_LTV_MASK) | (highVolatilityLtv << HIGH_VOLATILITY_LTV_START_BIT_POSITION);
    }

    function getHighVolatilityLtv(DataTypes.ReserveConfigurationMap storage self) internal view returns (uint256) {
        return (self.data & ~HIGH_VOLATILITY_LTV_MASK) >> HIGH_VOLATILITY_LTV_START_BIT_POSITION;
    }

    function setHighVolatilityLiquidationThreshold(DataTypes.ReserveConfigurationMap memory self, uint256 threshold)
        internal
        pure
    {
        require(threshold <= MAX_VALID_LIQUIDATION_THRESHOLD, Errors.RC_INVALID_LIQ_THRESHOLD);

        self.data =
        (self.data & HIGH_VOLATILITY_LIQUIDATION_THRESHOLD_MASK) |
        (threshold << HIGH_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION);
    }

    function getHighVolatilityLiquidationThreshold(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~HIGH_VOLATILITY_LIQUIDATION_THRESHOLD_MASK) >> HIGH_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION;
    }

    /**
    * @notice Sets the volatility tier of this reserve
    * @dev The higher the tier, the lower the user will be able to borrow accross all his assets
    * @param self The reserve configuration
    * @param volatilityTier The rank of the reserve
    */
    function setVolatilityTier(
        DataTypes.ReserveConfigurationMap memory self,
        uint256 volatilityTier
    ) internal pure {
        require (volatilityTier <= MAX_VALID_VOLATILITY_TIER, Errors.RC_INVALID_VOLATILITY_TIER);
        self.data =
        (self.data & VOLATILITY_TIER_MASK) |
        (volatilityTier << VOLATILITY_TIER_START_BIT_POSITION);
    }

    /**
    * @notice Gets the volatility tier of the reserve
    * @dev The higher the tier, the lower the user will be able to borrow accross all his assets
    * @param self The reserve configuration
    * @return volatilityTier The reserve's volatility tier
    */
    function getVolatilityTier(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data & ~VOLATILITY_TIER_MASK) >> VOLATILITY_TIER_START_BIT_POSITION;
    }

    /**
    * @dev Gets the configuration paramters of the reserve
    * @param self The reserve configuration
    * @return The state params representing low, medium, high paarms for the ltv and liquidation threshold
    **/
    function getVolatilityParams(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
        )
    {
        uint256 dataLocal = self.data;

        return (
        dataLocal & ~LOW_VOLATILITY_LTV_MASK,
        (dataLocal & ~LOW_VOLATILITY_LIQUIDATION_THRESHOLD_MASK) >> LOW_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION,
        (dataLocal & ~MEDIUM_VOLATILITY_LTV_MASK) >> ~MEDIUM_VOLATILITY_LTV_START_BIT_POSITION,
        (dataLocal & ~MEDIUM_VOLATILITY_LIQUIDATION_THRESHOLD_MASK) >> MEDIUM_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION,
        (dataLocal & ~HIGH_VOLATILITY_LTV_MASK) >> ~HIGH_VOLATILITY_LTV_START_BIT_POSITION,
        (dataLocal & ~HIGH_VOLATILITY_LIQUIDATION_THRESHOLD_MASK) >> HIGH_VOLATILITY_LIQUIDATION_THRESHOLD_START_BIT_POSITION
        );
    }
}
