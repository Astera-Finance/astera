// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {VersionedInitializable} from
    "../../../../contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {ReserveConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {IERC20Detailed} from
    "../../../../contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {PercentageMath} from "../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IAERC6909} from "../../../../contracts/interfaces/IAERC6909.sol";
import {IMiniPoolConfigurator} from "../../../../contracts/interfaces/IMiniPoolConfigurator.sol";
import {IMiniPool} from "../../../../contracts/interfaces/IMiniPool.sol";

/**
 * @title MiniPoolConfigurator contract.
 * @author Cod3x.
 * @notice Implements the configuration methods for the Cod3x Lend MiniPool protocol.
 * @dev This contract manages reserve configurations, pool parameters, and access controls.
 */
contract MiniPoolConfigurator is VersionedInitializable, IMiniPoolConfigurator {
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 internal constant CONFIGURATOR_REVISION = 0x1;
    IMiniPoolAddressesProvider public addressesProvider;

    constructor() {
        _blockInitializing();
    }

    /**
     * @dev Only allows pool admin to call the function.
     * @param pool The address of the MiniPool being accessed.
     */
    modifier onlyPoolAdmin(address pool) {
        uint256 id = addressesProvider.getMiniPoolId(pool);
        require(addressesProvider.getPoolAdmin(id) == msg.sender, Errors.VL_CALLER_NOT_POOL_ADMIN);
        _;
    }

    /**
     * @dev Only allows main pool admin to call the function.
     */
    modifier onlyMainPoolAdmin() {
        require(addressesProvider.getMainPoolAdmin() == msg.sender, Errors.VL_CALLER_NOT_POOL_ADMIN);
        _;
    }

    /**
     * @dev Only allows emergency admin to call the function.
     */
    modifier onlyEmergencyAdmin() {
        require(
            addressesProvider.getEmergencyAdmin() == msg.sender,
            Errors.VL_CALLER_NOT_EMERGENCY_ADMIN
        );
        _;
    }

    /**
     * @dev Returns the revision number of the contract.
     * @return The revision number.
     */
    function getRevision() internal pure override returns (uint256) {
        return CONFIGURATOR_REVISION;
    }

    /**
     * @dev Initializes the MiniPoolConfigurator.
     * @param provider The address of the MiniPoolAddressesProvider.
     */
    function initialize(IMiniPoolAddressesProvider provider) public initializer {
        addressesProvider = provider;
    }

    /*___ Only Main Pool ___*/

    /**
     * @dev Initializes multiple reserves in a single transaction.
     * @param input Array of reserve initialization parameters.
     * @param pool The MiniPool instance to initialize reserves for.
     */
    function batchInitReserve(InitReserveInput[] calldata input, IMiniPool pool)
        external
        onlyMainPoolAdmin
    {
        for (uint256 i = 0; i < input.length; i++) {
            _initReserve(pool, input[i]);
        }
    }

    /**
     * @dev Sets the rewarder contract for a specific reserve.
     * @param asset The address of the underlying asset.
     * @param rewarder The address of the rewarder contract.
     * @param pool The MiniPool instance to set the rewarder for.
     */
    function setRewarderForReserve(address asset, address rewarder, IMiniPool pool)
        external
        onlyMainPoolAdmin
    {
        pool.setRewarderForReserve(asset, rewarder);
    }

    /**
     * @dev Updates the total flashloan premium.
     * @param newFlashloanPremiumTotal The new flashloan premium total.
     * @param pool The MiniPool instance to update.
     */
    function updateFlashloanPremiumTotal(uint128 newFlashloanPremiumTotal, IMiniPool pool)
        external
        onlyMainPoolAdmin
    {
        require(
            newFlashloanPremiumTotal <= PercentageMath.PERCENTAGE_FACTOR,
            Errors.VL_FLASHLOAN_PREMIUM_INVALID
        );
        uint128 oldFlashloanPremiumTotal = uint128(pool.FLASHLOAN_PREMIUM_TOTAL());

        pool.updateFlashLoanFee(newFlashloanPremiumTotal);
        emit FlashloanPremiumTotalUpdated(oldFlashloanPremiumTotal, newFlashloanPremiumTotal);
    }

    /**
     * @dev Sets the Cod3x treasury address for all mini pools.
     * @param treasury The new treasury address.
     */
    function setCod3xTreasury(address treasury) public onlyMainPoolAdmin {
        addressesProvider.setCod3xTreasury(treasury);
    }

    /**
     * @dev Sets the flow limit for an asset in a MiniPool.
     * @param asset The address of the asset.
     * @param miniPool The address of the MiniPool.
     * @param limit The new flow limit value.
     */
    function setFlowLimit(address asset, address miniPool, uint256 limit)
        public
        onlyMainPoolAdmin
    {
        addressesProvider.setFlowLimit(asset, miniPool, limit);

        emit FlowLimitUpdated(asset, miniPool, limit);
    }

    /**
     * @dev Sets the interest rate strategy for a reserve.
     * @param asset The address of the underlying asset.
     * @param rateStrategyAddress The new interest rate strategy address.
     * @param pool The MiniPool instance to update.
     */
    function setReserveInterestRateStrategyAddress(
        address asset,
        address rateStrategyAddress,
        IMiniPool pool
    ) external onlyMainPoolAdmin {
        pool.syncIndexesState(asset);

        pool.setReserveInterestRateStrategyAddress(asset, rateStrategyAddress);

        pool.syncRatesState(asset);

        emit ReserveInterestRateStrategyChanged(asset, rateStrategyAddress);
    }

    /**
     * @dev Updates the Cod3x reserve factor for a reserve.
     * @param asset The address of the underlying asset.
     * @param reserveFactor The new reserve factor.
     * @param pool The MiniPool instance to update.
     */
    function setCod3xReserveFactor(address asset, uint256 reserveFactor, IMiniPool pool)
        external
        onlyMainPoolAdmin
    {
        pool.syncIndexesState(asset);

        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setCod3xReserveFactor(reserveFactor);

        pool.setConfiguration(asset, currentConfig.data);

        pool.syncRatesState(asset);

        emit Cod3xReserveFactorChanged(asset, reserveFactor);
    }

    /**
     * @dev Sets the deposit cap for a reserve.
     * @param asset The address of the underlying asset.
     * @param depositCap The new deposit cap.
     * @param pool The MiniPool instance to update.
     */
    function setDepositCap(address asset, uint256 depositCap, IMiniPool pool)
        external
        onlyMainPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setDepositCap(depositCap);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveDepositCapChanged(asset, depositCap);
    }

    /**
     * @dev Internal function to initialize a single reserve.
     * @param pool The MiniPool instance.
     * @param input The reserve initialization parameters.
     */
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

        emit ReserveInitialized(
            input.underlyingAsset, aTokenID, debtTokenID, input.interestRateStrategyAddress
        );
    }

    /*___ Only emergency admin ___*/

    /**
     * @dev Pauses or unpauses all protocol actions including aToken transfers.
     * @param val True to pause, false to unpause.
     * @param pool The MiniPool instance to update.
     */
    function setPoolPause(bool val, IMiniPool pool) external onlyEmergencyAdmin {
        pool.setPause(val);
    }

    /*___ Only pool admin ___*/

    /**
     * @dev Enables borrowing on a reserve.
     * @param asset The address of the underlying asset.
     * @param pool The MiniPool instance to update.
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
     * @dev Disables borrowing on a reserve.
     * @param asset The address of the underlying asset.
     * @param pool The MiniPool instance to update.
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
     * @dev Configures the collateralization parameters for a reserve.
     * @param asset The address of the underlying asset.
     * @param ltv The loan to value ratio (in basis points).
     * @param liquidationThreshold The liquidation threshold (in basis points).
     * @param liquidationBonus The liquidation bonus (in basis points).
     * @param pool The MiniPool instance to update.
     */
    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        IMiniPool pool
    ) external onlyPoolAdmin(address(pool)) {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        // Validation of the parameters: The LTV can
        // Only be lower or equal than the liquidation threshold
        // (Otherwise a loan against the asset would cause instantaneous liquidation).
        require(ltv <= liquidationThreshold, Errors.VL_INVALID_CONFIGURATION);

        if (liquidationThreshold != 0) {
            // Liquidation bonus must be bigger than 100.00%, otherwise the liquidator would receive less
            // Collateral than needed to cover the debt.
            require(
                liquidationBonus > PercentageMath.PERCENTAGE_FACTOR, Errors.VL_INVALID_CONFIGURATION
            );

            // If threshold * bonus is less than PERCENTAGE_FACTOR, it's guaranteed that at the moment
            // A loan is taken there is enough collateral available to cover the liquidation bonus.
            require(
                liquidationThreshold.percentMul(liquidationBonus)
                    <= PercentageMath.PERCENTAGE_FACTOR,
                Errors.VL_INVALID_CONFIGURATION
            );
        } else {
            require(liquidationBonus == 0, Errors.VL_INVALID_CONFIGURATION);
            // If the liquidation threshold is being set to 0,
            // The reserve is being disabled as collateral. To do so,
            // We need to ensure no liquidity is deposited.
            _checkNoLiquidity(asset, pool);
        }

        currentConfig.setLtv(ltv);
        currentConfig.setLiquidationThreshold(liquidationThreshold);
        currentConfig.setLiquidationBonus(liquidationBonus);

        pool.setConfiguration(asset, currentConfig.data);

        emit CollateralConfigurationChanged(asset, ltv, liquidationThreshold, liquidationBonus);
    }

    /**
     * @dev Activates a reserve.
     * @param asset The address of the underlying asset.
     * @param pool The MiniPool instance to update.
     */
    function activateReserve(address asset, IMiniPool pool) external onlyPoolAdmin(address(pool)) {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setActive(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveActivated(asset);
    }

    /**
     * @dev Deactivates a reserve.
     * @param asset The address of the underlying asset.
     * @param pool The MiniPool instance to update.
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
     * @dev Freezes a reserve. A frozen reserve doesn't allow new deposits or borrows.
     * @param asset The address of the underlying asset.
     * @param pool The MiniPool instance to update.
     */
    function freezeReserve(address asset, IMiniPool pool) external onlyPoolAdmin(address(pool)) {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setFrozen(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveFrozen(asset);
    }

    /**
     * @dev Unfreezes a reserve.
     * @param asset The address of the underlying asset.
     * @param pool The MiniPool instance to update.
     */
    function unfreezeReserve(address asset, IMiniPool pool) external onlyPoolAdmin(address(pool)) {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setFrozen(false);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveUnfrozen(asset);
    }

    /**
     * @dev Enables flash loans for a reserve.
     * @param asset The address of the underlying asset.
     * @param pool The MiniPool instance to update.
     */
    function enableFlashloan(address asset, IMiniPool pool) external onlyPoolAdmin(address(pool)) {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setFlashLoanEnabled(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit EnableFlashloan(asset);
    }

    /**
     * @dev Disables flash loans for a reserve.
     * @param asset The address of the underlying asset.
     * @param pool The MiniPool instance to update.
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
     * @dev Sets the pool admin for a MiniPool.
     * @param admin The address of the new pool admin.
     * @param pool The MiniPool instance to update.
     */
    function setPoolAdmin(address admin, IMiniPool pool) public onlyPoolAdmin(address(pool)) {
        uint256 id = addressesProvider.getMiniPoolId(address(pool));
        addressesProvider.setPoolAdmin(id, admin);
    }

    /**
     * @dev Sets the MiniPool owner treasury address.
     * @param treasury The address of the new treasury.
     * @param pool The MiniPool instance to update.
     */
    function setMinipoolOwnerTreasuryToMiniPool(address treasury, IMiniPool pool)
        public
        onlyPoolAdmin(address(pool))
    {
        uint256 id = addressesProvider.getMiniPoolId(address(pool));
        addressesProvider.setMinipoolOwnerTreasuryToMiniPool(id, treasury);
    }

    /**
     * @dev Updates the MiniPool owner reserve factor.
     * @param asset The address of the underlying asset.
     * @param reserveFactor The new reserve factor.
     * @param pool The MiniPool instance to update.
     */
    function setMinipoolOwnerReserveFactor(address asset, uint256 reserveFactor, IMiniPool pool)
        external
        onlyPoolAdmin(address(pool))
    {
        pool.syncIndexesState(asset);

        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setMinipoolOwnerReserveFactor(reserveFactor);

        pool.setConfiguration(asset, currentConfig.data);

        pool.syncRatesState(asset);

        emit MinipoolOwnerReserveFactorChanged(asset, reserveFactor);
    }

    /**
     * @dev Checks if a reserve has zero liquidity.
     * @param asset The address of the underlying asset.
     * @param pool The MiniPool instance to check.
     */
    function _checkNoLiquidity(address asset, IMiniPool pool) internal view {
        DataTypes.MiniPoolReserveData memory reserveData = pool.getReserveData(asset);

        IAERC6909 aToken6909 = IAERC6909(reserveData.aErc6909);
        (uint256 aTokenID, uint256 debtTokenID,) = aToken6909.getIdForUnderlying(asset);

        bool hasNoShares = aToken6909.scaledTotalSupply(aTokenID) == 0
            && aToken6909.scaledTotalSupply(debtTokenID) == 0;

        require(
            hasNoShares && reserveData.currentLiquidityRate == 0, Errors.VL_RESERVE_LIQUIDITY_NOT_0
        );
    }
}
