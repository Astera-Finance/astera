// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {ILendingPoolAddressesProvider} from
    "../../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {ReserveConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {Helpers} from "../../../../../contracts/protocol/libraries/helpers/Helpers.sol";
import {IFlashLoanReceiver} from "../../../../../contracts/interfaces/IFlashLoanReceiver.sol"; // Add this line
import {BorrowLogic} from "./BorrowLogic.sol";
import {EnumerableSet} from
    "../../../../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title FlashLoanLogic
 * @author Cod3x
 * @notice Implements the flash loan logic for the Cod3x lending protocol.
 * @dev Contains functions to execute flash loans and handle their repayments.
 */
library FlashLoanLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveLogic for DataTypes.ReserveData;
    using ValidationLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev Emitted when a flash loan is executed.
     * @param target The address of the flash loan receiver contract.
     * @param initiator The address initiating the flash loan.
     * @param asset The address of the asset being flash borrowed.
     * @param interestRateMode The interest rate mode of the flash loan.
     * @param amount The amount being flash borrowed.
     * @param premium The fee being charged for the flash loan.
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
     * @dev Struct containing local variables used in flash loan execution.
     */
    struct FlashLoanLocalVars {
        IFlashLoanReceiver receiver;
        uint256 i;
        address currentAsset;
        uint256 currentAmount;
        bool currentType;
        address currentATokenAddress;
        uint256 currentPremium;
    }

    /**
     * @dev Struct containing parameters for flash loan repayment.
     * @param amount The borrowed amount to be repaid.
     * @param totalPremium The total premium to be paid.
     * @param asset The address of the borrowed asset.
     * @param aToken The address of the corresponding aToken.
     * @param receiverAddress The address of the flash loan receiver.
     */
    struct FlashLoanRepaymentParams {
        uint256 amount;
        uint256 totalPremium;
        address asset;
        address aToken;
        address receiverAddress;
    }

    /**
     * @dev Struct containing parameters for flash loan execution.
     * @param receiverAddress The address of the contract receiving the flash loan.
     * @param assets Array of asset addresses being borrowed.
     * @param reserveTypes Array of booleans indicating if reserves are boosted by vaults.
     * @param onBehalfOf The address that will receive the debt in case of non-revert.
     * @param addressesProvider The addresses provider instance.
     * @param reservesCount Total number of initialized reserves.
     * @param flashLoanPremiumTotal Total premium for flash loans.
     * @param amounts Array of amounts being borrowed.
     * @param modes Array of interest rate modes.
     * @param params Bytes encoded params to pass to receiver's executeOperation.
     */
    struct FlashLoanParams {
        address receiverAddress;
        address[] assets;
        bool[] reserveTypes;
        address onBehalfOf;
        ILendingPoolAddressesProvider addressesProvider;
        uint256 reservesCount;
        uint256 flashLoanPremiumTotal;
        uint256[] amounts;
        uint256[] modes;
        bytes params;
    }

    /**
     * @notice Executes a flash loan operation.
     * @dev Allows smart contracts to access the liquidity of the pool within one transaction.
     * @param flashLoanParams The parameters for the flash loan operation.
     * @param reservesList Mapping of reserve references.
     * @param usersConfig Mapping of user configurations.
     * @param reserves Mapping of reserve data.
     */
    function flashLoan(
        FlashLoanParams memory flashLoanParams,
        mapping(address => EnumerableSet.AddressSet) storage assetToMinipoolFlowBorrowing,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves
    ) external {
        FlashLoanLocalVars memory vars;

        ValidationLogic.validateFlashloan(
            reserves,
            flashLoanParams.reserveTypes,
            flashLoanParams.assets,
            flashLoanParams.amounts,
            flashLoanParams.modes
        );

        address[] memory aTokenAddresses = new address[](flashLoanParams.assets.length);
        uint256[] memory premiums = new uint256[](flashLoanParams.assets.length);

        vars.receiver = IFlashLoanReceiver(flashLoanParams.receiverAddress);

        (aTokenAddresses, premiums) = getATokenAdressesAndPremiums(
            flashLoanParams.receiverAddress,
            flashLoanParams.assets,
            flashLoanParams.reserveTypes,
            flashLoanParams.amounts,
            flashLoanParams.flashLoanPremiumTotal,
            flashLoanParams.modes,
            reserves
        );

        require(
            vars.receiver.executeOperation(
                flashLoanParams.assets,
                flashLoanParams.amounts,
                premiums,
                msg.sender,
                flashLoanParams.params
            ),
            Errors.LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN
        );

        for (vars.i = 0; vars.i < flashLoanParams.assets.length; vars.i++) {
            vars.currentAsset = flashLoanParams.assets[vars.i];
            vars.currentType = flashLoanParams.reserveTypes[vars.i];
            vars.currentAmount = flashLoanParams.amounts[vars.i];
            vars.currentPremium = premiums[vars.i];
            vars.currentATokenAddress = aTokenAddresses[vars.i];

            if (
                DataTypes.InterestRateMode(flashLoanParams.modes[vars.i])
                    == DataTypes.InterestRateMode.NONE
            ) {
                _handleFlashLoanRepayment(
                    reserves[vars.currentAsset][vars.currentType],
                    assetToMinipoolFlowBorrowing[vars.currentAsset],
                    FlashLoanRepaymentParams({
                        amount: vars.currentAmount,
                        totalPremium: vars.currentPremium,
                        asset: vars.currentAsset,
                        aToken: vars.currentATokenAddress,
                        receiverAddress: flashLoanParams.receiverAddress
                    })
                );
            } else {
                // If the user chose to not return the funds, the system checks if there is enough collateral and
                // eventually opens a debt position.
                BorrowLogic.executeBorrow(
                    BorrowLogic.ExecuteBorrowParams(
                        vars.currentAsset,
                        vars.currentType,
                        msg.sender,
                        flashLoanParams.onBehalfOf,
                        vars.currentAmount,
                        vars.currentATokenAddress,
                        false,
                        flashLoanParams.addressesProvider,
                        flashLoanParams.reservesCount
                    ),
                    assetToMinipoolFlowBorrowing[vars.currentAsset],
                    reserves,
                    reservesList,
                    usersConfig
                );
            }

            emit FlashLoan(
                flashLoanParams.receiverAddress,
                msg.sender,
                vars.currentAsset,
                DataTypes.InterestRateMode(flashLoanParams.modes[vars.i]),
                vars.currentAmount,
                vars.currentPremium
            );
        }
    }

    /**
     * @notice Gets aToken addresses and calculates premiums for flash loans.
     * @param receiverAddress The address receiving the flash loan.
     * @param assets Array of asset addresses.
     * @param reserveTypes Array of reserve types.
     * @param amounts Array of amounts being borrowed.
     * @param flashLoanPremiumTotal Total premium percentage.
     * @param modes Array of interest rate modes.
     * @param _reserves Mapping of reserve data.
     * @return aTokenAddresses Array of aToken addresses.
     * @return premiums Array of calculated premiums.
     */
    function getATokenAdressesAndPremiums(
        address receiverAddress,
        address[] memory assets,
        bool[] memory reserveTypes,
        uint256[] memory amounts,
        uint256 flashLoanPremiumTotal,
        uint256[] memory modes,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage _reserves
    ) internal returns (address[] memory aTokenAddresses, uint256[] memory premiums) {
        aTokenAddresses = new address[](assets.length);
        premiums = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            aTokenAddresses[i] = _reserves[assets[i]][reserveTypes[i]].aTokenAddress;

            uint256 mode = modes[i];
            require(
                uint256(type(DataTypes.InterestRateMode).max) >= mode,
                Errors.VL_INVALID_INTEREST_RATE_MODE
            );

            premiums[i] = DataTypes.InterestRateMode(mode) == DataTypes.InterestRateMode.NONE
                ? amounts[i] * flashLoanPremiumTotal / 10000
                : 0;

            IAToken(aTokenAddresses[i]).transferUnderlyingTo(receiverAddress, amounts[i]);
        }
    }

    /**
     * @notice Handles the repayment of flash loaned assets plus premium.
     * @dev Will pull the amount plus premium from the receiver, which must have approved the pool.
     * @param reserve The state of the flash loaned reserve.
     * @param params The parameters needed to execute the repayment.
     */
    function _handleFlashLoanRepayment(
        DataTypes.ReserveData storage reserve,
        EnumerableSet.AddressSet storage minipoolFlowBorrowing,
        FlashLoanRepaymentParams memory params
    ) internal {
        uint256 amountPlusPremium = params.amount + params.totalPremium;

        // DataTypes.ReserveCache memory reserveCache = reserve.cache();
        reserve.updateState();
        reserve.cumulateToLiquidityIndex(IERC20(params.aToken).totalSupply(), params.totalPremium);

        reserve.updateInterestRates(
            minipoolFlowBorrowing, params.asset, params.aToken, amountPlusPremium, 0
        );

        IERC20(params.asset).safeTransferFrom(
            params.receiverAddress, params.aToken, amountPlusPremium
        );

        IAToken(params.aToken).handleRepayment(
            params.receiverAddress, params.receiverAddress, amountPlusPremium
        );
    }
}
