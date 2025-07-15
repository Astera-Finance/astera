// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IERC20} from "../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IScaledBalanceToken} from "../../contracts/interfaces/base/IScaledBalanceToken.sol";
import {IInitializableAToken} from "../../contracts/interfaces/base/IInitializableAToken.sol";
import {IRewarder} from "../../contracts/interfaces/IRewarder.sol";

/**
 * @title IAToken interface.
 * @author Conclave
 */
interface IAToken is IERC20, IScaledBalanceToken, IInitializableAToken {
    /**
     * @dev Emitted after the mint action.
     * @param user The address performing the mint.
     * @param amount The amount being.
     * @param index The new liquidity index of the reserve.
     */
    event Mint(address indexed user, uint256 amount, uint256 index);

    /**
     * @dev Emitted after aTokens are burned.
     * @param user The owner of the aTokens, getting them burned.
     * @param target The address that will receive the underlying.
     * @param amount The amount being burned.
     * @param index The new liquidity index of the reserve.
     */
    event Burn(address indexed user, address indexed target, uint256 amount, uint256 index);

    /**
     * @dev Emitted during the transfer action.
     * @param user The user whose tokens are being transferred.
     * @param to The recipient.
     * @param amount The amount being transferred.
     * @param index The new liquidity index of the reserve.
     */
    event BalanceTransfer(address indexed user, address indexed to, uint256 amount, uint256 index);

    /**
     * @dev Emitted during the rebalance action.
     * @param vault The vault that is being interacted with.
     * @param amountToWithdraw The amount of asset that needs to be free after the rebalance.
     * @param netAssetMovement The amount of asset being deposited into (if positive) or withdrawn from (if negative) the vault.
     */
    event Rebalance(address indexed vault, uint256 amountToWithdraw, int256 netAssetMovement);

    /**
     * @dev Emitted when the farming percentage is set.
     * @param farmingPct The new farming percentage.
     */
    event FarmingPctSet(uint256 farmingPct);

    /**
     * @dev Emitted when the claiming threshold is set.
     * @param claimingThreshold The new claiming threshold.
     */
    event ClaimingThresholdSet(uint256 claimingThreshold);

    /**
     * @dev Emitted when the farming percentage drift is set.
     * @param farmingPctDrift The new farming percentage drift.
     */
    event FarmingPctDriftSet(uint256 farmingPctDrift);

    /**
     * @dev Emitted when the profit handler is set.
     * @param profitHandler The new profit handler address.
     */
    event ProfitHandlerSet(address profitHandler);

    /**
     * @dev Emitted when the vault is set.
     * @param vault The new vault address.
     */
    event VaultSet(address vault);

    /**
     * @dev Emitted when the treasury is set.
     * @param treasury The new treasury address.
     */
    event TreasurySet(address treasury);

    /**
     * @dev Emitted when the incentives controller is set.
     * @param incentivesController The new incentives controller address.
     */
    event IncentivesControllerSet(address incentivesController);

    function mint(address user, uint256 amount, uint256 index) external returns (bool);

    function burn(address user, address receiverOfUnderlying, uint256 amount, uint256 index)
        external;

    function mintToCod3xTreasury(uint256 amount, uint256 index) external;

    function transferOnLiquidation(address from, address to, uint256 value) external;

    function transferUnderlyingTo(address user, uint256 amount) external returns (uint256);

    function handleRepayment(address user, address onBehalfOf, uint256 amount) external;

    function getIncentivesController() external view returns (IRewarder);

    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    function RESERVE_TYPE() external view returns (bool);

    /// --------- Share logic ---------

    function transferShare(address from, address to, uint256 shareAmount) external;

    function shareApprove(address owner, address spender, uint256 shareAmount) external;

    function shareAllowances(address owner, address spender) external view returns (uint256);

    function WRAPPER_ADDRESS() external view returns (address);

    function convertToShares(uint256 assetAmount) external view returns (uint256);

    function convertToAssets(uint256 shareAmount) external view returns (uint256);

    /// --------- Rehypothecation logic ---------

    function getTotalManagedAssets() external view returns (uint256);

    function setFarmingPct(uint256 _farmingPct) external;

    function setClaimingThreshold(uint256 _claimingThreshold) external;

    function setFarmingPctDrift(uint256 _farmingPctDrift) external;

    function setProfitHandler(address _profitHandler) external;

    function setVault(address _vault) external;

    function setTreasury(address _treasury) external;

    function setIncentivesController(address _incentivesController) external;

    function rebalance() external;

    function getPool() external view returns (address);
}
