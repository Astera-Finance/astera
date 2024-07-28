// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IPriceOracleGetter} from "../../../../interfaces/IPriceOracleGetter.sol";
import {IMiniPoolAddressesProvider} from "../../../../interfaces/IMiniPoolAddressesProvider.sol";
import {IAToken} from "../../../../interfaces/IAToken.sol";
import {IVariableDebtToken} from "../../../../interfaces/IVariableDebtToken.sol";
import {SafeMath} from "../../../../dependencies/openzeppelin/contracts/SafeMath.sol";
import {WadRayMath} from "../../../libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../libraries/math/PercentageMath.sol";
import {Errors} from "../../../libraries/helpers/Errors.sol";
import {DataTypes} from "../../../libraries/types/DataTypes.sol";
import {MiniPoolGenericLogic} from "./MiniPoolGenericLogic.sol";
import {MiniPoolReserveLogic} from "./MiniPoolReserveLogic.sol";
import {MiniPoolValidationLogic} from "./MiniPoolValidationLogic.sol";
import {ReserveConfiguration} from "../../../libraries/configuration/ReserveConfiguration.sol";
import {ReserveBorrowConfiguration} from
    "../../../libraries/configuration/ReserveBorrowConfiguration.sol";
import {UserConfiguration} from "../../../libraries/configuration/UserConfiguration.sol";
import {UserRecentBorrow} from "../../../libraries/configuration/UserRecentBorrow.sol";
import {Helpers} from "../../../libraries/helpers/Helpers.sol";
import {IFlashLoanReceiver} from "../../../../flashloan/interfaces/IFlashLoanReceiver.sol"; // Add this line
import {MiniPoolBorrowLogic} from "./MiniPoolBorrowLogic.sol";

library MiniPoolFlashLoanLogic {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    struct FlashLoanLocalVars {
        IFlashLoanReceiver receiver;
        address oracle;
        uint256 i;
        address currentAsset;
        bool currentType;
        address currentATokenAddress;
        uint256 currentAmount;
        uint256 currentPremium;
        uint256 currentAmountPlusPremium;
        address debtToken;
    }

    struct FlashLoanParams {
        address receiverAddress;
        address[] assets;
        bool[] reserveTypes;
        address onBehalfOf;
        IMiniPoolAddressesProvider addressesProvider;
        uint256 reservesCount;
        uint256 flashLoanPremiumTotal;
        uint256[] amounts;
        uint256[] modes;
        bytes params;
    }

    event FlashLoan(
        address indexed target,
        address indexed initiator,
        address indexed asset,
        uint256 amount,
        uint256 premium
    );

    /**
     * @dev Allows smartcontracts to access the liquidity of the pool within one transaction,
     * as long as the amount taken plus a fee is returned.
     * IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.
     * For further details please visit https://developers.aave.com
     * @param flashLoanParams struct containing receiverAddress, onBehalfOf, assets, amounts
     *
     */
    function flashLoan(
        FlashLoanParams memory flashLoanParams,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(address => DataTypes.UserRecentBorrowMap) storage usersRecentBorrow,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves
    ) internal {
        FlashLoanLocalVars memory vars;

        MiniPoolValidationLogic.validateFlashloan(flashLoanParams.assets, flashLoanParams.amounts); //@todo add types array to this funciton too

        address[] memory aTokenAddresses = new address[](flashLoanParams.assets.length);
        uint256[] memory premiums = new uint256[](flashLoanParams.assets.length);

        vars.receiver = IFlashLoanReceiver(flashLoanParams.receiverAddress);

        (aTokenAddresses, premiums) = getATokenAdressesAndPremiums(
            flashLoanParams.receiverAddress,
            flashLoanParams.assets,
            flashLoanParams.amounts,
            flashLoanParams.flashLoanPremiumTotal,
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
                reserves[vars.currentAsset].updateState();
                reserves[vars.currentAsset].cumulateToLiquidityIndex(
                    IERC20(vars.currentATokenAddress).totalSupply(), vars.currentPremium
                );
                reserves[vars.currentAsset].updateInterestRates(
                    vars.currentAsset, vars.currentAmount.add(vars.currentPremium), 0
                );

                IERC20(vars.currentAsset).safeTransferFrom(
                    flashLoanParams.receiverAddress,
                    vars.currentATokenAddress,
                    vars.currentAmount.add(vars.currentPremium)
                );
            } else {
                // If the user chose to not return the funds, the system checks if there is enough collateral and
                // eventually opens a debt position
                MiniPoolBorrowLogic.executeBorrow(
                    MiniPoolBorrowLogic.ExecuteBorrowParams(
                        vars.currentAsset,
                        vars.currentType,
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
                    reserves,
                    reservesList,
                    usersConfig,
                    usersRecentBorrow
                );
            }
            emit FlashLoan(
                flashLoanParams.receiverAddress,
                msg.sender,
                vars.currentAsset,
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
        mapping(address => DataTypes.MiniPoolReserveData) storage _reserves
    ) internal returns (address[] memory aTokenAddresses, uint256[] memory premiums) {
        for (uint256 i = 0; i < assets.length; i++) {
            aTokenAddresses[i] = _reserves[assets[i]].aTokenAddress;

            premiums[i] = amounts[i].mul(_flashLoanPremiumTotal).div(10000);

            IAToken(aTokenAddresses[i]).transferUnderlyingTo(receiverAddress, amounts[i]);
        }
        //@audit still wont work
    }
}
