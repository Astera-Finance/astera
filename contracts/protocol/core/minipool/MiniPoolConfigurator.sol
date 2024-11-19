// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {VersionedInitializable} from
    "../../../../contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {InitializableImmutableAdminUpgradeabilityProxy} from
    "../../../../contracts/protocol/libraries/upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol";
import {ReserveConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ILendingPoolAddressesProvider} from
    "../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {IERC20Detailed} from
    "../../../../contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {PercentageMath} from "../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {IInitializableDebtToken} from "../../../../contracts/interfaces/IInitializableDebtToken.sol";
import {IInitializableAToken} from "../../../../contracts/interfaces/IInitializableAToken.sol";
import {IRewarder} from "../../../../contracts/interfaces/IRewarder.sol";
import {ILendingPoolConfigurator} from
    "../../../../contracts/interfaces/ILendingPoolConfigurator.sol";
import {IAToken} from "../../../../contracts/interfaces/IAToken.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IAERC6909} from "../../../../contracts/interfaces/IAERC6909.sol";
import {IMiniPoolConfigurator} from "../../../../contracts/interfaces/IMiniPoolConfigurator.sol";
import {IMiniPool} from "../../../../contracts/interfaces/IMiniPool.sol";
/**
 * @title LendingPoolConfigurator contract
 * @author Cod3x
 * @dev Implements the configuration methods for the Cod3x Lend Lendingpool
 *
 */

