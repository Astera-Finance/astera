// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20Detailed} from
    "../../contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {IAToken} from "../../contracts/interfaces/IAToken.sol";
import {IMiniPool} from "../../contracts/interfaces/IMiniPool.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {ATokenERC6909} from "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

/**
 * @title Liquidator
 * @author Conclave
 * @notice Implements the liquidation logic of the protocol
 */
contract Liquidator is UUPSUpgradeable, Initializable {
    error LiquidatorCallerNotAuthorizedLiquidator();
    error LiquidatorOnlyOwner();

    struct UsdCollateralAndDebt {
        address[] collateralTokens;
        uint256[] collateralAmount;
        uint256 userUsdCollateral;
        address[] debtTokens;
        uint256[] debtAmount;
        uint256 userUsdDebt;
    }

    IMiniPoolAddressesProvider public miniPoolAddressesProvider =
        IMiniPoolAddressesProvider(0x9399aF805e673295610B17615C65b9d0cE1Ed306);
    mapping(address => bool) public authorizedLiquidators;

    modifier onlyAuthorizedLiquidator() {
        if (!authorizedLiquidators[msg.sender]) {
            revert LiquidatorCallerNotAuthorizedLiquidator();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != miniPoolAddressesProvider.getMainPoolAdmin()) {
            revert LiquidatorOnlyOwner();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    function calculateLiquidationParams(address user, address debtTokenToRepay, address miniPool)
        public
        view
        returns (uint256 amountToLiquidate, address[] memory collateralTokens)
    {
        UsdCollateralAndDebt memory userCollateralAndDebt =
            calculateUserCollateraAndDebtInUsd(user, miniPool);
        for (uint256 idx = 0; idx < userCollateralAndDebt.debtTokens.length; idx++) {
            if (userCollateralAndDebt.debtTokens[idx] == debtTokenToRepay) {
                amountToLiquidate = userCollateralAndDebt.debtAmount[idx];
            }
        }
        collateralTokens = userCollateralAndDebt.collateralTokens;
    }

    function calculateUserCollateraAndDebtInUsd(address user, address miniPool)
        public
        view
        returns (UsdCollateralAndDebt memory userCollateralAndDebt)
    {
        uint256 collateralCounter = 0;
        uint256 debtCounter = 0;
        ATokenERC6909 erc6909 =
            ATokenERC6909(miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        (address[] memory reserveList,) = IMiniPool(miniPool).getReservesList();
        userCollateralAndDebt.collateralTokens = new address[](reserveList.length);
        userCollateralAndDebt.collateralAmount = new uint256[](reserveList.length);
        userCollateralAndDebt.debtTokens = new address[](reserveList.length);
        userCollateralAndDebt.debtAmount = new uint256[](reserveList.length);
        for (uint256 idx = 0; idx < reserveList.length; idx++) {
            (uint256 aTokenId, uint256 debtTokenId, bool isTranched) =
                erc6909.getIdForUnderlying(reserveList[idx]);

            userCollateralAndDebt.collateralAmount[idx] = erc6909.balanceOf(user, aTokenId);
            userCollateralAndDebt.debtAmount[idx] = erc6909.balanceOf(user, debtTokenId);
            if (userCollateralAndDebt.collateralAmount[idx] > 0) {
                if (isTranched) {
                    userCollateralAndDebt.collateralTokens[collateralCounter] =
                        IAToken(reserveList[idx]).UNDERLYING_ASSET_ADDRESS();
                } else {
                    userCollateralAndDebt.collateralTokens[collateralCounter] = reserveList[idx];
                }
                userCollateralAndDebt.collateralAmount[collateralCounter] =
                    userCollateralAndDebt.collateralAmount[idx];
                collateralCounter++;
            }
            if (userCollateralAndDebt.debtAmount[idx] > 0) {
                if (isTranched) {
                    userCollateralAndDebt.debtTokens[debtCounter] =
                        IAToken(reserveList[idx]).UNDERLYING_ASSET_ADDRESS();
                } else {
                    userCollateralAndDebt.debtTokens[debtCounter] = reserveList[idx];
                }
                userCollateralAndDebt.debtAmount[debtCounter] =
                    userCollateralAndDebt.debtAmount[idx];
                debtCounter++;
            }
        }
        (userCollateralAndDebt.userUsdCollateral, userCollateralAndDebt.userUsdDebt,,,,) =
            IMiniPool(miniPool).getUserAccountData(user);
        return userCollateralAndDebt;
    }

    function liquidate(address user, address collateralToken, address debtToken, address miniPool)
        public
        onlyAuthorizedLiquidator
    {
        ATokenERC6909 erc6909 =
            ATokenERC6909(miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        (,, bool isCollateralTranched) = erc6909.getIdForUnderlying(collateralToken);
        (,, bool isDebtTranched) = erc6909.getIdForUnderlying(debtToken);

        (uint256 amountToLiquidate,) = calculateLiquidationParams(user, debtToken, miniPool);

        if (isDebtTranched) {
            IERC20Detailed(IAToken(debtToken).UNDERLYING_ASSET_ADDRESS()).transferFrom(
                msg.sender, address(this), amountToLiquidate
            );
        } else {
            IERC20Detailed(debtToken).transferFrom(msg.sender, address(this), amountToLiquidate);
        }

        IERC20Detailed(debtToken).approve(miniPool, amountToLiquidate);
        IMiniPool(miniPool).liquidationCall(
            collateralToken, true, debtToken, true, user, amountToLiquidate, false
        );

        // Transfer all fuds back to sender
        if (
            isCollateralTranched
                && (
                    IERC20Detailed(IAToken(collateralToken).UNDERLYING_ASSET_ADDRESS()).balanceOf(
                        msg.sender
                    ) > 0
                )
        ) {
            IERC20Detailed(collateralToken).transfer(
                msg.sender,
                IERC20Detailed(IAToken(collateralToken).UNDERLYING_ASSET_ADDRESS()).balanceOf(
                    address(this)
                )
            );
        }
        if ((IERC20Detailed(collateralToken).balanceOf(address(this)) > 0)) {
            IERC20Detailed(collateralToken).transfer(
                msg.sender, IERC20Detailed(collateralToken).balanceOf(address(this))
            );
        }
        if (
            isDebtTranched
                && (
                    IERC20Detailed(IAToken(collateralToken).UNDERLYING_ASSET_ADDRESS()).balanceOf(
                        msg.sender
                    ) > 0
                )
        ) {
            IERC20Detailed(debtToken).transfer(
                msg.sender,
                IERC20Detailed(IAToken(collateralToken).UNDERLYING_ASSET_ADDRESS()).balanceOf(
                    address(this)
                )
            );
        }
        if ((IERC20Detailed(debtToken).balanceOf(address(this)) > 0)) {
            IERC20Detailed(debtToken).transfer(
                msg.sender, IERC20Detailed(debtToken).balanceOf(address(this))
            );
        }
    }

    function withdrawERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20Detailed(token).transfer(to, amount);
    }

    function setAuthorizedLiquidator(address liquidator, bool authorized) external onlyOwner {
        authorizedLiquidators[liquidator] = authorized;
    }
}
