// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {
    ILendingPoolAddressesProvider
} from "../../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {
    SafeERC20
} from "../../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {
    ReserveConfiguration
} from "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {
    UserConfiguration
} from "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {
    EnumerableSet
} from "../../../../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title DepositLogic library
 * @author Conclave
 * @notice Implements the core deposit logic for the Astera protocol.
 * @dev Contains functions to handle deposits of assets into the protocol and related events.
 */
library DepositLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev Emitted when a deposit is made to a reserve.
     * @param reserve The address of the reserve receiving the deposit.
     * @param user The address initiating the deposit.
     * @param onBehalfOf The address that will receive the aTokens.
     * @param amount The amount being deposited.
     */
    event Deposit(
        address indexed reserve, address user, address indexed onBehalfOf, uint256 amount
    );

    /**
     * @dev Emitted when a reserve is enabled as collateral for a user.
     * @param reserve The address of the reserve enabled as collateral.
     * @param user The address of the user enabling the reserve as collateral.
     */
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

    /**
     * @dev Struct containing parameters for deposit operations.
     * @param asset The address of the underlying asset to deposit.
     * @param reserveType Boolean indicating if reserve is boosted by a vault.
     * @param amount The amount to deposit.
     * @param onBehalfOf The address that will receive the aTokens.
     */
    struct DepositParams {
        address asset;
        bool reserveType;
        uint256 amount;
        address onBehalfOf;
    }

    /**
     * @notice Deposits an `amount` of underlying asset into the reserve.
     * @dev Emits a `Deposit` event and possibly a `ReserveUsedAsCollateralEnabled` event.
     * @param params The parameters for the deposit operation.
     * @param _reserves The mapping of reserve data.
     * @param _usersConfig The mapping of user configuration data.
     */
    function deposit(
        DepositParams memory params,
        EnumerableSet.AddressSet storage minipoolFlowBorrowing,
        mapping(
            address => mapping(bool => DataTypes.ReserveData)
        ) storage _reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig,
        ILendingPoolAddressesProvider
    ) external {
        DataTypes.ReserveData storage reserve = _reserves[params.asset][params.reserveType];

        ValidationLogic.validateDeposit(reserve, params.amount);

        address aToken = reserve.aTokenAddress;

        reserve.updateState();
        reserve.updateInterestRates(minipoolFlowBorrowing, params.asset, aToken, params.amount, 0);

        IERC20(params.asset).safeTransferFrom(msg.sender, aToken, params.amount);

        bool isFirstDeposit =
            IAToken(aToken).mint(params.onBehalfOf, params.amount, reserve.liquidityIndex);

        if (isFirstDeposit) {
            _usersConfig[params.onBehalfOf].setUsingAsCollateral(reserve.id, true);
            emit ReserveUsedAsCollateralEnabled(params.asset, params.onBehalfOf);
        }

        emit Deposit(params.asset, msg.sender, params.onBehalfOf, params.amount);
    }
}
