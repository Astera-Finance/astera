// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {Ownable} from "../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {IERC20} from "../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IWETH} from "../../contracts/interfaces/base/IWETH.sol";
import {IWETHGateway} from "../../contracts/interfaces/base/IWETHGateway.sol";
import {ILendingPool} from "../../contracts/interfaces/ILendingPool.sol";
import {IMiniPool} from "../../contracts/interfaces/IMiniPool.sol";
import {IAToken} from "../../contracts/interfaces/IAToken.sol";
import {ReserveConfiguration} from
    "../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {Helpers} from "../../contracts/protocol/libraries/helpers/Helpers.sol";
import {DataTypes} from "../../contracts/protocol/libraries/types/DataTypes.sol";
import {IAERC6909} from "../../contracts/interfaces/IAERC6909.sol";
/**
 * @title WETHGateway
 * @author Conclave
 */

contract WETHGateway is IWETHGateway, Ownable {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    IAToken public immutable AWETH;
    IWETH public immutable WETH;

    event WethGatewayReceived(address indexed sender, uint256 amount);

    /**
     * @dev Sets the WETH address and the LendingPoolAddressesProvider address. Infinite approves lending pool.
     * @param aWeth Address of the Wrapped Ether contract
     */
    constructor(address aWeth) Ownable(msg.sender) {
        AWETH = IAToken(aWeth);
        WETH = IWETH(IAToken(aWeth).UNDERLYING_ASSET_ADDRESS());
    }

    /**
     * @dev Authorizes the LendingPool to spend WETH on behalf of the contract.
     * @param lendingPool Address of the LendingPool to authorize
     */
    function authorizeLendingPool(address lendingPool) external onlyOwner {
        WETH.approve(lendingPool, type(uint256).max);
    }

    /**
     * @dev Authorizes the MiniPool to spend WETH on behalf of the contract.
     * @param miniPool Address of the MiniPool to authorize
     */
    function authorizeMiniPool(address miniPool) external onlyOwner {
        WETH.approve(miniPool, type(uint256).max);
    }

    /**
     * @dev deposits WETH into the reserve, using native ETH. A corresponding amount of the overlying asset (aTokens)
     * is minted.
     * @param lendingPool address of the targeted underlying lending pool
     * @param reserveType boolean indicating the type of reserve
     * @param onBehalfOf address of the user who will receive the aTokens representing the deposit
     */
    function depositETH(address lendingPool, bool reserveType, address onBehalfOf)
        external
        payable
        override
    {
        WETH.deposit{value: msg.value}();
        ILendingPool(lendingPool).deposit(address(WETH), reserveType, msg.value, onBehalfOf);
    }

    /**
     * @dev Deposits ETH into the MiniPool, converting it to WETH and minting aTokens.
     * @param miniPool Address of the MiniPool
     * @param wrap boolean indicating whether to wrap the ETH into aTokens
     * @param onBehalfOf Address of the user who will receive the aTokens
     */
    function depositETHMiniPool(address miniPool, bool wrap, address onBehalfOf)
        external
        payable
        override
    {
        WETH.deposit{value: msg.value}();
        if (wrap) {
            IMiniPool(miniPool).deposit(
                address(AWETH), true, AWETH.convertToShares(msg.value), onBehalfOf
            ); // AWETH amount is decreased by the index
        } else {
            IMiniPool(miniPool).deposit(address(WETH), false, msg.value, onBehalfOf);
        }
    }

    /**
     * @dev withdraws the WETH reserves of msg.sender.
     * @param lendingPool address of the targeted underlying lending pool
     * @param reserveType boolean indicating the type of reserve
     * @param amount amount of aWETH to withdraw and receive native ETH
     * @param to address of the user who will receive native ETH
     */
    function withdrawETH(address lendingPool, bool reserveType, uint256 amount, address to)
        external
        override
    {
        IAToken aWETH = IAToken(
            ILendingPool(lendingPool).getReserveData(address(WETH), reserveType).aTokenAddress
        );

        uint256 amountToWithdraw;

        // if amount is equal to uint(-1), the user wants to redeem everything
        if (amount == type(uint256).max) {
            uint256 userBalance = aWETH.balanceOf(msg.sender);
            amountToWithdraw = userBalance;
        } else {
            amountToWithdraw = amount;
        }
        aWETH.transferFrom(msg.sender, address(this), amountToWithdraw);
        ILendingPool(lendingPool).withdraw(
            address(WETH), reserveType, amountToWithdraw, address(this)
        );
        WETH.withdraw(amountToWithdraw);
        _safeTransferETH(to, amountToWithdraw);
    }

    /**
     * @dev Withdraws ETH from the MiniPool by redeeming aTokens.
     * @param miniPool Address of the MiniPool
     * @param amount Amount of aTokens to withdraw (use uint256.max to withdraw all)
     * @param wrap boolean indicating whether to unwrap the aTokens into ETH
     * @param to Address to receive the withdrawn ETH
     */
    function withdrawETHMiniPool(address miniPool, uint256 amount, bool wrap, address to)
        external
    {
        if (wrap) {
            DataTypes.MiniPoolReserveData memory miniPoolReserveData =
                IMiniPool(miniPool).getReserveData(address(AWETH));

            uint256 amountToWithdraw;

            if (amount == type(uint256).max) {
                uint256 userBalance = IAERC6909(miniPoolReserveData.aErc6909).balanceOf(
                    msg.sender, miniPoolReserveData.aTokenID
                );
                amountToWithdraw = userBalance;
            } else {
                amountToWithdraw = amount;
            }
            IAERC6909(miniPoolReserveData.aErc6909).transferFrom(
                msg.sender,
                address(this),
                miniPoolReserveData.aTokenID,
                AWETH.convertToShares(amountToWithdraw)
            ); // transfer aToken shares
            IMiniPool(miniPool).withdraw(
                address(AWETH), true, AWETH.convertToShares(amountToWithdraw), address(this)
            );
            WETH.withdraw(amountToWithdraw);
            _safeTransferETH(to, amountToWithdraw);
        } else {
            DataTypes.MiniPoolReserveData memory miniPoolReserveData =
                IMiniPool(miniPool).getReserveData(address(WETH));

            uint256 amountToWithdraw;

            if (amount == type(uint256).max) {
                uint256 userBalance = IAERC6909(miniPoolReserveData.aErc6909).balanceOf(
                    msg.sender, miniPoolReserveData.aTokenID
                );
                amountToWithdraw = userBalance;
            } else {
                amountToWithdraw = amount;
            }
            IAERC6909(miniPoolReserveData.aErc6909).transferFrom(
                msg.sender, address(this), miniPoolReserveData.aTokenID, amountToWithdraw
            );
            IMiniPool(miniPool).withdraw(address(WETH), false, amountToWithdraw, address(this));
            WETH.withdraw(amountToWithdraw);
            _safeTransferETH(to, amountToWithdraw);
        }
    }

    /**
     * @dev repays a borrow on the WETH reserve, for the specified amount (or for the whole amount, if uint256(-1) is specified).
     * @param lendingPool address of the targeted underlying lending pool
     * @param reserveType boolean indicating the type of reserve
     * @param amount the amount to repay, or uint256(-1) if the user wants to repay everything
     * @param onBehalfOf the address for which msg.sender is repaying
     */
    function repayETH(address lendingPool, bool reserveType, uint256 amount, address onBehalfOf)
        external
        payable
        override
    {
        (uint256 variableDebt) = Helpers.getUserCurrentDebtMemory(
            onBehalfOf, ILendingPool(lendingPool).getReserveData(address(WETH), reserveType)
        );

        uint256 paybackAmount = variableDebt;

        if (amount < paybackAmount) {
            paybackAmount = amount;
        }
        require(msg.value >= paybackAmount, "msg.value is less than repayment amount");
        WETH.deposit{value: paybackAmount}();
        ILendingPool(lendingPool).repay(address(WETH), reserveType, msg.value, onBehalfOf);

        // refund remaining dust eth
        if (msg.value > paybackAmount) _safeTransferETH(msg.sender, msg.value - paybackAmount);
    }

    /**
     * @dev Repays a borrow on the MiniPool using ETH.
     * @param miniPool Address of the MiniPool
     * @param amount Amount to repay (use uint256.max to repay all)
     * @param wrap boolean indicating whether to repay using aTokens
     * @param onBehalfOf Address of the user for whom the repayment is made
     */
    function repayETHMiniPool(address miniPool, uint256 amount, bool wrap, address onBehalfOf)
        external
        payable
    {
        uint256 paybackAmount;
        if (wrap) {
            (uint256 variableDebt) = (
                AWETH.convertToAssets(
                    Helpers.getUserCurrentDebtMemory(
                        onBehalfOf, IMiniPool(miniPool).getReserveData(address(AWETH))
                    )
                )
            ); // variable debt in underlying assets -> convert to assets

            if (amount < variableDebt) {
                paybackAmount = amount;
            } else {
                paybackAmount = variableDebt;
            }
            require(msg.value >= paybackAmount, "msg.value is less than repayment amount");
            WETH.deposit{value: paybackAmount}();
            IMiniPool(miniPool).repay(
                address(AWETH), true, AWETH.convertToShares(msg.value), onBehalfOf
            );
        } else {
            (uint256 variableDebt) = Helpers.getUserCurrentDebtMemory(
                onBehalfOf, IMiniPool(miniPool).getReserveData(address(WETH))
            );

            if (amount < paybackAmount) {
                paybackAmount = amount;
            } else {
                paybackAmount = variableDebt;
            }
            require(msg.value >= paybackAmount, "msg.value is less than repayment amount");
            WETH.deposit{value: paybackAmount}();
            IMiniPool(miniPool).repay(address(WETH), false, msg.value, onBehalfOf);
        }

        // refund remaining dust eth
        if (msg.value > paybackAmount) _safeTransferETH(msg.sender, msg.value - paybackAmount);
    }

    /**
     * @dev borrow WETH, unwraps to ETH and send both the ETH and DebtTokens to msg.sender, via `approveDelegation` and onBehalf argument in `LendingPool.borrow`.
     * @param lendingPool address of the targeted underlying lending pool
     * @param reserveType boolean indicating the type of reserve
     * @param amount the amount of ETH to borrow
     */
    function borrowETH(address lendingPool, bool reserveType, uint256 amount) external override {
        ILendingPool(lendingPool).borrow(address(WETH), reserveType, amount, msg.sender);
        WETH.withdraw(amount);
        _safeTransferETH(msg.sender, amount);
    }

    /**
     * @dev Borrows ETH from the MiniPool by taking a debt position.
     * @param miniPool Address of the MiniPool
     * @param amount Amount of ETH to borrow
     * @param wrap boolean indicating whether to borrow using aTokens
     */
    function borrowETHMiniPool(address miniPool, uint256 amount, bool wrap) external {
        if (wrap) {
            IMiniPool(miniPool).borrow(
                address(AWETH), true, AWETH.convertToShares(amount), msg.sender
            );
        } else {
            IMiniPool(miniPool).borrow(address(WETH), false, amount, msg.sender);
        }
        WETH.withdraw(amount);
        _safeTransferETH(msg.sender, amount);
    }

    /**
     * @dev transfer ETH to an address, revert if it fails.
     * @param to recipient of the transfer
     * @param value the amount to send
     */
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "ETH_TRANSFER_FAILED");
    }

    /**
     * @dev transfer ERC20 from the utility contract, for ERC20 recovery in case of stuck tokens due
     * direct transfers to the contract address.
     * @param token token to transfer
     * @param to recipient of the transfer
     * @param amount amount to send
     */
    function emergencyTokenTransfer(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    /**
     * @dev transfer native Ether from the utility contract, for native Ether recovery in case of stuck Ether
     * due selfdestructs or transfer ether to pre-computated contract address before deployment.
     * @param to recipient of the transfer
     * @param amount amount to send
     */
    function emergencyEtherTransfer(address to, uint256 amount) external onlyOwner {
        _safeTransferETH(to, amount);
    }

    /**
     * @dev Get WETH address used by WETHGateway
     */
    function getWETHAddress() external view returns (address) {
        return address(WETH);
    }

    /**
     * @dev Only WETH contract is allowed to transfer ETH here. Prevent other addresses to send Ether to this contract.
     */
    receive() external payable {
        require(msg.sender == address(WETH), "Receive not allowed");
        emit WethGatewayReceived(msg.sender, msg.value);
    }

    /**
     * @dev Revert fallback calls
     */
    fallback() external payable {
        revert("Fallback not allowed");
    }
}
