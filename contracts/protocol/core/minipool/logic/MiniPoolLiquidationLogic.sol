// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";

/**
 * @title MiniPoolLiquidationLogic
 * @author Cod3x
 */
library MiniPoolLiquidationLogic {
    struct liquidationCallParams {
        address collateralAsset;
        address debtAsset;
        address user;
        uint256 debtToCover;
        bool receiveAToken;
        address _addressesProvider;
    }

    function liquidationCall(liquidationCallParams memory params) external {
        address collateralManager =
            IMiniPoolAddressesProvider(params._addressesProvider).getMiniPoolCollateralManager();

        //solium-disable-next-line
        (bool success, bytes memory result) = collateralManager.delegatecall(
            abi.encodeWithSignature(
                "liquidationCall(address,bool,address,bool,address,uint256,bool)",
                params.collateralAsset,
                true,
                params.debtAsset,
                true,
                params.user,
                params.debtToCover,
                params.receiveAToken
            )
        );

        require(success, Errors.LP_LIQUIDATION_CALL_FAILED);

        (uint256 returnCode, string memory returnMessage) = abi.decode(result, (uint256, string));

        require(returnCode == 0, string(abi.encodePacked(returnMessage)));
    }
}
