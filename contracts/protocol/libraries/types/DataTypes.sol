// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

/**
 * @title DataTypes
 * @author Cod3x
 * @notice Library containing data structures used across the protocol
 */
library DataTypes {
    /**
     * @notice Stores all configuration and state for a lending pool reserve
     * @param configuration Reserve configuration parameters
     * @param liquidityIndex Current liquidity index, expressed in ray
     * @param variableBorrowIndex Current variable borrow index, expressed in ray
     * @param currentLiquidityRate Current supply interest rate, expressed in ray
     * @param currentVariableBorrowRate Current variable borrow interest rate, expressed in ray
     * @param lastUpdateTimestamp Timestamp of the last reserve update
     * @param aTokenAddress Address of the aToken contract
     * @param variableDebtTokenAddress Address of the variable debt token
     * @param interestRateStrategyAddress Address of the interest rate strategy
     * @param id Identifier of the reserve in the list of active reserves
     */
    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 variableBorrowIndex;
        uint128 currentLiquidityRate;
        uint128 currentVariableBorrowRate;
        uint40 lastUpdateTimestamp;
        address aTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint8 id;
    }

    /**
     * @notice Stores all configuration and state for a minipool reserve
     * @param configuration Reserve configuration parameters
     * @param liquidityIndex Current liquidity index, expressed in ray
     * @param variableBorrowIndex Current variable borrow index, expressed in ray
     * @param currentLiquidityRate Current supply interest rate, expressed in ray
     * @param currentVariableBorrowRate Current variable borrow interest rate, expressed in ray
     * @param lastUpdateTimestamp Timestamp of the last reserve update
     * @param aTokenAddress Address of the ERC6909 token contract for aTokens
     * @param aTokenID ID of the ERC6909 aToken
     * @param variableDebtTokenID ID of the ERC6909 debt token
     * @param interestRateStrategyAddress Address of the interest rate strategy
     * @param id Identifier of the reserve in the list of active reserves
     */
    struct MiniPoolReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 variableBorrowIndex;
        uint128 currentLiquidityRate;
        uint128 currentVariableBorrowRate;
        uint40 lastUpdateTimestamp;
        address aTokenAddress;
        uint256 aTokenID;
        uint256 variableDebtTokenID;
        address interestRateStrategyAddress;
        uint8 id;
    }

    /**
     * @notice Stores the configuration parameters for a reserve
     * @dev Encoded as a packed bitfield for gas optimization
     * bits 0-15: Loan to Value ratio
     * bits 16-31: Liquidation threshold
     * bits 32-47: Liquidation bonus
     * bits 48-55: Decimals of the underlying asset
     * bit 56: Reserve is active
     * bit 57: Reserve is frozen
     * bit 58: Borrowing is enabled
     * bit 59: Flashloan is enabled
     * bits 60-75: Cod3x reserve factor
     * bits 76-91: Minipool owner reserve factor
     * bits 92-163: Deposit cap
     * bit 164: Reserve type
     * bits 165-255: Unused
     */
    struct ReserveConfigurationMap {
        uint256 data;
    }

    /**
     * @notice Stores reference information for a reserve
     * @param asset Address of the underlying asset
     * @param reserveType Boolean indicating if the reserve is vault-boosted
     */
    struct ReserveReference {
        address asset;
        bool reserveType;
    }

    /**
     * @notice Stores the user's configuration for all reserves
     * @dev Encoded as a packed bitfield for gas optimization
     */
    struct UserConfigurationMap {
        uint256 data;
    }

    /**
     * @notice Defines the possible interest rate modes for flashloans
     * @param NONE The flashloan must not be paid back
     * @param VARIABLE If not paid back, try to open a variable rate loan
     */
    enum InterestRateMode {
        NONE,
        VARIABLE
    }
}
