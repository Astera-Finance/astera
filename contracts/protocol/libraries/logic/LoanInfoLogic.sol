// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {SafeMath} from "../../../dependencies/openzeppelin/contracts/SafeMath.sol";
import {IERC20} from "../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IAToken} from "../../../interfaces/IAToken.sol";
import {IVariableDebtToken} from "../../../interfaces/IVariableDebtToken.sol";
import {IReserveInterestRateStrategy} from "../../../interfaces/IReserveInterestRateStrategy.sol";
import {ReserveConfiguration} from "../configuration/ReserveConfiguration.sol";
import {ReserveBorrowConfiguration} from "../configuration/ReserveBorrowConfiguration.sol";
import {MathUtils} from "../math/MathUtils.sol";
import {WadRayMath} from "../math/WadRayMath.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {Errors} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title LoanInfoLogic library
 * @author Granary
 * @notice Implements the logic to save information of Loans
 */
library LoanInfoLogic {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;

    struct LoanInfoParams {
        uint256 i;
    }

    struct updateLoanDataLocalVars {
        uint8 i;
        uint256 loanID;
    }

    /**
     * @struct Struct for parameters needed to update loan data
     * @dev This struct is used to pass multiple parameters to the updateLoanData function
     *
     * @param collaterals An array of addresses representing the collateral assets for the loan
     * @param debts An array of addresses representing the debt assets for the loans
     *        this param is length 1 for relationLoans and can be >1 for the general loan cases
     * @param amountsCollateral An array of uint256 representing the amounts of each collateral asset
     * @param amountsBorrowed An array of uint256 representing the amounts borrowed for each loan
     * @param liquidityIndexes An array of uint128 representing the liquidity index for each loan,
     *        used to keep track of the true amount of asset allocated to a loan
     * @param variableBorrowIndexes An array of uint128 representing the variable borrow index for each loaned assed,
     *        used to keep track of the true amount of asset borrowed for a loan
     * @param ltvs An array of uint16 representing the Loan-to-Value (LTV) ratio for each loan
     * @param liquidationThresholds An array of uint16 representing the liquidation threshold for each loan
     */
    struct updateLoanDataParams {
        address[] collaterals;
        address[] debts;
        uint256[] amountsCollateral;
        uint256[] amountsBorrowed;
        uint128[] liquidityIndexes;
        uint128[] variableBorrowIndexes;
        uint16[] ltvs;
        uint16[] liquidationThresholds;
        address user;
        bool relationLoan;
        bool updateLoan;
    }

    error LOAN_DOES_NOT_EXIST();
    error LOAN_ALREADY_EXISTS();
    error LOAN_NOT_RELATION();

    function updateLoanData(
        mapping(address => mapping(uint256 => DataTypes.LoanInfo)) storage _userLoanInfo,
        mapping(address => uint8) storage _userLoanInfoCount,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage _reserves,
        updateLoanDataParams memory params
    ) internal returns (bool) {
        updateLoanDataLocalVars memory vars;
        if (params.updateLoan) {
            vars.i = 0;
            uint256 length = _userLoanInfoCount[params.user];
            for (vars.i; vars.i < length; vars.i++) {
                if (
                    _userLoanInfo[params.user][vars.i].debtInfo.debtSnapshots[0].reserveID
                        == getReserveIdByAddress(_reserves, params.debts[0])
                ) {
                    if (!params.relationLoan) {
                        if (
                            _userLoanInfo[params.user][vars.i].debtInfo.debtSnapshots[1].reserveID
                                == getReserveIdByAddress(_reserves, params.debts[1])
                        ) {
                            vars.loanID = vars.i;
                            break;
                        }
                    }
                    vars.loanID = vars.i;
                    break;
                }
            }
            //revert(Errors.LOAN_DOES_NOT_EXIST);
        }

        if (vars.loanID != 0) {
            vars.loanID = _userLoanInfoCount[params.user] + 1;
            _userLoanInfoCount[params.user] = uint8(vars.loanID);
        }
        vars.i = 0;
        uint256 length = params.collaterals.length;
        //uint8[] memory rankedIDs = rankIDs(params.ltvs);

        DataTypes.LoanInfo storage loanInfo = _userLoanInfo[params.user][vars.loanID];
        loanInfo.relation = params.relationLoan;
        //loanInfo.collateralInfo.collateralSnapshots = new DataTypes.snapshot[](length);
        //loanInfo.debtInfo.debtSnapshots = new DataTypes.snapshot[](params.debts.length);

        for (vars.i; vars.i < length; vars.i++) {
            loanInfo.collateralInfo.collateralSnapshots[vars.i].reserveID =
                getReserveIdByAddress(_reserves, params.collaterals[vars.i]);
            loanInfo.collateralInfo.collateralSnapshots[vars.i].usedLTV = params.ltvs[vars.i];
            loanInfo.collateralInfo.collateralSnapshots[vars.i].usedLiquidationThreshold =
                params.liquidationThresholds[vars.i];
            loanInfo.collateralInfo.collateralSnapshots[vars.i].index =
                params.liquidityIndexes[vars.i];
            loanInfo.collateralInfo.collateralSnapshots[vars.i].amount =
                params.amountsCollateral[vars.i];
            loanInfo.collateralInfo.numCollateral = vars.i + 1;
            if (vars.i < params.debts.length) {
                loanInfo.debtInfo.debtSnapshots[vars.i].reserveID =
                    getReserveIdByAddress(_reserves, params.debts[vars.i]);
                loanInfo.debtInfo.debtSnapshots[vars.i].index = params.variableBorrowIndexes[vars.i];
                loanInfo.debtInfo.debtSnapshots[vars.i].amount = params.amountsBorrowed[vars.i];
                loanInfo.debtInfo.numDebt = vars.i + 1;
            }
        }
        return true;
    }

    function getReserveIdByAddress(
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage _reserves,
        address asset
    ) internal view returns (uint8) {
        return _reserves[asset][false].id;
    }
}