contract MiniPoolConfigurator is VersionedInitializable, IMiniPoolConfigurator {
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IMiniPoolAddressesProvider public addressesProvider;

    modifier onlyPoolAdmin(address pool) {
        uint256 id = addressesProvider.getMiniPoolId(pool);
        require(addressesProvider.getPoolAdmin(id) == msg.sender, Errors.CALLER_NOT_POOL_ADMIN);
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
        onlyPoolAdmin(address(pool))
    {
        for (uint256 i = 0; i < input.length; i++) {
            _initReserve(pool, input[i]);
        }
    }

    function _initReserve(IMiniPool pool, InitReserveInput calldata input) internal {
        address AERC6909proxy = addressesProvider.getMiniPoolToAERC6909(address(pool));
        (uint256 aTokenID, uint256 debtTokenID,) = IAERC6909(AERC6909proxy).initReserve(
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
            pool.getConfiguration(input.underlyingAsset);

        currentConfig.setDecimals(input.underlyingAssetDecimals);
        currentConfig.setActive(true);
        currentConfig.setFrozen(false);
        currentConfig.setFlashLoanEnabled(true);

        pool.setConfiguration(input.underlyingAsset, currentConfig.data);
    }

    /**
     * @dev Enables borrowing on a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param pool Minipool address
     *
     */
    function enableBorrowingOnReserve(address asset, IMiniPool pool)
        external
        onlyPoolAdmin(address(pool))
    {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setBorrowingEnabled(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit BorrowingEnabledOnReserve(asset);
    }

    /**
     * @dev Disables borrowing on a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param pool Minipool address
     *
     */
    function disableBorrowingOnReserve(address asset, IMiniPool pool)
        external
        onlyPoolAdmin(address(pool))
    {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setBorrowingEnabled(false);

        pool.setConfiguration(asset, currentConfig.data);
        emit BorrowingDisabledOnReserve(asset);
    }

    /**
     * @dev Configures the reserve collateralization parameters
     * all the values are expressed in percentages with two decimals of precision. A valid value is 10000, which means 100.00%
     * @param asset The address of the underlying asset of the reserve
     * @param ltv The loan to value of the asset when used as collateral
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param liquidationBonus The bonus liquidators receive to liquidate this asset. The values is always above 100%. A value of 105%
     * means the liquidator will receive a 5% bonus
     *
     */
    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        IMiniPool pool
    ) external onlyPoolAdmin(address(pool)) {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

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
            _checkNoLiquidity(asset, pool);
        }

        currentConfig.setLtv(ltv);
        currentConfig.setLiquidationThreshold(liquidationThreshold);
        currentConfig.setLiquidationBonus(liquidationBonus);

        pool.setConfiguration(asset, currentConfig.data);

        emit CollateralConfigurationChanged(asset, ltv, liquidationThreshold, liquidationBonus);
    }

    /**
     * @dev Activates a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param pool Minipool address
     *
     */
    function activateReserve(address asset, IMiniPool pool) external onlyPoolAdmin(address(pool)) {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setActive(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveActivated(asset);
    }

    /**
     * @dev Deactivates a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param pool Minipool address
     *
     */
    function deactivateReserve(address asset, IMiniPool pool)
        external
        onlyPoolAdmin(address(pool))
    {
        _checkNoLiquidity(asset, pool);

        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setActive(false);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveDeactivated(asset);
    }

    /**
     * @dev Freezes a reserve. A frozen reserve doesn't allow any new deposit, or borrow
     *  but allows repayments, liquidations, and withdrawals
     * @param asset The address of the underlying asset of the reserve
     * @param pool Minipool address
     *
     */
    function freezeReserve(address asset, IMiniPool pool) external onlyPoolAdmin(address(pool)) {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setFrozen(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveFrozen(asset);
    }

    /**
     * @dev Unfreezes a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param pool Minipool address
     *
     */
    function unfreezeReserve(address asset, IMiniPool pool) external onlyPoolAdmin(address(pool)) {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setFrozen(false);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveUnfrozen(asset);
    }

    /**
     * @dev Enable Flash loan.
     * @param asset The address of the underlying asset of the reserve
     * @param pool Minipool address
     *
     */
    function enableFlashloan(address asset, IMiniPool pool) external onlyPoolAdmin(address(pool)) {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setFlashLoanEnabled(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit EnableFlashloan(asset);
    }

    /**
     * @dev Disable Flash loan.
     * @param asset The address of the underlying asset of the reserve
     * @param pool Minipool address
     *
     */
    function disableFlashloan(address asset, IMiniPool pool)
        external
        onlyPoolAdmin(address(pool))
    {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setFlashLoanEnabled(false);

        pool.setConfiguration(asset, currentConfig.data);

        emit DisableFlashloan(asset);
    }

    /**
     * @dev Updates the Cod3x reserve factor of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveFactor The new reserve factor of the reserve
     *
     */
    function setCod3xReserveFactor(address asset, uint256 reserveFactor, IMiniPool pool)
        external
        onlyEmergencyAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setCod3xReserveFactor(reserveFactor);

        pool.setConfiguration(asset, currentConfig.data);

        emit Cod3xReserveFactorChanged(asset, reserveFactor);
    }

    /**
     * @dev Updates the minipool owner reserve factor of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveFactor The new reserve factor of the reserve
     *
     */
    function setMinipoolOwnerReserveFactor(address asset, uint256 reserveFactor, IMiniPool pool)
        external
        onlyPoolAdmin(address(pool))
    {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setMinipoolOwnerReserveFactor(reserveFactor);

        pool.setConfiguration(asset, currentConfig.data);

        emit MinipoolOwnerReserveFactorChanged(asset, reserveFactor);
    }

    function setDepositCap(address asset, uint256 depositCap, IMiniPool pool)
        external
        onlyEmergencyAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setDepositCap(depositCap);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveDepositCapChanged(asset, depositCap);
    }

    /**
     * @dev Sets the interest rate strategy of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param rateStrategyAddress The new address of the interest strategy contract
     * @param pool Minipool address
     *
     */

    // Discuss access control
    function setReserveInterestRateStrategyAddress(
        address asset,
        address rateStrategyAddress,
        IMiniPool pool
    ) external onlyEmergencyAdmin {
        pool.setReserveInterestRateStrategyAddress(asset, rateStrategyAddress);
        emit ReserveInterestRateStrategyChanged(asset, rateStrategyAddress);
    }

    /**
     * @dev pauses or unpauses all the actions of the protocol, including aToken transfers
     * @param val true if protocol needs to be paused, false otherwise
     *
     */
    function setPoolPause(bool val, IMiniPool pool) external onlyEmergencyAdmin {
        pool.setPause(val);
    }

    function _checkNoLiquidity(address asset, IMiniPool pool) internal view {
        DataTypes.MiniPoolReserveData memory reserveData = pool.getReserveData(asset);

        uint256 availableLiquidity = IERC20Detailed(asset).balanceOf(reserveData.aTokenAddress);

        require(
            availableLiquidity == 0 && reserveData.currentLiquidityRate == 0,
            Errors.LPC_RESERVE_LIQUIDITY_NOT_0
        );
    }

    // Discuss access control
    function setRewarderForReserve(address asset, address rewarder, IMiniPool pool)
        external
        onlyEmergencyAdmin
    {
        pool.setRewarderForReserve(asset, rewarder);
    }

    // Discuss access control
    function updateFlashloanPremiumTotal(uint128 newFlashloanPremiumTotal, IMiniPool pool)
        external
        onlyEmergencyAdmin
    {
        require(
            newFlashloanPremiumTotal <= PercentageMath.PERCENTAGE_FACTOR,
            Errors.LPC_FLASHLOAN_PREMIUM_INVALID
        );
        pool.updateFlashLoanFee(newFlashloanPremiumTotal);
    }

    function setPoolAdmin(address admin, IMiniPool pool) public onlyPoolAdmin(address(pool)) {
        uint256 id = addressesProvider.getMiniPoolId(address(pool));
        addressesProvider.setPoolAdmin(id, admin);
    }

    function setMiniPoolToMinipoolOwnerTreasury(address treasury, IMiniPool pool)
        public
        onlyPoolAdmin(address(pool))
    {
        uint256 id = addressesProvider.getMiniPoolId(address(pool));
        addressesProvider.setMiniPoolToMinipoolOwnerTreasury(id, treasury);
    }
}
