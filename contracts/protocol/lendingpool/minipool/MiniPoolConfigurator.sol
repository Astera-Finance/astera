// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {SafeMath} from "contracts/dependencies/openzeppelin/contracts/SafeMath.sol";
import {VersionedInitializable} from
    "contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {InitializableImmutableAdminUpgradeabilityProxy} from
    "contracts/protocol/libraries/upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ReserveBorrowConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveBorrowConfiguration.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {IERC20Detailed} from "contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {IInitializableDebtToken} from "contracts/interfaces/IInitializableDebtToken.sol";
import {IInitializableAToken} from "contracts/interfaces/IInitializableAToken.sol";
import {IRewarder} from "contracts/interfaces/IRewarder.sol";
import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IAERC6909} from "contracts/interfaces/IAERC6909.sol";
import {IMiniPoolConfigurator} from "contracts/interfaces/IMiniPoolConfigurator.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";
/**
 * @title LendingPoolConfigurator contract
 * @author Aave
 * @dev Implements the configuration methods for the Aave protocol
 *
 */

contract MiniPoolConfigurator is VersionedInitializable, IMiniPoolConfigurator {
    using SafeMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using ReserveBorrowConfiguration for DataTypes.ReserveBorrowConfigurationMap;

    IMiniPoolAddressesProvider public addressesProvider;

    modifier onlyPoolAdmin() {
        require(addressesProvider.getPoolAdmin() == msg.sender, Errors.CALLER_NOT_POOL_ADMIN);
        _;
    }

    modifier onlyEmergencyAdmin() {
        require(
            addressesProvider.getEmergencyAdmin() == msg.sender,
            Errors.LPC_CALLER_NOT_EMERGENCY_ADMIN
        );
        _;
    }

    uint256 internal constant CONFIGURATOR_REVISION = 0x1;

    function getRevision() internal pure override returns (uint256) {
        return CONFIGURATOR_REVISION;
    }

    function initialize(IMiniPoolAddressesProvider provider) public initializer {
        addressesProvider = provider;
    }

    /**
     * @dev Initializes reserves in batch
     *
     */
    function batchInitReserve(InitReserveInput[] calldata input, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        for (uint256 i = 0; i < input.length; i++) {
            _initReserve(pool, input[i]);
        }
    }

    function _initReserve(IMiniPool pool, InitReserveInput calldata input) internal {
        address AERC6909proxy = addressesProvider.getMiniPoolToAERC6909(address(pool));
        (uint256 aTokenID, uint256 debtTokenID, bool isTranche) = IAERC6909(AERC6909proxy)
            .initReserve(
            input.underlyingAsset,
            input.underlyingAssetName,
            input.underlyingAssetSymbol,
            input.underlyingAssetDecimals
        );
        pool.initReserve(
            input.underlyingAsset,
            IAERC6909(AERC6909proxy),
            aTokenID,
            debtTokenID,
            input.interestRateStrategyAddress
        );
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(input.underlyingAsset, false);

        currentConfig.setDecimals(input.underlyingAssetDecimals);
        currentConfig.setActive(true);
        currentConfig.setFrozen(false);
        currentConfig.setFlashLoanEnabled(true);

        pool.setConfiguration(input.underlyingAsset, false, currentConfig.data);
    }

    /**
     * @dev Enables borrowing on a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function enableBorrowingOnReserve(address asset, bool reserveType, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setBorrowingEnabled(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit BorrowingEnabledOnReserve(asset, reserveType);
    }

    /**
     * @dev Disables borrowing on a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function disableBorrowingOnReserve(address asset, bool reserveType, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setBorrowingEnabled(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);
        emit BorrowingDisabledOnReserve(asset, reserveType);
    }

    /**
     * @dev Configures the reserve collateralization parameters
     * all the values are expressed in percentages with two decimals of precision. A valid value is 10000, which means 100.00%
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param ltv The loan to value of the asset when used as collateral
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param liquidationBonus The bonus liquidators receive to liquidate this asset. The values is always above 100%. A value of 105%
     * means the liquidator will receive a 5% bonus
     *
     */
    function configureReserveAsCollateral(
        address asset,
        bool reserveType,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        IMiniPool pool
    ) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);
        DataTypes.ReserveBorrowConfigurationMap memory currentBorrowConfig =
            pool.getBorrowConfiguration(asset, reserveType);

        //validation of the parameters: the LTV can
        //only be lower or equal than the liquidation threshold
        //(otherwise a loan against the asset would cause instantaneous liquidation)
        require(ltv <= liquidationThreshold, Errors.LPC_INVALID_CONFIGURATION);

        if (liquidationThreshold != 0) {
            //liquidation bonus must be bigger than 100.00%, otherwise the liquidator would receive less
            //collateral than needed to cover the debt
            require(
                liquidationBonus > PercentageMath.PERCENTAGE_FACTOR,
                Errors.LPC_INVALID_CONFIGURATION
            );

            //if threshold * bonus is less than PERCENTAGE_FACTOR, it's guaranteed that at the moment
            //a loan is taken there is enough collateral available to cover the liquidation bonus
            require(
                liquidationThreshold.percentMul(liquidationBonus)
                    <= PercentageMath.PERCENTAGE_FACTOR,
                Errors.LPC_INVALID_CONFIGURATION
            );
        } else {
            require(liquidationBonus == 0, Errors.LPC_INVALID_CONFIGURATION);
            //if the liquidation threshold is being set to 0,
            // the reserve is being disabled as collateral. To do so,
            //we need to ensure no liquidity is deposited
            _checkNoLiquidity(asset, reserveType, pool);
        }

        currentConfig.setLtv(ltv);
        currentBorrowConfig.setLowVolatilityLtv(ltv);
        currentBorrowConfig.setMediumVolatilityLtv(ltv);
        currentBorrowConfig.setHighVolatilityLtv(ltv);
        currentConfig.setLiquidationThreshold(liquidationThreshold);
        currentBorrowConfig.setLowVolatilityLiquidationThreshold(liquidationThreshold);
        currentBorrowConfig.setMediumVolatilityLiquidationThreshold(liquidationThreshold);
        currentBorrowConfig.setHighVolatilityLiquidationThreshold(liquidationThreshold);
        currentConfig.setLiquidationBonus(liquidationBonus);

        pool.setConfiguration(asset, reserveType, currentConfig.data);
        pool.setBorrowConfiguration(asset, reserveType, currentBorrowConfig.data);

        emit CollateralConfigurationChanged(
            asset, reserveType, ltv, liquidationThreshold, liquidationBonus
        );
    }

    /**
     * @dev Activates a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function activateReserve(address asset, bool reserveType, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setActive(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveActivated(asset, reserveType);
    }

    /**
     * @dev Deactivates a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function deactivateReserve(address asset, bool reserveType, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        _checkNoLiquidity(asset, reserveType, pool);

        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setActive(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveDeactivated(asset, reserveType);
    }

    /**
     * @dev Freezes a reserve. A frozen reserve doesn't allow any new deposit, or borrow
     *  but allows repayments, liquidations, and withdrawals
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function freezeReserve(address asset, bool reserveType, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFrozen(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveFrozen(asset, reserveType);
    }

    /**
     * @dev Unfreezes a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function unfreezeReserve(address asset, bool reserveType, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFrozen(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveUnfrozen(asset, reserveType);
    }

    /**
     * @dev Pause a reserve.
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param pool Minipool address
     *
     */
    function pauseReserve(address asset, bool reserveType, IMiniPool pool) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setPaused(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReservePaused(asset, reserveType);
    }

    /**
     * @dev Unpause a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param pool Minipool address
     *
     */
    function unpauseReserve(address asset, bool reserveType, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setPaused(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveUnpaused(asset, reserveType);
    }

    /**
     * @dev Enable Flash loan.
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param pool Minipool address
     *
     */
    function enableFlashloan(address asset, bool reserveType, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFlashLoanEnabled(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit EnableFlashloan(asset, reserveType);
    }

    /**
     * @dev Disable Flash loan.
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param pool Minipool address
     *
     */
    function disableFlashloan(address asset, bool reserveType, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFlashLoanEnabled(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit DisableFlashloan(asset, reserveType);
    }

    /**
     * @dev Updates the reserve factor of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param reserveFactor The new reserve factor of the reserve
     *
     */
    function setReserveFactor(
        address asset,
        bool reserveType,
        uint256 reserveFactor,
        IMiniPool pool
    ) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setReserveFactor(reserveFactor);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveFactorChanged(asset, reserveType, reserveFactor);
    }

    function setDepositCap(address asset, bool reserveType, uint256 depositCap, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setDepositCap(depositCap);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveDepositCapChanged(asset, reserveType, depositCap);
    }

    function setReserveVolatilityTier(address asset, bool reserveType, uint256 tier, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveBorrowConfigurationMap memory currentBorrowConfig =
            pool.getBorrowConfiguration(asset, reserveType);

        currentBorrowConfig.setVolatilityTier(tier);

        pool.setBorrowConfiguration(asset, reserveType, currentBorrowConfig.data);

        emit ReserveVolatilityTierChanged(asset, reserveType, tier);
    }

    function setLowVolatilityLtv(address asset, bool reserveType, uint256 ltv, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveBorrowConfigurationMap memory currentBorrowConfig =
            pool.getBorrowConfiguration(asset, reserveType);

        currentBorrowConfig.setLowVolatilityLtv(ltv);

        pool.setBorrowConfiguration(asset, reserveType, currentBorrowConfig.data);

        emit ReserveLowVolatilityLtvChanged(asset, reserveType, ltv);
    }

    function setMediumVolatilityLtv(address asset, bool reserveType, uint256 ltv, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveBorrowConfigurationMap memory currentBorrowConfig =
            pool.getBorrowConfiguration(asset, reserveType);

        currentBorrowConfig.setMediumVolatilityLtv(ltv);

        pool.setBorrowConfiguration(asset, reserveType, currentBorrowConfig.data);

        emit ReserveMediumVolatilityLtvChanged(asset, reserveType, ltv);
    }

    function setHighVolatilityLtv(address asset, bool reserveType, uint256 ltv, IMiniPool pool)
        external
        onlyPoolAdmin
    {
        // Store update params in array
        DataTypes.ReserveBorrowConfigurationMap memory currentBorrowConfig =
            pool.getBorrowConfiguration(asset, reserveType);

        currentBorrowConfig.setHighVolatilityLtv(ltv);

        pool.setBorrowConfiguration(asset, reserveType, currentBorrowConfig.data);

        emit ReserveHighVolatilityLtvChanged(asset, reserveType, ltv);
    }

    /**
     * @dev Sets the interest rate strategy of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param rateStrategyAddress The new address of the interest strategy contract
     *
     */
    function setReserveInterestRateStrategyAddress(
        address asset,
        bool reserveType,
        address rateStrategyAddress,
        IMiniPool pool
    ) external onlyPoolAdmin {
        pool.setReserveInterestRateStrategyAddress(asset, reserveType, rateStrategyAddress);
        emit ReserveInterestRateStrategyChanged(asset, reserveType, rateStrategyAddress);
    }

    /**
     * @dev pauses or unpauses all the actions of the protocol, including aToken transfers
     * @param val true if protocol needs to be paused, false otherwise
     *
     */
    function setPoolPause(bool val, IMiniPool pool) external onlyEmergencyAdmin {
        pool.setPause(val);
    }

    function _checkNoLiquidity(address asset, bool reserveType, IMiniPool pool) internal view {
        DataTypes.MiniPoolReserveData memory reserveData = pool.getReserveData(asset, reserveType);

        uint256 availableLiquidity = IERC20Detailed(asset).balanceOf(reserveData.aTokenAddress);

        require(
            availableLiquidity == 0 && reserveData.currentLiquidityRate == 0,
            Errors.LPC_RESERVE_LIQUIDITY_NOT_0
        );
    }
}
