// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {Address} from "../../../../contracts/dependencies/openzeppelin/contracts/Address.sol";
import {IAERC6909} from "../../../../contracts/interfaces/IAERC6909.sol";
import {IERC20Detailed} from
    "../../../../contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {SafeERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IFlowLimiter} from "../../../../contracts/interfaces/base/IFlowLimiter.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {VersionedInitializable} from
    "../../../../contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {Helpers} from "../../../../contracts/protocol/libraries/helpers/Helpers.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {MiniPoolReserveLogic} from "./logic/MiniPoolReserveLogic.sol";
import {MiniPoolGenericLogic} from "./logic/MiniPoolGenericLogic.sol";
import {MiniPoolValidationLogic} from "./logic/MiniPoolValidationLogic.sol";
import {ReserveConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {MiniPoolStorage} from "./MiniPoolStorage.sol";
import {IMiniPool} from "../../../../contracts/interfaces/IMiniPool.sol";
import {ATokenNonRebasing} from
    "../../../../contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";
import {MiniPoolDepositLogic} from "./logic/MiniPoolDepositLogic.sol";
import {MiniPoolWithdrawLogic} from "./logic/MiniPoolWithdrawLogic.sol";
import {MiniPoolBorrowLogic} from "./logic/MiniPoolBorrowLogic.sol";
import {MiniPoolFlashLoanLogic} from "./logic/MiniPoolFlashLoanLogic.sol";
import {MiniPoolLiquidationLogic} from "./logic/MiniPoolLiquidationLogic.sol";
import {IMiniPoolRewarder} from "../../../../contracts/interfaces/IMiniPoolRewarder.sol";
import {IMiniPoolAddressProviderUpdatable} from
    "../../../../contracts/interfaces/IMiniPoolAddressProviderUpdatable.sol";

/**
 * @title MiniPool contract
 * @dev A highly correlated sub market that can borrow from the main lending pool and charge double
 * interest rates on those loans.
 * Minipool can 'flow borrow' from the main lending pool on aTokens from the main lending pool,
 * which means that the a Minipool can borrow from the main lending pool and use it as collateral
 * for its own borrowing power. This power is set by the admin through the FlowLimiter.
 *
 * - Users can: Deposit, Withdraw, Borrow, Repay, Enable/disable their deposits as collateral, Liquidate positions, Execute Flash Loans
 * - To be covered by a proxy contract, owned by the MiniPoolAddressesProvider of the specific market.
 * - All admin functions are callable by the MiniPoolConfigurator contract defined also in the
 *   MiniPoolAddressesProvider.
 * @author Cod3x
 */
contract MiniPool is
    VersionedInitializable,
    IMiniPool,
    MiniPoolStorage,
    IMiniPoolAddressProviderUpdatable
{
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20Detailed;
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /**
     * @dev The revision number of the MiniPool contract implementation.
     * Used for tracking contract versions in the upgradeable proxy pattern.
     */
    uint256 public constant MINIPOOL_REVISION = 0x1;

    /**
     * @dev Safety margin for handling rounding errors during minipool flow borrow.
     * This variable ensures that we can do at least 100_000 transactions on minipool in the current block.
     * The value represents the minimum amount of wei that should remain in the pool.
     */
    uint256 public constant ERROR_REMAINDER_MARGIN = 100_000;

    constructor() {
        _blockInitializing();
    }

    /**
     * @dev Modifier to verify the protocol is not paused.
     * Reverts if the protocol is in a paused state.
     */
    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    /**
     * @dev Modifier to verify caller is the MiniPool configurator.
     * Reverts if caller is not authorized.
     */
    modifier onlyMiniPoolConfigurator() {
        _onlyMiniPoolConfigurator();
        _;
    }

    /**
     * @dev Modifier to verify caller is the LendingPool.
     * Reverts if caller is not authorized.
     */
    modifier onlyLendingPool() {
        require(
            _addressesProvider.getLendingPool() == msg.sender,
            Errors.VL_ACCESS_RESTRICTED_TO_LENDING_POOL
        );
        _;
    }

    /**
     * @dev Internal function to check if protocol is paused.
     * Reverts with `LP_IS_PAUSED` if `_paused` is true.
     */
    function _whenNotPaused() internal view {
        require(!_paused, Errors.LP_IS_PAUSED);
    }

    /**
     * @dev Internal function to verify caller is the MiniPool configurator.
     * Reverts with `LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR` if `msg.sender` is not the configurator.
     */
    function _onlyMiniPoolConfigurator() internal view {
        require(
            _addressesProvider.getMiniPoolConfigurator() == msg.sender,
            Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
    }

    function getRevision() internal pure override returns (uint256) {
        return MINIPOOL_REVISION;
    }

    /**
     * @dev Function is invoked by the proxy contract when the LendingPool contract is added to the
     * LendingPoolAddressesProvider of the market.
     * - Caching the address of the LendingPoolAddressesProvider in order to reduce gas consumption
     *   on subsequent operations.
     * @param provider The address of the LendingPoolAddressesProvider.
     */
    function initialize(address provider, uint256 minipoolID) public initializer {
        _addressesProvider = IMiniPoolAddressesProvider(provider);
        _minipoolId = minipoolID;
        _updateFlashLoanFee(9);
        _maxNumberOfReserves = 128;
        _minDebtThreshold = 1e3;
    }

    /**
     * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User deposits 100 USDC and gets in return 100 aUSDC.
     * @param asset The address of the underlying asset to deposit.
     * @param wrap Convert the underlying in AToken from the lendingpool.
     * @param amount The amount to be deposited.
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet.
     */
    function deposit(address asset, bool wrap, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
    {
        MiniPoolDepositLogic.deposit(
            MiniPoolDepositLogic.DepositParams(asset, amount, onBehalfOf),
            wrap,
            _reserves,
            _usersConfig,
            _addressesProvider
        );
        _repayLendingPool(asset);
    }

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC.
     * @param asset The address of the underlying asset to withdraw.
     * @param unwrap If true, and `asset` is an aToken, `to` will directly receive the underlying.
     * @param amount The underlying amount to be withdrawn.
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance.
     * @param to Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet.
     * @return The final amount withdrawn.
     */
    function withdraw(address asset, bool unwrap, uint256 amount, address to)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        return MiniPoolWithdrawLogic.withdraw(
            MiniPoolWithdrawLogic.withdrawParams(asset, amount, to, _reservesCount),
            unwrap,
            _reserves,
            _usersConfig,
            _reservesList,
            _addressesProvider
        );
    }

    struct borrowVarsLocalVars {
        uint256 availableLiquidity;
        uint256 amountReceived;
        address onBehalfOf;
        address aErc6909;
        address LendingPool;
    }
    /**
     * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
     * already deposited enough collateral, or he was given enough allowance by a credit delegator on the VariableDebtToken
     * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
     *   and 100 variable debt tokens.
     * @param asset The address of the underlying asset to borrow.
     * @param unwrap If true, and `asset` is an aToken, `to` will directly receive the underlying.
     * @param amount The amount to be borrowed.
     * @param onBehalfOf Address of the user who will receive the debt. Should be the address of the borrower itself
     * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
     * if he has been given credit delegation allowance.
     */

    function borrow(address asset, bool unwrap, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
    {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[asset];
        borrowVarsLocalVars memory vars;
        vars.aErc6909 = reserve.aErc6909;
        require(vars.aErc6909 != address(0), Errors.RL_RESERVE_NOT_INITIALIZED);
        vars.availableLiquidity = IERC20Detailed(asset).balanceOf(vars.aErc6909);
        if (
            amount > vars.availableLiquidity
                && IAERC6909(reserve.aErc6909).isTranche(reserve.aTokenID)
        ) {
            address underlying = ATokenNonRebasing(asset).UNDERLYING_ASSET_ADDRESS();
            vars.LendingPool = _addressesProvider.getLendingPool();
            ILendingPool(vars.LendingPool).miniPoolBorrow(
                underlying,
                true,
                ATokenNonRebasing(asset).convertToAssets(amount - vars.availableLiquidity), // amount - availableLiquidity converted to asset
                ATokenNonRebasing(asset).ATOKEN_ADDRESS()
            );

            vars.amountReceived = IERC20Detailed(underlying).balanceOf(address(this));

            IERC20Detailed(underlying).forceApprove(vars.LendingPool, vars.amountReceived);
            ILendingPool(vars.LendingPool).deposit(
                underlying, true, vars.amountReceived, address(this)
            );

            vars.amountReceived = IERC20Detailed(asset).balanceOf(address(this));
            assert(vars.amountReceived >= amount - vars.availableLiquidity);

            MiniPoolDepositLogic.internalDeposit(
                MiniPoolDepositLogic.DepositParams(asset, vars.amountReceived, address(this)),
                _reserves,
                _usersConfig,
                _addressesProvider
            );
        }
        MiniPoolBorrowLogic.executeBorrow(
            MiniPoolBorrowLogic.ExecuteBorrowParams(
                asset,
                msg.sender,
                onBehalfOf,
                amount,
                reserve.aErc6909,
                0,
                0,
                0,
                true,
                _addressesProvider,
                _reservesCount,
                minDebtThreshold(IERC20Detailed(asset).decimals())
            ),
            unwrap,
            _reserves,
            _reservesList,
            _usersConfig
        );
    }

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned.
     * - E.g. User repays 100 USDC, burning 100 variable debt tokens of the `onBehalfOf` address.
     * @param asset The address of the borrowed underlying asset previously borrowed.
     * @param wrap Convert the underlying in AToken from the lendingpool.
     * @param amount The amount to repay.
     * - Send the value type(uint256).max in order to repay the whole debt for `asset`.
     * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
     * user calling the function if he wants to reduce/remove his own debt, or the address of any other
     * other borrower whose debt should be removed.
     * @return The final amount repaid.
     */
    function repay(address asset, bool wrap, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        uint256 repayAmount = MiniPoolBorrowLogic.repay(
            MiniPoolBorrowLogic.RepayParams(
                asset,
                amount,
                onBehalfOf,
                _addressesProvider,
                minDebtThreshold(IERC20Detailed(asset).decimals())
            ),
            wrap,
            _reserves,
            _usersConfig
        );

        _repayLendingPool(asset);
        return repayAmount;
    }

    /**
     * @dev Allows depositors to enable/disable a specific deposited asset as collateral.
     * @param asset The address of the underlying asset deposited.
     * @param useAsCollateral `true` if the user wants to use the deposit as collateral, `false` otherwise.
     */
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral)
        external
        override
        whenNotPaused
    {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[asset];

        MiniPoolValidationLogic.validateSetUseReserveAsCollateral(
            reserve,
            asset,
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
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk.
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation.
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation.
     * @param user The address of the borrower getting liquidated.
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover.
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly.
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external override whenNotPaused {
        MiniPoolLiquidationLogic.liquidationCall(
            _reserves,
            _usersConfig,
            _reservesList,
            MiniPoolLiquidationLogic.liquidationCallParams(
                address(_addressesProvider),
                _reservesCount,
                collateralAsset,
                debtAsset,
                user,
                debtToCover,
                receiveAToken
            )
        );
        _repayLendingPool(debtAsset);
    }

    /**
     * @dev Internal function to repay the flow debt of the minipool to the lending pool.
     * @param asset The address of the underlying asset to repay.
     */
    function _repayLendingPool(address asset) internal {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[asset];
        address aErc6909 = reserve.aErc6909;
        address underlyingAsset;

        if (IAERC6909(aErc6909).isTranche(reserve.aTokenID)) {
            underlyingAsset = ATokenNonRebasing(asset).UNDERLYING_ASSET_ADDRESS();
            uint256 underlyingDebt =
                ATokenNonRebasing(asset).convertToShares(getCurrentLendingPoolDebt(underlyingAsset)); // share

            if (underlyingDebt != 0) {
                MiniPoolWithdrawLogic.internalWithdraw(
                    MiniPoolWithdrawLogic.withdrawParams(
                        asset, underlyingDebt, address(this), _reservesCount
                    ),
                    _reserves,
                    _usersConfig,
                    _reservesList,
                    _addressesProvider
                ); // MUST use share

                ILendingPool(_addressesProvider.getLendingPool()).repayWithATokens(
                    underlyingAsset,
                    true,
                    IERC20Detailed(ATokenNonRebasing(asset).ATOKEN_ADDRESS()).balanceOf(
                        address(this)
                    )
                ); // MUST use asset
            }
            uint256 remainingBalance =
                IAERC6909(aErc6909).balanceOf(address(this), reserve.aTokenID);

            if (
                getCurrentLendingPoolDebt(underlyingAsset) == 0
                    && remainingBalance > ERROR_REMAINDER_MARGIN /* We leave ERROR_REMAINDER_MARGIN of aToken wei in the minipool to mitigate rounding errors. */
                    && IERC20Detailed(asset).balanceOf(aErc6909)
                        > remainingBalance - ERROR_REMAINDER_MARGIN /* Check if there is enough liquidity to withdraw. */
            ) {
                // Withdraw the remaining AERC6909 to Treasury. This is due to Minipool IR > Lending IR.
                // `this.` modifies the execution context => msg.sender == address(this).
                this.withdraw(
                    asset,
                    false,
                    remainingBalance - ERROR_REMAINDER_MARGIN,
                    _addressesProvider.getMiniPoolCod3xTreasury()
                );
            }
        }
    }

    /**
     * @dev Allows smartcontracts to access the liquidity of the pool within one transaction,
     * as long as the amount taken plus a fee is returned.
     * IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.
     * @param flashLoanParams struct containing receiverAddress, onBehalfOf, assets, amounts.
     * @param modes Types of the debt to open if the flash loan is not returned:
     *   0    -> Don't open any debt, just revert if funds can't be transferred from the receiver.
     *   =! 0 -> Open debt at variable rate for the value of the amount flash-borrowed to the `onBehalfOf` address.
     * @param params Variadic packed params to pass to the receiver as extra information.
     */
    function flashLoan(
        FlashLoanParams memory flashLoanParams,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        bytes calldata params
    ) external override whenNotPaused {
        uint256[] memory minAmounts = new uint256[](flashLoanParams.assets.length);
        for (uint256 idx = 0; idx < flashLoanParams.assets.length; idx++) {
            minAmounts[idx] =
                minDebtThreshold(IERC20Detailed(flashLoanParams.assets[idx]).decimals());
        }
        MiniPoolFlashLoanLogic.flashLoan(
            MiniPoolFlashLoanLogic.FlashLoanParams(
                flashLoanParams.receiverAddress,
                flashLoanParams.assets,
                flashLoanParams.onBehalfOf,
                _addressesProvider,
                _reservesCount,
                _flashLoanPremiumTotal,
                amounts,
                modes,
                params,
                minAmounts
            ),
            _reservesList,
            _usersConfig,
            _reserves
        );
    }

    /**
     * @dev Returns the state and configuration of the reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @return The state of the reserve.
     */
    function getReserveData(address asset)
        external
        view
        override
        returns (DataTypes.MiniPoolReserveData memory)
    {
        return _reserves[asset];
    }

    /**
     * @dev Returns the user account data across all the reserves.
     * @param user The address of the user.
     * @return totalCollateralETH the total collateral in ETH of the user.
     * @return totalDebtETH the total debt in ETH of the user.
     * @return availableBorrowsETH the borrowing power left of the user.
     * @return currentLiquidationThreshold the liquidation threshold of the user.
     * @return ltv the loan to value of the user.
     * @return healthFactor the current health factor of the user.
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
        MiniPoolGenericLogic.calculateUserAccountData(
            user,
            _reserves,
            _usersConfig[user],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        availableBorrowsETH =
            MiniPoolGenericLogic.calculateAvailableBorrowsETH(totalCollateralETH, totalDebtETH, ltv);
    }

    /**
     * @dev Returns the configuration of the reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @return The configuration of the reserve.
     */
    function getConfiguration(address asset)
        external
        view
        override
        returns (DataTypes.ReserveConfigurationMap memory)
    {
        return _reserves[asset].configuration;
    }

    /**
     * @dev Returns the configuration of the user across all the reserves.
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
     * @dev Returns the normalized income per unit of asset.
     * @param asset The address of the underlying asset of the reserve.
     * @return The reserve's normalized income.
     */
    function getReserveNormalizedIncome(address asset)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _reserves[asset].getNormalizedIncome();
    }

    /**
     * @dev Returns the normalized variable debt per unit of asset.
     * @param asset The address of the underlying asset of the reserve.
     * @return The reserve normalized variable debt.
     */
    function getReserveNormalizedVariableDebt(address asset)
        external
        view
        override
        returns (uint256)
    {
        return _reserves[asset].getNormalizedDebt();
    }

    /**
     * @dev Returns if the LendingPool is paused.
     * @return `true` if the LendingPool is paused, `false` otherwise.
     */
    function paused() external view override returns (bool) {
        return _paused;
    }

    /**
     * @dev Returns the list of the initialized reserves and their types.
     * @return A tuple containing:
     *   - An array of addresses representing the initialized reserves.
     *   - An array of booleans indicating the type of each reserve.
     */
    function getReservesList() external view override returns (address[] memory, bool[] memory) {
        address[] memory _activeReserves = new address[](_reservesCount);
        bool[] memory _activeReservesTypes = new bool[](_reservesCount);

        for (uint256 i = 0; i < _reservesCount; i++) {
            _activeReserves[i] = _reservesList[i];
            _activeReservesTypes[i] = false;
        }
        return (_activeReserves, _activeReservesTypes);
    }

    /// @dev Returns the total number of initialized reserves.
    function getReservesCount() external view override returns (uint256) {
        return _reservesCount;
    }

    /**
     * @dev Returns the cached addresses provider instance connected to this contract.
     * @return The `IMiniPoolAddressesProvider` instance.
     */
    function getAddressesProvider() external view override returns (IMiniPoolAddressesProvider) {
        return _addressesProvider;
    }

    /**
     * @dev Returns threshold for minimal debt.
     * @param decimals Decimals of the token.
     * @return The `_minDebtThreshold` instance.
     */
    function minDebtThreshold(uint8 decimals) public view returns (uint256) {
        return _minDebtThreshold * (10 ** (decimals - THRESHOLD_SCALING_DECIMALS));
    }

    /**
     * @dev Returns the total premium percentage charged on flash loans.
     * @return The flash loan premium as a percentage value.
     */
    function FLASHLOAN_PREMIUM_TOTAL() public view returns (uint256) {
        return _flashLoanPremiumTotal;
    }

    /**
     * @dev Returns the maximum number of reserves that can be supported by this lending pool.
     * @return The maximum number of reserves allowed.
     */
    function MAX_NUMBER_RESERVES() public view returns (uint256) {
        return _maxNumberOfReserves;
    }

    /**
     * @dev Validates and finalizes an aToken transfer.
     * - Only callable by the overlying aToken of the `asset`.
     * @param asset The address of the underlying asset of the aToken.
     * @param from The user from which the aTokens are transferred.
     * @param to The user receiving the aTokens.
     * @param amount The amount being transferred/withdrawn.
     * @param balanceFromBefore The aToken balance of the `from` user before the transfer.
     * @param balanceToBefore The aToken balance of the `to` user before the transfer.
     */
    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external override whenNotPaused {
        MiniPoolWithdrawLogic.finalizeTransfer(
            MiniPoolWithdrawLogic.finalizeTransferParams(
                asset, from, to, amount, balanceFromBefore, balanceToBefore, _reservesCount
            ),
            _reserves,
            _usersConfig,
            _reservesList,
            _addressesProvider
        );
    }

    /**
     * @dev Sets minimal debt threshold for specific decimals
     * @param threshold Minimal debt threshold value to set.
     */
    function setMinDebtThreshold(uint256 threshold) external onlyMiniPoolConfigurator {
        _minDebtThreshold = threshold;
    }

    /**
     * @dev Initializes a reserve, activating it, assigning an aToken and debt tokens and an
     * interest rate strategy.
     * - Only callable by the LendingPoolConfigurator contract.
     * @param asset The address of the underlying asset of the reserve.
     * @param aErc6909 Whether the reserve is boosted by a vault.
     * @param aTokenID The address of the aToken that will be assigned to the reserve.
     * @param variableDebtTokenID The address of the VariableDebtToken that will be assigned to the reserve.
     * @param interestRateStrategyAddress The address of the interest rate strategy contract.
     */
    function initReserve(
        address asset,
        IAERC6909 aErc6909,
        uint256 aTokenID,
        uint256 variableDebtTokenID,
        address interestRateStrategyAddress
    ) external override onlyMiniPoolConfigurator {
        require(Address.isContract(asset), Errors.LP_NOT_CONTRACT);
        _reserves[asset].init(
            asset, aErc6909, aTokenID, variableDebtTokenID, interestRateStrategyAddress
        );
        _addReserveToList(asset);
    }

    /**
     * @dev Updates the address of the interest rate strategy contract.
     * - Only callable by the LendingPoolConfigurator contract.
     * @param asset The address of the underlying asset of the reserve.
     * @param rateStrategyAddress The address of the interest rate strategy contract.
     */
    function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress)
        external
        override
        onlyMiniPoolConfigurator
    {
        _reserves[asset].interestRateStrategyAddress = rateStrategyAddress;
    }

    /**
     * @dev Sets the configuration bitmap of the reserve as a whole.
     * - Only callable by the LendingPoolConfigurator contract.
     * @param asset The address of the underlying asset of the reserve.
     * @param configuration The new configuration bitmap.
     */
    function setConfiguration(address asset, uint256 configuration)
        external
        override
        onlyMiniPoolConfigurator
    {
        _reserves[asset].configuration.data = configuration;
    }

    /**
     * @dev Set the _pause state of a reserve.
     * - Only callable by the LendingPoolConfigurator contract.
     * @param val `true` to pause the reserve, `false` to un-pause it.
     */
    function setPause(bool val) external override onlyMiniPoolConfigurator {
        require(val != _paused, Errors.VL_INVALID_INPUT);

        _paused = val;
        if (_paused) {
            emit Paused();
        } else {
            emit Unpaused();
        }
    }
    /**
     * @dev Adds a reserve to the list of reserves.
     * @param asset The address of the underlying asset of the reserve to be added.
     */

    function _addReserveToList(address asset) internal {
        uint256 reservesCount = _reservesCount;

        require(reservesCount < _maxNumberOfReserves, Errors.LP_NO_MORE_RESERVES_ALLOWED);

        bool reserveAlreadyAdded = _reserves[asset].id != 0 || _reservesList[0] == asset;

        require(!reserveAlreadyAdded, Errors.LP_RESERVE_ALREADY_ADDED);

        _reserves[asset].id = uint8(reservesCount);
        _reservesList[reservesCount] = asset;

        _reservesCount = reservesCount + 1;
    }

    /**
     * @dev Returns the current lending pool debt for a specific asset.
     * @param asset The address of the asset to check the debt for.
     * @return The current lending pool debt amount.
     */
    function getCurrentLendingPoolDebt(address asset) public view returns (uint256) {
        return IFlowLimiter(_addressesProvider.getFlowLimiter()).currentFlow(asset, address(this));
    }
    /**
     * @dev Sets the rewarder contract for a specific reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param rewarder The address of the rewarder contract to be set.
     * @notice Multiple reserves share the same aToken6909, so changing
     * the rewarder for one reserve will change it for all reserves.
     */

    function setRewarderForReserve(address asset, address rewarder)
        external
        onlyMiniPoolConfigurator
    {
        IAERC6909(_reserves[asset].aErc6909).setIncentivesController(IMiniPoolRewarder(rewarder));
    }

    /**
     * @dev Updates the flash loan premium total.
     * @param flashLoanPremiumTotal The new premium value for flash loans.
     */
    function updateFlashLoanFee(uint128 flashLoanPremiumTotal) external onlyMiniPoolConfigurator {
        _updateFlashLoanFee(flashLoanPremiumTotal);
    }

    /**
     * @notice Synchronizes the reserve indexes state for a specific asset
     * @dev Only callable by the LendingPoolConfigurator
     * @param asset The address of the underlying asset of the reserve
     */
    function syncIndexesState(address asset) external virtual override onlyMiniPoolConfigurator {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[asset];

        reserve.updateState();
    }

    /**
     * @notice Synchronizes the interest rates state for a specific asset
     * @dev Only callable by the LendingPoolConfigurator
     * @param asset The address of the underlying asset of the reserve
     */
    function syncRatesState(address asset) external virtual override onlyMiniPoolConfigurator {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[asset];

        reserve.updateInterestRates(asset, 0, 0);
    }

    function syncState(address asset) external virtual override onlyLendingPool {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[asset];

        reserve.updateState();
        reserve.updateInterestRates(asset, 0, 0);
    }

    /**
     * @dev Internal function to update the flash loan premium total.
     * @param flashLoanPremiumTotal The new premium value to be set.
     */
    function _updateFlashLoanFee(uint128 flashLoanPremiumTotal) internal {
        _flashLoanPremiumTotal = flashLoanPremiumTotal;
    }
}
