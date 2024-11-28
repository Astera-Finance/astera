// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {ILendingPoolAddressesProvider} from
    "../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {DataTypes} from "../../contracts/protocol/libraries/types/DataTypes.sol";

interface ILendingPool {
    /**
     * @dev Emitted on deposit()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The address initiating the deposit
     * @param onBehalfOf The beneficiary of the deposit, receiving the aTokens
     * @param amount The amount deposited
     */
    event Deposit(
        address indexed reserve, address user, address indexed onBehalfOf, uint256 amount
    );

    /**
     * @dev Emitted on withdraw()
     * @param reserve The address of the underlyng asset being withdrawn
     * @param user The address initiating the withdrawal, owner of aTokens
     * @param to Address that will receive the underlying
     * @param amount The amount to be withdrawn
     */
    event Withdraw(
        address indexed reserve, address indexed user, address indexed to, uint256 amount
    );

    /**
     * @dev Emitted on borrow() and flashLoan() when debt needs to be opened
     * @param reserve The address of the underlying asset being borrowed
     * @param user The address of the user initiating the borrow(), receiving the funds on borrow() or just
     * initiator of the transaction on flashLoan()
     * @param onBehalfOf The address that will be getting the debt
     * @param amount The amount borrowed out
     * @param borrowRate The numeric rate at which the user has borrowed
     */
    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRate
    );

    /**
     * @dev Emitted on repay()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The beneficiary of the repayment, getting his debt reduced
     * @param repayer The address of the user initiating the repay(), providing the funds
     * @param amount The amount repaid
     */
    event Repay(
        address indexed reserve, address indexed user, address indexed repayer, uint256 amount
    );

    /**
     * @dev Emitted on setUserUseReserveAsCollateral()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The address of the user enabling the usage as collateral
     */
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

    /**
     * @dev Emitted on setUserUseReserveAsCollateral()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The address of the user enabling the usage as collateral
     */
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    /**
     * @dev Emitted on flashLoan()
     * @param target The address of the flash loan receiver contract
     * @param initiator The address initiating the flash loan
     * @param asset The address of the asset being flash borrowed
     * @param interestRateMode The interest rate mode selected for the flash loan:
     *   0 -> Don't open any debt, just revert if funds can't be transferred from the receiver
     *   != 0 -> Open debt at variable rate for the value of the amount flash-borrowed
     * @param amount The amount flash borrowed
     * @param premium The fee charged for the flash loan
     */
    event FlashLoan(
        address indexed target,
        address indexed initiator,
        address indexed asset,
        DataTypes.InterestRateMode interestRateMode,
        uint256 amount,
        uint256 premium
    );

    /**
     * @dev Emitted when the pause is triggered.
     */
    event Paused();

    /**
     * @dev Emitted when the pause is lifted.
     */
    event Unpaused();

    /**
     * @dev Emitted when a borrower is liquidated. This event is emitted by the LendingPool via
     * LendingPoolCollateral manager using a DELEGATECALL
     * This allows to have the events in the generated ABI for LendingPool.
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param liquidatedCollateralAmount The amount of collateral received by the liiquidator
     * @param liquidator The address of the liquidator
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     */
    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken
    );

    /**
     * @dev Emitted when the state of a reserve is updated. NOTE: This event is actually declared
     * in the ReserveLogic library and emitted in the updateInterestRates() function. Since the function is internal,
     * the event will actually be fired by the LendingPool contract. The event is therefore replicated here so it
     * gets added to the LendingPool ABI
     * @param reserve The address of the underlying asset of the reserve
     * @param liquidityRate The new liquidity rate
     * @param variableBorrowRate The new variable borrow rate
     * @param liquidityIndex The new liquidity index
     * @param variableBorrowIndex The new variable borrow index
     */
    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    /**
     * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
     * @param asset The address of the underlying asset to deposit
     * @param reserveType Whether the reserve is boosted by a vault
     * @param amount The amount to be deposited
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     */
    function deposit(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external;

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param asset The address of the underlying asset to withdraw
     * @param reserveType Whether the reserve is boosted by a vault
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     */
    function withdraw(address asset, bool reserveType, uint256 amount, address to)
        external
        returns (uint256);

    /**
     * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
     * already deposited enough collateral, or he was given enough allowance by a credit delegator on the
     * VariableDebtToken
     * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
     *   and 100 variable debt tokens
     * @param asset The address of the underlying asset to borrow
     * @param reserveType Whether the reserve is boosted by a vault
     * @param amount The amount to be borrowed
     * @param onBehalfOf Address of the user who will receive the debt. Should be the address of the borrower itself
     * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
     * if he has been given credit delegation allowance
     */
    function borrow(address asset, bool reserveType, uint256 amount, address onBehalfOf) external;

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
     * - E.g. User repays 100 USDC, burning 100 variable debt tokens of the `onBehalfOf` address
     * @param asset The address of the borrowed underlying asset previously borrowed
     * @param reserveType Whether the reserve is boosted by a vault
     * @param amount The amount to repay
     * - Send the value type(uint256).max in order to repay the whole debt for `asset`
     * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
     * user calling the function if he wants to reduce/remove his own debt, or the address of any other
     * other borrower whose debt should be removed
     * @return The final amount repaid
     */
    function repay(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external
        returns (uint256);

    /**
     * @notice Borrows an unbacked amount of the reserve's underlying asset.
     * @dev This function is restricted to minipools.
     * @param asset The address of the underlying asset to borrow.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param amount The amount to borrow.
     * @param miniPoolAddress The address of the mini pool.
     * @param aTokenAddress The address of the aToken.
     */
    function miniPoolBorrow(
        address asset,
        bool reserveType,
        uint256 amount,
        address miniPoolAddress,
        address aTokenAddress
    ) external;

    /**
     * @notice Repays a borrowed amount using aTokens.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param amount The amount to repay.
     * @return The final amount repaid.
     */
    function repayWithATokens(address asset, bool reserveType, uint256 amount)
        external
        returns (uint256);
    /**
     * @dev Allows depositors to enable/disable a specific deposited asset as collateral
     * @param asset The address of the underlying asset deposited
     * @param reserveType Whether the reserve is boosted by a vault
     * @param useAsCollateral `true` if the user wants to use the deposit as collateral, `false` otherwise
     */
    function setUserUseReserveAsCollateral(address asset, bool reserveType, bool useAsCollateral)
        external;

    /**
     * @dev Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param collateralAssetType Whether the collateral asset reserve is boosted by a vault
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param debtAssetType Whether the debt asset reserve is boosted by a vault
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
    ) external;

    /**
     * @param receiverAddress The address of the contract receiving the funds, implementing the IFlashLoanReceiver interface
     * @param assets The addresses of the assets being flash-borrowed
     * @param reserveTypes Whether the reserves are boosted by a vault
     * @param onBehalfOf The address that will receive the debt
     */
    struct FlashLoanParams {
        address receiverAddress;
        address[] assets;
        bool[] reserveTypes;
        address onBehalfOf;
    }

    /**
     * @dev Allows smartcontracts to access the liquidity of the pool within one transaction,
     * as long as the amount taken plus a fee is returned.
     * IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.
     * @param flashLoanParams struct containing receiverAddress, onBehalfOf
     * @param amounts The amounts amounts being flash-borrowed
     * @param modes Types of the debt to open if the flash loan is not returned:
     *   0    -> Don't open any debt, just revert if funds can't be transferred from the receiver
     *   =! 0 -> Open debt at variable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
     * @param params Variadic packed params to pass to the receiver as extra information
     */
    function flashLoan(
        FlashLoanParams memory flashLoanParams,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        bytes calldata params
    ) external;

    /**
     * @dev Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return currentLiquidationThreshold the liquidation threshold of the user
     * @return ltv the loan to value of the user
     * @return healthFactor the current health factor of the user
     */
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /**
     * @notice Initializes a new reserve in the lending pool
     * @param reserve The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param aTokenAddress The address of the aToken contract associated with the reserve
     * @param variableDebtAddress The address of the variable debt token contract
     * @param interestRateStrategyAddress The address of the interest rate strategy contract
     */
    function initReserve(
        address reserve,
        bool reserveType,
        address aTokenAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external;

    /**
     * @notice Sets the interest rate strategy address for a reserve
     * @param reserve The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param rateStrategyAddress The new interest rate strategy address
     */
    function setReserveInterestRateStrategyAddress(
        address reserve,
        bool reserveType,
        address rateStrategyAddress
    ) external;

    function setConfiguration(address reserve, bool reserveType, uint256 configuration) external;

    /**
     * @dev Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @return The configuration of the reserve
     */
    function getConfiguration(address asset, bool reserveType)
        external
        view
        returns (DataTypes.ReserveConfigurationMap memory);

    /**
     * @dev Returns the configuration of the user across all the reserves
     * @param user The user address
     * @return The configuration of the user
     */
    function getUserConfiguration(address user)
        external
        view
        returns (DataTypes.UserConfigurationMap memory);

    /**
     * @dev Returns the normalized income normalized income of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @return The reserve's normalized income
     */
    function getReserveNormalizedIncome(address asset, bool reserveType)
        external
        view
        returns (uint256);

    /**
     * @dev Returns the normalized variable debt per unit of asset
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @return The reserve normalized variable debt
     */
    function getReserveNormalizedVariableDebt(address asset, bool reserveType)
        external
        view
        returns (uint256);

    /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @return The state of the reserve
     */
    function getReserveData(address asset, bool reserveType)
        external
        view
        returns (DataTypes.ReserveData memory);

    /**
     * @notice Validates and finalizes an aToken transfer
     * @dev Only callable by the overlying aToken of the `asset`
     * @param asset The address of the underlying asset of the aToken
     * @param reserveType A boolean indicating whether the asset is boosted by a vault.
     * @param from The user from which the aTokens are transferred
     * @param to The user receiving the aTokens
     * @param amount The amount being transferred/withdrawn
     * @param balanceFromBefore The aToken balance of the `from` user before the transfer
     * @param balanceToBefore The aToken balance of the `to` user before the transfer
     */
    function finalizeTransfer(
        address asset,
        bool reserveType,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external;

    /**
     * @notice Returns the list of all the reserves.
     * @return An array of reserve addresses and an array indicating if each reserve is boosted by a vault.
     */
    function getReservesList() external view returns (address[] memory, bool[] memory);

    /**
     * @notice Returns the number of reserves.
     * @return The total number of reserves available.
     */
    function getReservesCount() external view returns (uint256);

    /**
     * @notice Returns the addresses provider of the lending pool.
     * @return The ILendingPoolAddressesProvider contract associated with this lending pool.
     */
    function getAddressesProvider() external view returns (ILendingPoolAddressesProvider);

    /**
     * @notice Returns the maximum number of reserves that the pool can support.
     * @return The maximum number of reserves.
     */
    function MAX_NUMBER_RESERVES() external view returns (uint256);

    /**
     * @notice Sets the paused state of the pool.
     * @param val A boolean value indicating whether the pool should be paused (`true`) or unpaused (`false`).
     */
    function setPause(bool val) external;

    /**
     * @notice Returns whether the pool is currently paused.
     * @return `true` if the pool is paused, otherwise `false`.
     */
    function paused() external view returns (bool);

    /**
     * @notice Sets the farming percentage for a specific aToken.
     * @param aTokenAddress The address of the aToken.
     * @param farmingPct The new farming percentage.
     */
    function setFarmingPct(address aTokenAddress, uint256 farmingPct) external;

    /**
     * @notice Sets the claiming threshold for a specific aToken.
     * @param aTokenAddress The address of the aToken.
     * @param claimingThreshold The new claiming threshold to be set.
     */
    function setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold) external;

    /**
     * @notice Sets the allowable drift for the farming percentage.
     * @param aTokenAddress The address of the aToken.
     * @param farmingPctDrift The allowable drift for the farming percentage.
     */
    function setFarmingPctDrift(address aTokenAddress, uint256 farmingPctDrift) external;

    /**
     * @notice Sets the profit handler for a specific aToken.
     * @param aTokenAddress The address of the aToken.
     * @param profitHandler The address of the profit handler.
     */
    function setProfitHandler(address aTokenAddress, address profitHandler) external;

    /**
     * @notice Sets the rehypothecation vault for a specific aToken.
     * @param aTokenAddress The address of the aToken.
     * @param vault The address of the vault to be set.
     */
    function setVault(address aTokenAddress, address vault) external;

    /**
     * @notice Rebalances the assets of a specific aToken rehypothecation vault.
     * @param aTokenAddress The address of the aToken to be rebalanced.
     */
    function rebalance(address aTokenAddress) external;

    /**
     * @notice Returns the total assets managed by a specific aToken/reserve.
     * @param aTokenAddress The address of the aToken.
     * @return The total amount of assets managed by the aToken.
     */
    function getTotalManagedAssets(address aTokenAddress) external view returns (uint256);

    /**
     * @notice Updates the flash loan fee.
     * @param flashLoanPremiumTotal The new total premium to be applied on flash loans.
     */
    function updateFlashLoanFee(uint128 flashLoanPremiumTotal) external;

    /**
     * @notice Sets the rewarder contract for a specific reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param rewarder The address of the rewarder contract to be set.
     */
    function setRewarderForReserve(address asset, bool reserveType, address rewarder) external;

    /**
     * @notice Sets the treasury for a specific reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param treasury The address of the treasury to be set.
     */
    function setTreasury(address asset, bool reserveType, address treasury) external;

    /**
     * @notice Returns the total premium applied on flash loans.
     * @return The total flash loan premium.
     */
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}
