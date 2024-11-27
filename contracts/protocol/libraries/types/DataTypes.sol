// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

/**
 * @title DataTypes
 * @author Cod3x
 */
library DataTypes {
    // refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
    struct ReserveData {
        //stores the reserve configuration
        ReserveConfigurationMap configuration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        //timestamp of last update
        uint40 lastUpdateTimestamp;
        //tokens addresses
        address aTokenAddress;
        //variableDebtToken address
        address variableDebtTokenAddress;
        //address of the interest rate strategy
        address interestRateStrategyAddress;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint8 id;
    }

    struct MiniPoolReserveData {
        //stores the reserve configuration
        ReserveConfigurationMap configuration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        //timestamp of last update
        uint40 lastUpdateTimestamp;
        //tokens addresses
        address aTokenAddress;
        //ERC6909 aToken ID.
        uint256 aTokenID;
        //ERC6909 debt token ID.
        uint256 variableDebtTokenID;
        //address of the interest rate strategy
        address interestRateStrategyAddress;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint8 id;
    }

    struct ReserveConfigurationMap {
        //bit 0-15: LTV
        //bit 16-31: Liq. threshold
        //bit 32-47: Liq. bonus
        //bit 48-55: Decimals
        //bit 56: Reserve is active
        //bit 57: reserve is frozen
        //bit 58: borrowing is enabled
        //bit 59: Flashloan is enabled
        //bit 60-75: Cod3x reserve factor
        //bit 76-91: Minipool owner reserve factor
        //bit 92-163: deposit cap
        //bit 164: reserve type
        //bit 165-255: unused
        uint256 data;
    }

    struct ReserveReference {
        address asset; // underlying asset
        bool reserveType; // if the reserve is vault-boosted
    }

    struct UserConfigurationMap {
        uint256 data;
    }

    enum InterestRateMode {
        NONE,
        VARIABLE
    }
}
