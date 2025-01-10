// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {Address} from "../../../../contracts/dependencies/openzeppelin/contracts/Address.sol";
import {ILendingPoolAddressesProvider} from
    "../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IAToken} from "../../../../contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "../../../../contracts/interfaces/IVariableDebtToken.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {VersionedInitializable} from
    "../../../../contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {Helpers} from "../../../../contracts/protocol/libraries/helpers/Helpers.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveLogic} from "../../../../contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
import {GenericLogic} from "../../../../contracts/protocol/core/lendingpool/logic/GenericLogic.sol";
import {ValidationLogic} from
    "../../../../contracts/protocol/core/lendingpool/logic/ValidationLogic.sol";
import {ReserveConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {LendingPoolStorage} from "./LendingPoolStorage.sol";
import {DepositLogic} from "../../../../contracts/protocol/core/lendingpool/logic/DepositLogic.sol";
import {WithdrawLogic} from
    "../../../../contracts/protocol/core/lendingpool/logic/WithdrawLogic.sol";
import {BorrowLogic} from "../../../../contracts/protocol/core/lendingpool/logic/BorrowLogic.sol";
import {FlashLoanLogic} from
    "../../../../contracts/protocol/core/lendingpool/logic/FlashLoanLogic.sol";
import {LiquidationLogic} from
    "../../../../contracts/protocol/core/lendingpool/logic/LiquidationLogic.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";

/**
 * @title LendingPool contract
 * @dev Main point of interaction with an Cod3x Lend protocol's market.
 *
 * - Minipools can borrow from the main lending pool on aTokens from the main lending pool.
 * - Admin can activate rehypothecation on reserves.
 * - Users can: Deposit, Withdraw, Borrow, Repay, Enable/disable their deposits as collateral, Liquidate positions, Execute Flash Loans
 * - To be covered by a proxy contract, owned by the LendingPoolAddressesProvider of the specific market
 * - All admin functions are callable by the LendingPoolConfigurator contract defined also in the
 *   LendingPoolAddressesProvider
 * @author Cod3x
 */
contract LendingPool is VersionedInitializable, ILendingPool, LendingPoolStorage {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 public constant LENDINGPOOL_REVISION = 0x1;

    /**
     * @dev Modifier to check if the lending pool is not paused.
     * Reverts if the pool is paused.
     */
    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    /**
     * @dev Modifier to check if caller is the lending pool configurator.
     * Reverts if caller is not the configurator.
     */
    modifier onlyLendingPoolConfigurator() {
        _onlyLendingPoolConfigurator();
        _;
    }

    /**
     * @dev Internal function to check if lending pool is not paused.
     * Reverts with `LP_IS_PAUSED` if `_paused` is true.
     */
    function _whenNotPaused() internal view {
        require(!_paused, Errors.LP_IS_PAUSED);
    }

    /**
     * @dev Internal function to validate caller is lending pool configurator.
     * Reverts with `LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR` if caller is not the configurator.
     */
    function _onlyLendingPoolConfigurator() internal view {
        require(
            _addressesProvider.getLendingPoolConfigurator() == msg.sender,
            Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
    }

    /// @dev Returns the revision number of the contract.
    function getRevision() internal pure override returns (uint256) {
        return LENDINGPOOL_REVISION;
    }

    /**
     * @dev Function is invoked by the proxy contract when the LendingPool contract is added to the
     * LendingPoolAddressesProvider of the market.
     * - Caching the address of the LendingPoolAddressesProvider in order to reduce gas consumption
     *   on subsequent operations.
     * @param provider The address of the LendingPoolAddressesProvider
     */
    function initialize(ILendingPoolAddressesProvider provider) public initializer {
        _addressesProvider = provider;
        _updateFlashLoanFee(9);
        _maxNumberOfReserves = 128;
    }

    /**
     * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User deposits 100 USDC and gets in return 100 aUSDC.
     * @param asset The address of the underlying asset to deposit.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param amount The amount to be deposited.
     * @param onBehalfOf The address that will receive the aTokens, same as `msg.sender` if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet.
     */
    function deposit(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
    {
        DepositLogic.deposit(
            DepositLogic.DepositParams(asset, reserveType, amount, onBehalfOf),
            _reserves,
            _usersConfig,
            _addressesProvider
        );
    }

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned.
     * - E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC.
     * @param asset The address of the underlying asset to withdraw.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param amount The underlying amount to be withdrawn.
     *   - Send the value `type(uint256).max` in order to withdraw the whole aToken balance.
     * @param to Address that will receive the underlying, same as `msg.sender` if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet.
     * @return The final amount withdrawn.
     */
    function withdraw(address asset, bool reserveType, uint256 amount, address to)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        return WithdrawLogic.withdraw(
            WithdrawLogic.withdrawParams(asset, reserveType, amount, to, _reservesCount),
            _reserves,
            _usersConfig,
            _reservesList,
            _addressesProvider
        );
    }

    /**
     * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
     * already deposited enough collateral, or he was given enough allowance by a credit delegator on the VariableDebtToken
     * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
     *   and 100 variable debt tokens
     * @param asset The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param onBehalfOf Address of the user who will receive the debt. Should be the address of the borrower itself
     * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
     * if he has been given credit delegation allowance
     */
    function borrow(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
    {
        DataTypes.ReserveData storage reserve = _reserves[asset][reserveType];

        BorrowLogic.executeBorrow(
            BorrowLogic.ExecuteBorrowParams(
                asset,
                reserveType,
                msg.sender,
                onBehalfOf,
                amount,
                reserve.aTokenAddress,
                true,
                _addressesProvider,
                _reservesCount
            ),
            _reserves,
            _reservesList,
            _usersConfig
        );
    }

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned.
     * @dev User repays their debt by burning the corresponding debt tokens.
     * For example: User repays 100 USDC, burning 100 variable debt tokens of the `onBehalfOf` address.
     * @param asset The address of the borrowed underlying asset previously borrowed.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param amount The amount to repay.
     * Send the value `type(uint256).max` in order to repay the whole debt for `asset`.
     * @param onBehalfOf Address of the user who will get his debt reduced/removed.
     * Should be the address of the user calling the function if he wants to reduce/remove his own debt,
     * or the address of any other borrower whose debt should be removed.
     * @return The final amount repaid.
     */
    function repay(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        return BorrowLogic.repay(
            BorrowLogic.RepayParams(asset, reserveType, amount, onBehalfOf, _addressesProvider),
            _reserves,
            _usersConfig
        );
    }

    /**
     * @notice Repays a borrowed amount using aTokens.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param amount The amount to repay.
     * @return The final amount repaid.
     */
    function repayWithATokens(address asset, bool reserveType, uint256 amount)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        return BorrowLogic.repayWithAtokens(
            BorrowLogic.RepayParams(asset, reserveType, amount, msg.sender, _addressesProvider),
            _reserves,
            _usersConfig
        );
    }

    /**
     * @notice Allows depositors to enable/disable a specific deposited asset as collateral.
     * @dev Updates the user's configuration to use or stop using a deposit as collateral.
     * @param asset The address of the underlying asset deposited.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param useAsCollateral `true` if the user wants to use the deposit as collateral, `false` otherwise.
     */
    function setUserUseReserveAsCollateral(address asset, bool reserveType, bool useAsCollateral)
        external
        override
        whenNotPaused
    {
        DataTypes.ReserveData storage reserve = _reserves[asset][reserveType];

        ValidationLogic.validateSetUseReserveAsCollateral(
            reserve,
            asset,
            reserveType,
            useAsCollateral,
            _reserves,
            _usersConfig[msg.sender],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        _usersConfig[msg.sender].setUsingAsCollateral(reserve.id, useAsCollateral);

        if (useAsCollateral) {
            emit ReserveUsedAsCollateralEnabled(asset, msg.sender);
        } else {
            emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
        }
    }

    /**
     * @dev Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param collateralAssetType The reserve type of the underlying used as collateral
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param debtAssetType The reserve type of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     */
    function liquidationCall(
        address collateralAsset,
        bool collateralAssetType,
        address debtAsset,
        bool debtAssetType,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external override whenNotPaused {
        require(!_isMiniPool(user), Errors.VL_MINIPOOL_CANNOT_BE_LIQUIDATED);

        LiquidationLogic.liquidationCall(
            _reserves,
            _usersConfig,
            _reservesList,
            LiquidationLogic.liquidationCallParams(
                address(_addressesProvider),
                _reservesCount,
                collateralAsset,
                collateralAssetType,
                debtAsset,
                debtAssetType,
                user,
                debtToCover,
                receiveAToken
            )
        );
    }

    /**
     * @notice Executes a flash loan operation.
     * @dev Allows smart contracts to access the liquidity of the pool within one transaction,
     * as long as the amount taken plus a fee is returned.
     * @param flashLoanParams A struct containing:
     *   - `receiverAddress`: The address of the contract receiving the funds.
     *   - `onBehalfOf`: The address that will receive the debt if the flash loan is not returned.
     *   - `assets`: Array of asset addresses to flash loan.
     *   - `reserveTypes`: Array indicating if each asset is boosted by a vault.
     * @param amounts Array of amounts to flash loan for each asset.
     * @param modes Array indicating the borrow mode for each asset:
     *   - 0: Don't open any debt, just revert if funds can't be transferred from the receiver.
     *   - != 0: Open debt at variable rate for the flash borrowed amount.
     * @param params Variadic packed params to pass to the receiver as extra information.
     * IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.
     */
    function flashLoan(
        FlashLoanParams memory flashLoanParams,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        bytes calldata params
    ) external override whenNotPaused {
        FlashLoanLogic.flashLoan(
            FlashLoanLogic.FlashLoanParams({
                receiverAddress: flashLoanParams.receiverAddress,
                assets: flashLoanParams.assets,
                reserveTypes: flashLoanParams.reserveTypes,
                onBehalfOf: flashLoanParams.onBehalfOf,
                addressesProvider: _addressesProvider,
                reservesCount: _reservesCount,
                flashLoanPremiumTotal: _flashLoanPremiumTotal,
                amounts: amounts,
                modes: modes,
                params: params
            }),
            _reservesList,
            _usersConfig,
            _reserves
        );
    }

    /**
     * @notice Allows minipools to borrow unbacked amounts of reserve assets.
     * @dev This function is restricted to minipools only.
     * @param asset The address of the underlying asset to borrow.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param amount The amount to borrow.
     * @param aTokenAddress The address of the aToken.
     */
    function miniPoolBorrow(address asset, bool reserveType, uint256 amount, address aTokenAddress)
        external
        override
        whenNotPaused
    {
        require(_isMiniPool(msg.sender), Errors.LP_CALLER_NOT_MINIPOOL);

        BorrowLogic.executeMiniPoolBorrow(
            BorrowLogic.ExecuteMiniPoolBorrowParams(
                asset,
                reserveType,
                amount,
                msg.sender,
                aTokenAddress,
                _addressesProvider,
                _reservesCount
            ),
            _reserves
        );
    }

    /**
     * @notice Checks if a user is a minipool.
     * @param user The address of the user.
     * @return True if the user is a minipool, false otherwise.
     */
    function _isMiniPool(address user) internal view returns (bool) {
        address minipoolAddressProvider = _addressesProvider.getMiniPoolAddressesProvider();
        if (minipoolAddressProvider == address(0)) return false;
        return IMiniPoolAddressesProvider(minipoolAddressProvider).getMiniPoolToAERC6909(user)
            != address(0);
    }

    /**
     * @notice Returns the state and configuration of a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @return The state of the reserve.
     */
    function getReserveData(address asset, bool reserveType)
        external
        view
        override
        returns (DataTypes.ReserveData memory)
    {
        return _reserves[asset][reserveType];
    }

    /**
     * @notice Returns the user account data across all reserves.
     * @param user The address of the user.
     * @return totalCollateralETH The total collateral in ETH of the user.
     * @return totalDebtETH The total debt in ETH of the user.
     * @return availableBorrowsETH The borrowing power left of the user.
     * @return currentLiquidationThreshold The liquidation threshold of the user.
     * @return ltv The loan to value of the user.
     * @return healthFactor The current health factor of the user.
     */
    function getUserAccountData(address user)
        external
        view
        override
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        (totalCollateralETH, totalDebtETH, ltv, currentLiquidationThreshold, healthFactor) =
        GenericLogic.calculateUserAccountData(
            user,
            _reserves,
            _usersConfig[user],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        availableBorrowsETH =
            GenericLogic.calculateAvailableBorrowsETH(totalCollateralETH, totalDebtETH, ltv);
    }

    /**
     * @notice Returns the configuration of a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @return The configuration of the reserve.
     */
    function getConfiguration(address asset, bool reserveType)
        external
        view
        override
        returns (DataTypes.ReserveConfigurationMap memory)
    {
        return _reserves[asset][reserveType].configuration;
    }

    /**
     * @notice Returns the configuration of a user across all reserves.
     * @param user The user address.
     * @return The configuration of the user.
     */
    function getUserConfiguration(address user)
        external
        view
        override
        returns (DataTypes.UserConfigurationMap memory)
    {
        return _usersConfig[user];
    }

    /**
     * @notice Returns the normalized income per unit of asset.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @return The reserve's normalized income.
     */
    function getReserveNormalizedIncome(address asset, bool reserveType)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _reserves[asset][reserveType].getNormalizedIncome();
    }

    /**
     * @notice Returns the normalized variable debt per unit of asset.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @return The reserve normalized variable debt.
     */
    function getReserveNormalizedVariableDebt(address asset, bool reserveType)
        external
        view
        override
        returns (uint256)
    {
        return _reserves[asset][reserveType].getNormalizedDebt();
    }

    /**
     * @notice Returns if the LendingPool is paused.
     * @return True if the pool is paused, false otherwise.
     */
    function paused() external view override returns (bool) {
        return _paused;
    }

    /**
     * @notice Returns the list of initialized reserves.
     * @return _activeReserves Array of reserve addresses.
     * @return _activeReservesTypes Array indicating if each reserve is boosted by a vault.
     */
    function getReservesList() external view override returns (address[] memory, bool[] memory) {
        address[] memory _activeReserves = new address[](_reservesCount);
        bool[] memory _activeReservesTypes = new bool[](_reservesCount);

        for (uint256 i = 0; i < _reservesCount; i++) {
            _activeReserves[i] = _reservesList[i].asset;
            _activeReservesTypes[i] = _reservesList[i].reserveType;
        }
        return (_activeReserves, _activeReservesTypes);
    }

    /**
     * @notice Returns the total number of initialized reserves.
     * @return The number of reserves.
     */
    function getReservesCount() external view override returns (uint256) {
        return _reservesCount;
    }

    /**
     * @notice Returns the cached LendingPoolAddressesProvider connected to this contract.
     * @return The addresses provider instance.
     */
    function getAddressesProvider()
        external
        view
        override
        returns (ILendingPoolAddressesProvider)
    {
        return _addressesProvider;
    }

    /**
     * @notice Returns the fee on flash loans.
     * @return The total flash loan premium percentage.
     */
    function FLASHLOAN_PREMIUM_TOTAL() public view returns (uint128) {
        return _flashLoanPremiumTotal;
    }

    /**
     * @notice Returns the maximum number of reserves supported to be listed in this LendingPool.
     * @return The maximum number of reserves allowed.
     */
    function MAX_NUMBER_RESERVES() public view returns (uint256) {
        return _maxNumberOfReserves;
    }

    /**
     * @notice Validates and finalizes an aToken transfer.
     * @dev Only callable by the overlying aToken of the `asset`.
     * @param asset The address of the underlying asset of the aToken.
     * @param reserveType A boolean indicating whether the asset is boosted by a vault.
     * @param from The user from which the aTokens are transferred.
     * @param to The user receiving the aTokens.
     * @param amount The amount being transferred/withdrawn.
     * @param balanceFromBefore The aToken balance of the `from` user before the transfer.
     * @param balanceToBefore The aToken balance of the `to` user before the transfer.
     */
    function finalizeTransfer(
        address asset,
        bool reserveType,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external override whenNotPaused {
        WithdrawLogic.finalizeTransfer(
            WithdrawLogic.finalizeTransferParams(
                asset,
                reserveType,
                from,
                to,
                amount,
                balanceFromBefore,
                balanceToBefore,
                _reservesCount
            ),
            _reserves,
            _usersConfig,
            _reservesList,
            _addressesProvider
        );
    }

    /**
     * @notice Initializes a reserve, activating it, assigning an aToken and debt tokens and an interest rate strategy.
     * @dev Only callable by the LendingPoolConfigurator contract.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param aTokenAddress The address of the aToken that will be assigned to the reserve.
     * @param variableDebtAddress The address of the VariableDebtToken that will be assigned to the reserve.
     * @param interestRateStrategyAddress The address of the interest rate strategy contract.
     */
    function initReserve(
        address asset,
        bool reserveType,
        address aTokenAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external override onlyLendingPoolConfigurator {
        require(Address.isContract(asset), Errors.LP_NOT_CONTRACT);
        _reserves[asset][reserveType].init(
            aTokenAddress, variableDebtAddress, interestRateStrategyAddress
        );
        _addReserveToList(asset, reserveType);
    }

    /**
     * @notice Updates the address of the interest rate strategy contract.
     * @dev Only callable by the LendingPoolConfigurator contract.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param rateStrategyAddress The address of the interest rate strategy contract.
     */
    function setReserveInterestRateStrategyAddress(
        address asset,
        bool reserveType,
        address rateStrategyAddress
    ) external override onlyLendingPoolConfigurator {
        _reserves[asset][reserveType].interestRateStrategyAddress = rateStrategyAddress;
    }

    /**
     * @notice Sets the configuration bitmap of the reserve as a whole.
     * @dev Only callable by the LendingPoolConfigurator contract.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param configuration The new configuration bitmap.
     */
    function setConfiguration(address asset, bool reserveType, uint256 configuration)
        external
        override
        onlyLendingPoolConfigurator
    {
        _reserves[asset][reserveType].configuration.data = configuration;
    }

    /**
     * @notice Sets the pause state of the pool.
     * @dev Only callable by the LendingPoolConfigurator contract.
     * @param val `true` to pause the reserve, `false` to un-pause it.
     */
    function setPause(bool val) external override onlyLendingPoolConfigurator {
        require(val != _paused, Errors.VL_INVALID_INPUT);

        _paused = val;
        if (_paused) {
            emit Paused();
        } else {
            emit Unpaused();
        }
    }

    /**
     * @notice Sets the farming percentage for a specific aToken.
     * @param aTokenAddress The address of the aToken.
     * @param farmingPct The new farming percentage.
     */
    function setFarmingPct(address aTokenAddress, uint256 farmingPct)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(aTokenAddress).setFarmingPct(farmingPct);
    }

    /**
     * @notice Sets the claiming threshold for a specific aToken.
     * @param aTokenAddress The address of the aToken.
     * @param claimingThreshold The new claiming threshold to be set.
     */
    function setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(aTokenAddress).setClaimingThreshold(claimingThreshold);
    }

    /**
     * @notice Sets the allowable drift for the farming percentage.
     * @param aTokenAddress The address of the aToken.
     * @param farmingPctDrift The allowable drift for the farming percentage.
     */
    function setFarmingPctDrift(address aTokenAddress, uint256 farmingPctDrift)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(aTokenAddress).setFarmingPctDrift(farmingPctDrift);
    }

    /**
     * @notice Sets the profit handler for a specific aToken.
     * @param aTokenAddress The address of the aToken.
     * @param profitHandler The address of the profit handler.
     */
    function setProfitHandler(address aTokenAddress, address profitHandler)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(aTokenAddress).setProfitHandler(profitHandler);
    }

    /**
     * @notice Sets the rehypothecation vault for a specific aToken.
     * @param aTokenAddress The address of the aToken.
     * @param vault The address of the vault to be set.
     */
    function setVault(address aTokenAddress, address vault)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(aTokenAddress).setVault(vault);
    }

    /**
     * @notice Rebalances the assets of a specific aToken rehypothecation vault.
     * @param aTokenAddress The address of the aToken to be rebalanced.
     */
    function rebalance(address aTokenAddress) external override onlyLendingPoolConfigurator {
        IAToken(aTokenAddress).rebalance();
    }

    /**
     * @notice Returns the total assets managed by a specific aToken/reserve.
     * @param aTokenAddress The address of the aToken.
     * @return The total amount of assets managed by the aToken.
     */
    function getTotalManagedAssets(address aTokenAddress)
        external
        view
        override
        returns (uint256)
    {
        return IAToken(aTokenAddress).getTotalManagedAssets();
    }

    /**
     * @dev Adds a new reserve to the list of reserves.
     * @param asset The address of the underlying asset to add.
     * @param reserveType Whether the reserve is boosted by a vault.
     */
    function _addReserveToList(address asset, bool reserveType) internal {
        uint256 reservesCount = _reservesCount;

        require(reservesCount < _maxNumberOfReserves, Errors.LP_NO_MORE_RESERVES_ALLOWED);

        bool reserveAlreadyAdded = _reserves[asset][reserveType].id != 0
            || (_reservesList[0].asset == asset && _reservesList[0].reserveType == reserveType);

        if (!reserveAlreadyAdded) {
            _reserves[asset][reserveType].id = uint8(reservesCount);
            _reservesList[reservesCount] = DataTypes.ReserveReference(asset, reserveType);

            _reservesCount = reservesCount + 1;
        }
    }

    /**
     * @notice Updates the flash loan fee.
     * @param flashLoanPremiumTotal The new total premium to be applied on flash loans.
     */
    function updateFlashLoanFee(uint128 flashLoanPremiumTotal)
        external
        override
        onlyLendingPoolConfigurator
    {
        _updateFlashLoanFee(flashLoanPremiumTotal);
    }

    /**
     * @dev Internal function to update the flash loan fee.
     * @param flashLoanPremiumTotal The new total premium to be applied.
     */
    function _updateFlashLoanFee(uint128 flashLoanPremiumTotal) internal {
        _flashLoanPremiumTotal = flashLoanPremiumTotal;

        emit FlashLoanFeeUpdated(flashLoanPremiumTotal);
    }

    /**
     * @notice Sets the rewarder contract for a specific reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param rewarder The address of the rewarder contract to be set.
     */
    function setRewarderForReserve(address asset, bool reserveType, address rewarder)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(_reserves[asset][reserveType].aTokenAddress).setIncentivesController(rewarder);
        IVariableDebtToken(_reserves[asset][reserveType].variableDebtTokenAddress)
            .setIncentivesController(rewarder);
    }

    /**
     * @notice Sets the treasury for a specific reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param treasury The address of the treasury to be set.
     */
    function setTreasury(address asset, bool reserveType, address treasury)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(_reserves[asset][reserveType].aTokenAddress).setTreasury(treasury);
    }
}
