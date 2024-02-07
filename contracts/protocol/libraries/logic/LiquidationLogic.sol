// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {ILendingPoolAddressesProvider} from '../../../interfaces/ILendingPoolAddressesProvider.sol';
import {Errors} from '../helpers/Errors.sol';

library LiquidationLogic {

    struct liquidationCallParams {
        address collateralAsset;
        bool collateralAssetType;
        address debtAsset;
        bool debtAssetType;
        address user;
        uint256 debtToCover;
        bool receiveAToken;
        address _addressesProvider;
    }

    function liquidationCall(
        liquidationCallParams memory params
    ) external {
        address collateralManager = ILendingPoolAddressesProvider(params._addressesProvider).getLendingPoolCollateralManager();

        //solium-disable-next-line
        (bool success, bytes memory result) =
        collateralManager.delegatecall(
            abi.encodeWithSignature(
            'liquidationCall(address,bool,address,bool,address,uint256,bool)',
            params.collateralAsset,
            params.collateralAssetType,
            params.debtAsset,
            params.debtAssetType,
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