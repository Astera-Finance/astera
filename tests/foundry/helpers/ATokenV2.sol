// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";
import {VersionedInitializable} from
    "contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {IncentivizedERC20} from "contracts/protocol/tokenization/ERC20/IncentivizedERC20.sol";
import {IRewarder} from "contracts/interfaces/IRewarder.sol";
import {IERC4626} from "lib/openzeppelin-contracts/lib/forge-std/src/interfaces/IERC4626.sol";
import {ATokenNonRebasing} from "contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";

/**
 * @title Cod3x Lend ERC20 AToken
 * @notice Implementation of the interest bearing token for the Cod3x Lend protocol.
 * @author Cod3x
 */
contract ATokenV2 is
    VersionedInitializable,
    IncentivizedERC20("ATOKEN_IMPL", "ATOKEN_IMPL", 0),
    IAToken
{
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Constant used for EIP712 domain revision.
    bytes public constant EIP712_REVISION = bytes("1");

    /// @notice EIP712 domain separator data structure hash.
    bytes32 internal constant EIP712_DOMAIN = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    /// @notice EIP712 typehash for permit function.
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    /// @notice Current revision of the AToken implementation.
    uint256 public constant ATOKEN_REVISION = 0x2;

    /// @notice EIP712 domain separator.
    bytes32 public DOMAIN_SEPARATOR;

    /// @notice Flag indicating if the reserve is boosted by a vault.
    bool public RESERVE_TYPE;

    /// @notice Chain ID cached at contract deployment for EIP712 domain separator.
    uint256 public CACHED_CHAIN_ID;

    /// @notice Reference to the `ILendingPool` contract.
    ILendingPool internal _pool;

    /// @notice Address of the treasury receiving fees.
    address internal _treasury;

    /// @notice Address of the underlying asset.
    address internal _underlyingAsset;

    /// @notice Reference to the incentives controller contract.
    IRewarder internal _incentivesController;

    /// @notice Address of the non rebasing AToken wrapper address.
    address internal _aTokenWrapper;

    /// @notice Mapping of share allowances from owner to spender.
    mapping(address => mapping(address => uint256)) internal _shareAllowances;

    /// @notice Mapping of nonces for permit function.
    mapping(address => uint256) public _nonces;

    // ---- Rehypothecation related vars ----

    /// @notice The ERC4626 vault contract that this aToken supplies tokens to for rehypothecation.
    IERC4626 public _vault;
    /// @notice The total amount of underlying tokens that have entered/exited this contract from protocol perspective.
    uint256 public _underlyingAmount;
    /// @notice The percentage of underlying tokens that should be rehypothecated to the vault.
    uint256 public _farmingPct;
    /// @notice The current amount of underlying tokens supplied to the vault.
    uint256 public _farmingBal;
    /// @notice The minimum profit amount that will trigger a claim.
    uint256 public _claimingThreshold;
    /// @notice The minimum percentage difference that will trigger rebalancing.
    uint256 public _farmingPctDrift;
    /// @notice The address that receives claimed profits.
    address public _profitHandler;

    /**
     * @notice Modifier to ensure only the lending pool can call certain functions.
     * @dev Reverts if the caller is not the lending pool contract.
     */
    modifier onlyLendingPool() {
        require(msg.sender == address(_pool), Errors.AT_CALLER_MUST_BE_LENDING_POOL);
        _;
    }

    /**
     * @notice Returns the current revision number of this implementation.
     * @dev Implements the VersionedInitializable interface.
     * @return The revision number of this contract.
     */
    function getRevision() internal pure virtual override returns (uint256) {
        return ATOKEN_REVISION;
    }

    /**
     * @notice Initializes the aToken contract with its core configuration.
     * @dev Sets up the token metadata, pool references, and EIP712 domain separator.
     * @param pool The address of the lending pool where this aToken will be used.
     * @param treasury The address of the Cod3x treasury, receiving the fees on this aToken.
     * @param underlyingAsset The address of the underlying asset of this aToken (E.g. `WETH` for aWETH).
     * @param incentivesController The smart contract managing potential incentives distribution.
     * @param aTokenDecimals The decimals of the aToken, same as the underlying asset's.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param aTokenName The name of the aToken.
     * @param aTokenSymbol The symbol of the aToken.
     * @param params Additional params to configure contract.
     */
    function initialize(
        ILendingPool pool,
        address treasury,
        address underlyingAsset,
        IRewarder incentivesController,
        uint8 aTokenDecimals,
        bool reserveType,
        string calldata aTokenName,
        string calldata aTokenSymbol,
        bytes calldata params
    ) external override initializer {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN,
                keccak256(bytes(aTokenName)),
                keccak256(EIP712_REVISION),
                block.chainid,
                address(this)
            )
        );

        RESERVE_TYPE = reserveType;

        _setName(aTokenName);
        _setSymbol(aTokenSymbol);
        _setDecimals(aTokenDecimals);

        _pool = pool;
        _treasury = treasury;
        _underlyingAsset = underlyingAsset;
        _incentivesController = incentivesController;
        if (_aTokenWrapper == address(0)) {
            _aTokenWrapper = address(new ATokenNonRebasing(address(this)));
        }

        emit Initialized(
            underlyingAsset,
            address(pool),
            _aTokenWrapper,
            _treasury,
            address(incentivesController),
            aTokenDecimals,
            reserveType,
            aTokenName,
            aTokenSymbol,
            params
        );
    }

    /**
     * @notice Burns aTokens and transfers underlying tokens to a specified receiver.
     * @dev Only callable by the LendingPool contract.
     * @param user The owner of the aTokens getting burned.
     * @param receiverOfUnderlying The address that will receive the underlying tokens.
     * @param amount The amount of tokens being burned.
     * @param index The new liquidity index of the reserve.
     */
    function burn(address user, address receiverOfUnderlying, uint256 amount, uint256 index)
        external
        override
        onlyLendingPool
    {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.AT_INVALID_BURN_AMOUNT);
        _rebalance(amount);
        _underlyingAmount = _underlyingAmount - amount;
        _burn(user, amountScaled);

        IERC20(_underlyingAsset).safeTransfer(receiverOfUnderlying, amount);

        emit Transfer(user, address(0), amount);
        emit Burn(user, receiverOfUnderlying, amount, index);
    }

    /**
     * @notice Mints new aTokens to a specified user.
     * @dev Only callable by the LendingPool contract.
     * @param user The address receiving the minted tokens.
     * @param amount The amount of tokens to mint.
     * @param index The new liquidity index of the reserve.
     * @return True if the previous balance of the user was 0.
     */
    function mint(address user, uint256 amount, uint256 index)
        external
        override
        onlyLendingPool
        returns (bool)
    {
        uint256 previousBalance = super.balanceOf(user);

        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.AT_INVALID_MINT_AMOUNT);
        _underlyingAmount = _underlyingAmount + amount;
        _rebalance(0);
        _mint(user, amountScaled);

        emit Transfer(address(0), user, amount);
        emit Mint(user, amount, index);

        return previousBalance == 0;
    }

    /**
     * @notice Mints aTokens to the Cod3x treasury.
     * @dev Only callable by the LendingPool contract. Does not check for rounding errors.
     * @param amount The amount of tokens to mint.
     * @param index The new liquidity index of the reserve.
     */
    function mintToCod3xTreasury(uint256 amount, uint256 index) external override onlyLendingPool {
        if (amount == 0) {
            return;
        }

        address treasury = _treasury;

        // Compared to the normal mint, we don't check for rounding errors.
        // The amount to mint can easily be very small since it is a fraction of the interest accrued.
        // In that case, the treasury will experience a (very small) loss, but it
        // won't cause potentially valid transactions to fail.
        _mint(treasury, amount.rayDiv(index));

        emit Transfer(address(0), treasury, amount);
        emit Mint(treasury, amount, index);
    }

    /**
     * @notice Transfers aTokens during liquidation.
     * @dev Only callable by the LendingPool contract.
     * @param from The address getting liquidated, current owner of the aTokens.
     * @param to The recipient of the aTokens.
     * @param value The amount of tokens being transferred.
     */
    function transferOnLiquidation(address from, address to, uint256 value)
        external
        override
        onlyLendingPool
    {
        // Being a normal transfer, the Transfer() and BalanceTransfer() are emitted
        // so no need to emit a specific event here.
        _transfer(from, to, value, false);

        emit Transfer(from, to, value);
    }

    /**
     * @dev Calculates the balance of the user: principal balance + interest generated by the principal.
     * @param user The user whose balance is calculated.
     * @return The balance of the user.
     */
    function balanceOf(address user)
        public
        view
        override(IncentivizedERC20, IERC20)
        returns (uint256)
    {
        return super.balanceOf(user).rayMul(
            _pool.getReserveNormalizedIncome(_underlyingAsset, RESERVE_TYPE)
        );
    }

    /**
     * @dev Returns the scaled balance of the user. The scaled balance is the sum of all the
     * updated stored balance divided by the reserve's liquidity index at the moment of the update.
     * @param user The user whose balance is calculated.
     * @return The scaled balance of the user.
     */
    function scaledBalanceOf(address user) external view override returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @dev Returns the scaled balance of the user and the scaled total supply.
     * @param user The address of the user.
     * @return The scaled balance of the user.
     * @return The scaled total supply.
     */
    function getScaledUserBalanceAndSupply(address user)
        external
        view
        override
        returns (uint256, uint256)
    {
        return (super.balanceOf(user), super.totalSupply());
    }

    /**
     * @dev Calculates the total supply of the specific aToken.
     * Since the balance of every single user increases over time, the total supply
     * does that too.
     * @return The current total supply.
     */
    function totalSupply() public view override(IncentivizedERC20, IERC20) returns (uint256) {
        uint256 currentSupplyScaled = super.totalSupply();

        if (currentSupplyScaled == 0) {
            return 0;
        }

        return currentSupplyScaled.rayMul(
            _pool.getReserveNormalizedIncome(_underlyingAsset, RESERVE_TYPE)
        );
    }

    /**
     * @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index).
     * @return The scaled total supply.
     */
    function scaledTotalSupply() public view virtual override returns (uint256) {
        return super.totalSupply();
    }

    /// @dev Returns the address of the Cod3x treasury, receiving the fees on this aToken.
    function RESERVE_TREASURY_ADDRESS() public view returns (address) {
        return _treasury;
    }

    /// @dev Returns the address of the underlying asset of this aToken (E.g. `WETH` for aWETH).
    function UNDERLYING_ASSET_ADDRESS() public view override returns (address) {
        return _underlyingAsset;
    }

    /// @dev Returns the address of the lending pool where this aToken is used.
    function POOL() public view returns (ILendingPool) {
        return _pool;
    }

    /// @dev For internal usage in the logic of the parent contract `IncentivizedERC20`.
    function _getIncentivesController() internal view override returns (IRewarder) {
        return _incentivesController;
    }

    /// @dev Returns the address of the incentives controller contract.
    function getIncentivesController() external view override returns (IRewarder) {
        return _getIncentivesController();
    }

    /**
     * @dev Transfers the underlying asset to `target`. Used by the LendingPool to transfer
     * assets in borrow(), withdraw() and flashLoan().
     * @param target The recipient of the aTokens.
     * @param amount The amount getting transferred.
     * @return The amount transferred.
     */
    function transferUnderlyingTo(address target, uint256 amount)
        external
        override
        onlyLendingPool
        returns (uint256)
    {
        _rebalance(amount);
        _underlyingAmount = _underlyingAmount - amount;
        IERC20(_underlyingAsset).safeTransfer(target, amount);
        return amount;
    }

    /**
     * @dev Invoked to execute actions on the aToken side after a repayment.
     * @param user The user executing the repayment.
     * @param onBehalfOf The user beneficiary.
     * @param amount The amount getting repaid.
     */
    function handleRepayment(address user, address onBehalfOf, uint256 amount)
        external
        override
        onlyLendingPool
    {
        _underlyingAmount = _underlyingAmount + amount;
    }

    /**
     * @dev Implements the permit function as per
     * https://github.com/ethereum/EIPs/blob/8a34d644aacf0f9f8f00815307fd7dd5da07655f/EIPS/eip-2612.md.
     * @param owner The owner of the funds.
     * @param spender The spender.
     * @param value The amount.
     * @param deadline The deadline timestamp, type(uint256).max for max deadline.
     * @param v Signature param.
     * @param s Signature param.
     * @param r Signature param.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(owner != address(0), "INVALID_OWNER");

        require(block.timestamp <= deadline, "INVALID_EXPIRATION");
        uint256 currentValidNonce = _nonces[owner];
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(PERMIT_TYPEHASH, owner, spender, value, currentValidNonce, deadline)
                )
            )
        );
        require(owner == ecrecover(digest, v, r, s), "INVALID_SIGNATURE");
        _nonces[owner] = currentValidNonce + 1;
        _approve(owner, spender, value);
    }

    /**
     * @dev Transfers the aTokens between two users. Validates the transfer
     * (ie checks for valid HF after the transfer) if required.
     * @param from The source address.
     * @param to The destination address.
     * @param amount The amount getting transferred.
     * @param validate `true` if the transfer needs to be validated.
     */
    function _transfer(address from, address to, uint256 amount, bool validate) internal {
        address underlyingAsset = _underlyingAsset;
        ILendingPool pool = _pool;

        uint256 index = pool.getReserveNormalizedIncome(underlyingAsset, RESERVE_TYPE);

        uint256 fromBalanceBefore = super.balanceOf(from).rayMul(index);
        uint256 toBalanceBefore = super.balanceOf(to).rayMul(index);

        super._transfer(from, to, amount.rayDiv(index));

        if (validate) {
            pool.finalizeTransfer(
                underlyingAsset, RESERVE_TYPE, from, to, amount, fromBalanceBefore, toBalanceBefore
            );
        }

        emit BalanceTransfer(from, to, amount, index);
    }

    /**
     * @dev Overrides the parent _transfer to force validated transfer() and transferFrom().
     * @param from The source address.
     * @param to The destination address.
     * @param amount The amount getting transferred.
     */
    function _transfer(address from, address to, uint256 amount) internal override {
        _transfer(from, to, amount, true);
    }

    /// --------- Share logic ---------

    /**
     * @dev Transfers the aToken shares between two users. Validates the transfer
     * (ie checks for valid HF after the transfer) if required.
     * Restricted to `_aTokenWrapper`.
     * @param from The source address.
     * @param to The destination address.
     * @param shareAmount The share amount getting transferred.
     */
    function transferShare(address from, address to, uint256 shareAmount) external {
        require(msg.sender == _aTokenWrapper, "AT_CALLER_NOT_WRAPPER");

        address underlyingAsset = _underlyingAsset;
        ILendingPool pool = _pool;

        uint256 index = pool.getReserveNormalizedIncome(underlyingAsset, RESERVE_TYPE);

        uint256 fromBalanceBefore = super.balanceOf(from).rayMul(index);
        uint256 toBalanceBefore = super.balanceOf(to).rayMul(index);

        super._transfer(from, to, shareAmount);

        uint256 amount = shareAmount.rayMul(index);

        pool.finalizeTransfer(
            underlyingAsset, RESERVE_TYPE, from, to, amount, fromBalanceBefore, toBalanceBefore
        );

        emit BalanceTransfer(from, to, amount, index);
    }

    /**
     * @dev Allows `spender` to spend the shares owned by `owner`.
     * Restricted to `_aTokenWrapper`.
     * @param owner The owner of the shares.
     * @param spender The user allowed to spend owner tokens.
     * @param shareAmount The share amount getting approved.
     */
    function shareApprove(address owner, address spender, uint256 shareAmount) external {
        require(msg.sender == _aTokenWrapper, "AT_CALLER_NOT_WRAPPER");

        _shareAllowances[owner][spender] = shareAmount;
    }

    /**
     * @dev Returns the share allowance for a given owner and spender.
     * @param owner The owner of the shares.
     * @param spender The spender address.
     * @return The current share allowance.
     */
    function shareAllowances(address owner, address spender) external view returns (uint256) {
        return _shareAllowances[owner][spender];
    }

    /// @dev Returns the address of the wrapper contract for this aToken.
    function WRAPPER_ADDRESS() external view returns (address) {
        return _aTokenWrapper;
    }

    /**
     * @dev Converts an asset amount to share amount.
     * @param assetAmount The amount of assets to convert.
     * @return The equivalent amount in shares.
     */
    function convertToShares(uint256 assetAmount) external view returns (uint256) {
        return assetAmount.rayDiv(_pool.getReserveNormalizedIncome(_underlyingAsset, RESERVE_TYPE));
    }

    /**
     * @dev Converts a share amount to asset amount.
     * @param shareAmount The amount of shares to convert.
     * @return The equivalent amount in assets.
     */
    function convertToAssets(uint256 shareAmount) external view returns (uint256) {
        return shareAmount.rayMul(_pool.getReserveNormalizedIncome(_underlyingAsset, RESERVE_TYPE));
    }

    /// --------- Rehypothecation logic ---------
    /**
     * @dev Rebalances the internal allocation of funds between the contract and the vault.
     * @notice This function ensures there is enough liquidity to process a future transfer by freeing up `_amountToWithdraw`.
     * @param _amountToWithdraw The amount of tokens that needs to be made available for withdrawal.
     */
    function _rebalance(uint256 _amountToWithdraw) internal {
        if (_farmingPct == 0 && _farmingBal == 0) {
            return;
        }
        // How much has been allocated as per our internal records?
        uint256 currentAllocated = _farmingBal;
        // What is the present value of our shares?
        uint256 ownedShares = IERC20(address(_vault)).balanceOf(address(this));
        uint256 sharesToAssets = _vault.convertToAssets(ownedShares);
        uint256 profit;
        uint256 toWithdraw;
        uint256 toDeposit;
        // If we have profit that's more than the threshold, record it for withdrawal and redistribution.
        if (
            sharesToAssets > currentAllocated
                && sharesToAssets - currentAllocated >= _claimingThreshold
        ) {
            profit = sharesToAssets - currentAllocated;
        }
        // What % of the final pool balance would the current allocation be?
        uint256 finalBalance = _underlyingAmount - _amountToWithdraw;
        uint256 pctOfFinalBal =
            finalBalance == 0 ? type(uint256).max : currentAllocated * 10000 / finalBalance;
        // If abs(percentOfFinalBal - yieldingPercentage) > drift, we will need to deposit more or withdraw some.
        uint256 finalFarmingAmount = finalBalance * _farmingPct / 10000;
        if (pctOfFinalBal > _farmingPct && pctOfFinalBal - _farmingPct > _farmingPctDrift) {
            // We will end up overallocated, withdraw some.
            toWithdraw = currentAllocated - finalFarmingAmount;
            _farmingBal = _farmingBal - toWithdraw;
        } else if (pctOfFinalBal < _farmingPct && _farmingPct - pctOfFinalBal > _farmingPctDrift) {
            // We will end up underallocated, deposit more.
            toDeposit = finalFarmingAmount - currentAllocated;
            _farmingBal = _farmingBal + toDeposit;
        }
        // + means deposit, - means withdraw.
        int256 netAssetMovement = int256(toDeposit) - int256(toWithdraw) - int256(profit);
        if (netAssetMovement > 0) {
            _vault.deposit(uint256(netAssetMovement), address(this));
        } else if (netAssetMovement < 0) {
            _vault.withdraw(uint256(-netAssetMovement), address(this), address(this));
        }
        // If we recorded profit, recalculate it for precision and distribute.
        if (profit != 0) {
            // Profit is ultimately (coll at hand) + (coll allocated to yield generator) - (recorded total coll Amount in pool).
            profit =
                IERC20(_underlyingAsset).balanceOf(address(this)) + _farmingBal - _underlyingAmount;
            if (profit != 0) {
                // Distribute to profitHandler.
                IERC20(_underlyingAsset).safeTransfer(_profitHandler, profit);
            }
        }

        emit Rebalance(address(_vault), _amountToWithdraw, netAssetMovement);
    }

    /**
     * @dev Sets the farming percentage for yield generation.
     * @param farmingPct The new farming percentage (0-10000).
     */
    function setFarmingPct(uint256 farmingPct) external override onlyLendingPool {
        require(address(_vault) != address(0), Errors.AT_VAULT_NOT_INITIALIZED);
        require(farmingPct <= 10000, Errors.AT_INVALID_AMOUNT);
        _farmingPct = farmingPct;
    }

    /**
     * @dev Sets the claiming threshold for profit distribution.
     * @param claimingThreshold The new claiming threshold.
     */
    function setClaimingThreshold(uint256 claimingThreshold) external override onlyLendingPool {
        require(address(_vault) != address(0), Errors.AT_VAULT_NOT_INITIALIZED);
        _claimingThreshold = claimingThreshold;
    }

    /**
     * @dev Sets the farming percentage drift threshold.
     * @param farmingPctDrift The new farming percentage drift (0-10000).
     */
    function setFarmingPctDrift(uint256 farmingPctDrift) external override onlyLendingPool {
        require(farmingPctDrift <= 10000, Errors.AT_INVALID_AMOUNT);
        require(address(_vault) != address(0), Errors.AT_VAULT_NOT_INITIALIZED);
        _farmingPctDrift = farmingPctDrift;
    }

    /**
     * @dev Sets the profit handler address.
     * @param profitHandler The new profit handler address.
     */
    function setProfitHandler(address profitHandler) external override onlyLendingPool {
        require(profitHandler != address(0), Errors.AT_INVALID_ADDRESS);
        require(address(_vault) != address(0), Errors.AT_VAULT_NOT_INITIALIZED);
        _profitHandler = profitHandler;
    }

    /**
     * @dev Sets the vault address for yield generation.
     * @param vault The new vault address.
     */
    function setVault(address vault) external override onlyLendingPool {
        require(address(vault) != address(0), Errors.AT_INVALID_ADDRESS);
        if (address(_vault) != address(0)) {
            require(_farmingBal == 0, Errors.AT_VAULT_NOT_EMPTY);
        }
        require(IERC4626(vault).asset() == _underlyingAsset, Errors.AT_INVALID_ADDRESS);
        _vault = IERC4626(vault);
        IERC20(_underlyingAsset).forceApprove(address(_vault), type(uint256).max);
    }

    /**
     * @dev Sets the treasury address.
     * @param treasury The new treasury address.
     */
    function setTreasury(address treasury) external override onlyLendingPool {
        require(treasury != address(0), Errors.AT_INVALID_ADDRESS);
        _treasury = treasury;
    }

    /**
     * @dev Sets the incentives controller address.
     * @param incentivesController The new incentives controller address.
     */
    function setIncentivesController(address incentivesController)
        external
        override
        onlyLendingPool
    {
        require(incentivesController != address(0), Errors.AT_INVALID_ADDRESS);
        _incentivesController = IRewarder(incentivesController);
    }

    /**
     * @dev Triggers a rebalance of the vault allocation.
     */
    function rebalance() external override onlyLendingPool {
        _rebalance(0);
    }

    /// @dev Returns the total balance of underlying asset of this token, including balance lent to a vault.
    function getTotalManagedAssets() public view override returns (uint256) {
        return _underlyingAmount;
    }

    /// @dev Returns the address of the lending pool contract.
    function getPool() external view returns (address) {
        return address(_pool);
    }
}
