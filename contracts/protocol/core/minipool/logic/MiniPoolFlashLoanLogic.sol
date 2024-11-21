// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IPriceOracleGetter} from "../../../../../contracts/interfaces/IPriceOracleGetter.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IVariableDebtToken} from "../../../../../contracts/interfaces/IVariableDebtToken.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {MiniPoolGenericLogic} from "./MiniPoolGenericLogic.sol";
import {MiniPoolReserveLogic} from "./MiniPoolReserveLogic.sol";
import {MiniPoolValidationLogic} from "./MiniPoolValidationLogic.sol";
import {ReserveConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {Helpers} from "../../../../../contracts/protocol/libraries/helpers/Helpers.sol";
import {IFlashLoanReceiver} from "../../../../../contracts/interfaces/IFlashLoanReceiver.sol"; // Add this line
import {MiniPoolBorrowLogic} from "./MiniPoolBorrowLogic.sol";
import {IAERC6909} from "../../../../../contracts/interfaces/IAERC6909.sol";

/**
 * @title MiniPoolFlashLoanLogic
 * @author Cod3x
 */
library MiniPoolFlashLoanLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    event FlashLoan(
        address indexed target,
        address indexed initiator,
        address indexed asset,
        DataTypes.InterestRateMode interestRateMode,
        uint256 amount,
        uint256 premium
    );

    struct FlashLoanLocalVars {
        IFlashLoanReceiver receiver;
        uint256 i;
        address currentAsset;
        uint256 currentAmount;
        address currentATokenAddress;
        uint256 currentPremium;
    }

    struct FlashLoanRepaymentParams {
        uint256 amount;
        uint256 totalPremium;
        uint256 liquidityIndex;
        address asset;
        address aToken;
        address receiverAddress;
    }

    struct FlashLoanParams {
        address receiverAddress;
        address[] assets;
        address onBehalfOf;
        IMiniPoolAddressesProvider addressesProvider;
        uint256 reservesCount;
        uint256 flashLoanPremiumTotal;
        uint256[] amounts;
        uint256[] modes;
        bytes params;
    }

    /**
     * @dev Allows smartcontracts to access the liquidity of the pool within one transaction,
     * as long as the amount taken plus a fee is returned.
     * IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.
     * @param flashLoanParams struct containing receiverAddress, onBehalfOf, assets, amounts
     *
     */
    function flashLoan(
        FlashLoanParams memory flashLoanParams,
        mapping(uint256 => address) storage reservesList,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves
    ) external {
        FlashLoanLocalVars memory vars;

        MiniPoolValidationLogic.validateFlashloan(
            reserves, flashLoanParams.assets, flashLoanParams.amounts
        );

        address[] memory aTokenAddresses = new address[](flashLoanParams.assets.length);
        uint256[] memory premiums = new uint256[](flashLoanParams.assets.length);

        vars.receiver = IFlashLoanReceiver(flashLoanParams.receiverAddress);

        (aTokenAddresses, premiums) = getATokenAdressesAndPremiums(
            flashLoanParams.receiverAddress,
            flashLoanParams.assets,
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
            vars.currentAmount = flashLoanParams.amounts[vars.i];
            vars.currentPremium = premiums[vars.i];
            vars.currentATokenAddress = aTokenAddresses[vars.i];

            DataTypes.MiniPoolReserveData storage reserve = reserves[vars.currentAsset];
            if (
                DataTypes.InterestRateMode(flashLoanParams.modes[vars.i])
                    == DataTypes.InterestRateMode.NONE
            ) {
                _handleFlashLoanRepayment(
                    reserve,
                    FlashLoanRepaymentParams({
                        amount: vars.currentAmount,
                        totalPremium: vars.currentPremium,
                        liquidityIndex: reserve.liquidityIndex,
                        asset: vars.currentAsset,
                        aToken: vars.currentATokenAddress,
                        receiverAddress: flashLoanParams.receiverAddress
                    })
                );
            } else {
                // If the user chose to not return the funds, the system checks if there is enough collateral and
                // eventually opens a debt position
                MiniPoolBorrowLogic.executeBorrow(
                    MiniPoolBorrowLogic.ExecuteBorrowParams(
                        vars.currentAsset,
                        msg.sender,
                        flashLoanParams.onBehalfOf,
                        vars.currentAmount,
                        vars.currentATokenAddress,
                        0,
                        0,
                        0,
                        false,
                        flashLoanParams.addressesProvider,
                        flashLoanParams.reservesCount
                    ),
                    false,
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

    function getATokenAdressesAndPremiums(
        address receiverAddress,
        address[] memory assets,
        uint256[] memory amounts,
        uint256 _flashLoanPremiumTotal,
        uint256[] memory modes,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves
    ) internal returns (address[] memory aTokenAddresses, uint256[] memory premiums) {
        aTokenAddresses = new address[](assets.length);
        premiums = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            DataTypes.MiniPoolReserveData storage reserve = reserves[assets[i]];
            aTokenAddresses[i] = reserve.aTokenAddress;

            premiums[i] = DataTypes.InterestRateMode(modes[i]) == DataTypes.InterestRateMode.NONE
                ? amounts[i] * _flashLoanPremiumTotal / 10000
                : 0;

            IAERC6909 aToken6909 = IAERC6909(aTokenAddresses[i]);
            aToken6909.transferUnderlyingTo(receiverAddress, reserve.aTokenID, amounts[i], false);
        }
    }

    /**
     * @notice Handles repayment of flashloaned assets + premium
     * @dev Will pull the amount + premium from the receiver, so must have approved pool
     * @param reserve The state of the flashloaned reserve
     * @param params The additional parameters needed to execute the repayment function
     */
    function _handleFlashLoanRepayment(
        DataTypes.MiniPoolReserveData storage reserve,
        FlashLoanRepaymentParams memory params
    ) internal {
        uint256 amountPlusPremium = params.amount + params.totalPremium;

        reserve.updateState();

        uint256 id = reserve.aTokenID;
        reserve.cumulateToLiquidityIndex(
            IAERC6909(params.aToken).totalSupply(id), params.totalPremium
        );

        reserve.updateInterestRates(params.asset, amountPlusPremium, 0);

        IERC20(params.asset).safeTransferFrom(
            params.receiverAddress, params.aToken, amountPlusPremium
        );

        IAERC6909(params.aToken).handleRepayment(
            params.receiverAddress, params.receiverAddress, id, amountPlusPremium
        );

        emit FlashLoan(
            params.receiverAddress,
            msg.sender,
            params.asset,
            DataTypes.InterestRateMode(0),
            params.amount,
            params.totalPremium
        );
    }
}
