// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IAERC6909} from "../../../../../contracts/interfaces/IAERC6909.sol";
import {ReserveConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {UserConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {MiniPoolValidationLogic} from "./MiniPoolValidationLogic.sol";
import {MiniPoolReserveLogic} from "./MiniPoolReserveLogic.sol";
import {ILendingPool} from "../../../../../contracts/interfaces/ILendingPool.sol";
import {ATokenNonRebasing} from
    "../../../../../contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";

/**
 * @title Deposit Logic library
 * @notice Implements the logic to deposit assets into the protocol
 * @author Cod3x
 */
library MiniPoolDepositLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    event Deposit(
        address indexed reserve, address user, address indexed onBehalfOf, uint256 amount
    );

    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

    struct DepositParams {
        address asset;
        uint256 amount;
        address onBehalfOf;
    }

    function deposit(
        DepositParams memory params,
        bool wrap,
        mapping(address => DataTypes.MiniPoolReserveData) storage _reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig,
        IMiniPoolAddressesProvider _addressesProvider
    ) external {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[params.asset];

        MiniPoolValidationLogic.validateDeposit(reserve, params.amount);

        address aToken = reserve.aTokenAddress;

        reserve.updateState();
        reserve.updateInterestRates(params.asset, params.amount, 0);

        if (wrap) {
            address underlying = ATokenNonRebasing(params.asset).UNDERLYING_ASSET_ADDRESS();
            address lendingPool = _addressesProvider.getLendingPool();
            uint256 underlyingAmount =
                ATokenNonRebasing(params.asset).convertToAssets(params.amount);

            IERC20(underlying).safeTransferFrom(msg.sender, address(this), underlyingAmount);
            IERC20(underlying).forceApprove(lendingPool, underlyingAmount);
            ILendingPool(lendingPool).deposit(underlying, true, underlyingAmount, aToken);
        } else {
            IERC20(params.asset).safeTransferFrom(msg.sender, aToken, params.amount);
        }

        bool isFirstDeposit = IAERC6909(reserve.aTokenAddress).mint(
            msg.sender, params.onBehalfOf, reserve.aTokenID, params.amount, reserve.liquidityIndex
        );

        if (isFirstDeposit) {
            _usersConfig[params.onBehalfOf].setUsingAsCollateral(reserve.id, true);
            emit ReserveUsedAsCollateralEnabled(params.asset, params.onBehalfOf);
        }

        emit Deposit(params.asset, msg.sender, params.onBehalfOf, params.amount);
    }

    function internalDeposit(
        DepositParams memory params,
        mapping(address => DataTypes.MiniPoolReserveData) storage _reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage,
        IMiniPoolAddressesProvider
    ) external {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[params.asset];

        MiniPoolValidationLogic.validateDeposit(reserve, params.amount);

        address aToken = reserve.aTokenAddress;

        reserve.updateState();
        reserve.updateInterestRates(params.asset, params.amount, 0);

        IERC20(params.asset).safeTransfer(aToken, params.amount);

        IAERC6909(reserve.aTokenAddress).mint(
            address(this), address(this), reserve.aTokenID, params.amount, reserve.liquidityIndex
        );

        emit Deposit(params.asset, address(this), address(this), params.amount);
    }
}
