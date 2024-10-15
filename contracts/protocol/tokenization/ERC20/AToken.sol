// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {IAToken} from "../../../../contracts/interfaces/IAToken.sol";
import {WadRayMath} from "../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {VersionedInitializable} from
    "../../../../contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {IncentivizedERC20} from
    "../../../../contracts/protocol/tokenization/ERC20/IncentivizedERC20.sol";
import {IRewarder} from "../../../../contracts/interfaces/IRewarder.sol";
import {IERC4626} from "../../../../contracts/interfaces/IERC4626.sol";
import {ATokenNonRebasing} from
    "../../../../contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";

/**
 * @title Aave ERC20 AToken
 * @dev Implementation of the interest bearing token for the Aave protocol
 * @author Cod3x
 */
contract AToken is
    VersionedInitializable,
    IncentivizedERC20("ATOKEN_IMPL", "ATOKEN_IMPL", 0),
    IAToken
{
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    bytes public constant EIP712_REVISION = bytes("1");
    bytes32 internal constant EIP712_DOMAIN = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    uint256 public constant ATOKEN_REVISION = 0x1;

    mapping(address => mapping(address => uint256)) internal _shareAllowances;

    /// @dev owner => next valid nonce to submit with permit()
    mapping(address => uint256) public _nonces;

    bytes32 public DOMAIN_SEPARATOR;
    bool public RESERVE_TYPE;

    ILendingPool internal _pool;
    address internal _treasury;
    address internal _underlyingAsset;

    IRewarder internal _incentivesController;

    address internal _aTokenWrapper;

    /**
     * @dev Rehypothecation related vars
     * vault is the ERC4626 contract the aToken will supply part of its tokens to
     * underlyingAmount is the recorded amount of underlying entering and exiting this contract from the perspective of the protocol
     * farmingPct is the share of underlying that should be rehypothecated
     * farmingBal is the recorded amount of underlying supplied to the vault
     * claimingThreshold is the minimum amount this contract will try to claim as profit
     * farmingPctDrift is the minimum difference in pct after which the contract will rebalance
     * profitHandler is the EOA/contract receiving profit
     */
    IERC4626 public vault;
    uint256 public underlyingAmount;
    uint256 public farmingPct;
    uint256 public farmingBal;
    uint256 public claimingThreshold;
    uint256 public farmingPctDrift;
    address public profitHandler;

    modifier onlyLendingPool() {
        require(_msgSender() == address(_pool), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        _;
    }

    function getRevision() internal pure virtual override returns (uint256) {
        return ATOKEN_REVISION;
    }

    /**
     * @dev Initializes the aToken
     * @param pool The address of the lending pool where this aToken will be used
     * @param treasury The address of the Aave treasury, receiving the fees on this aToken
     * @param underlyingAsset The address of the underlying asset of this aToken (E.g. WETH for aWETH)
     * @param incentivesController The smart contract managing potential incentives distribution
     * @param aTokenDecimals The decimals of the aToken, same as the underlying asset's\
     * @param reserveType Whether the reserve is boosted by a vault
     * @param aTokenName The name of the aToken
     * @param aTokenSymbol The symbol of the aToken
     * @param params Additional params to configure contract
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

        _aTokenWrapper = address(new ATokenNonRebasing(address(this)));

        emit Initialized(
            underlyingAsset,
            address(pool),
            treasury,
            address(incentivesController),
            aTokenDecimals,
            reserveType,
            aTokenName,
            aTokenSymbol,
            params
        );
    }

    /**
     * @dev Burns aTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
     * - Only callable by the LendingPool, as extra state updates there need to be managed
     * @param user The owner of the aTokens, getting them burned
     * @param receiverOfUnderlying The address that will receive the underlying
     * @param amount The amount being burned
     * @param index The new liquidity index of the reserve
     *
     */
    function burn(address user, address receiverOfUnderlying, uint256 amount, uint256 index)
        external
        override
        onlyLendingPool
    {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.CT_INVALID_BURN_AMOUNT);
        _rebalance(amount);
        underlyingAmount = underlyingAmount - amount;
        _burn(user, amountScaled);

        IERC20(_underlyingAsset).safeTransfer(receiverOfUnderlying, amount);

        emit Transfer(user, address(0), amount);
        emit Burn(user, receiverOfUnderlying, amount, index);
    }

    /**
     * @dev Mints `amount` aTokens to `user`
     * - Only callable by the LendingPool, as extra state updates there need to be managed
     * @param user The address receiving the minted tokens
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve
     * @return `true` if the the previous balance of the user was 0
     */
    function mint(address user, uint256 amount, uint256 index)
        external
        override
        onlyLendingPool
        returns (bool)
    {
        uint256 previousBalance = super.balanceOf(user);

        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.CT_INVALID_MINT_AMOUNT);
        underlyingAmount = underlyingAmount + amount;
        _rebalance(0);
        _mint(user, amountScaled);

        emit Transfer(address(0), user, amount);
        emit Mint(user, amount, index);

        return previousBalance == 0;
    }

    /**
     * @dev Mints aTokens to the reserve treasury
     * - Only callable by the LendingPool
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve
     */
    function mintToTreasury(uint256 amount, uint256 index) external override onlyLendingPool {
        if (amount == 0) {
            return;
        }

        address treasury = _treasury;

        // Compared to the normal mint, we don't check for rounding errors.
        // The amount to mint can easily be very small since it is a fraction of the interest ccrued.
        // In that case, the treasury will experience a (very small) loss, but it
        // wont cause potentially valid transactions to fail.
        _mint(treasury, amount.rayDiv(index));

        emit Transfer(address(0), treasury, amount);
        emit Mint(treasury, amount, index);
    }

    /**
     * @dev Transfers aTokens in the event of a borrow being liquidated, in case the liquidators reclaims the aToken
     * - Only callable by the LendingPool
     * @param from The address getting liquidated, current owner of the aTokens
     * @param to The recipient
     * @param value The amount of tokens getting transferred
     *
     */
    function transferOnLiquidation(address from, address to, uint256 value)
        external
        override
        onlyLendingPool
    {
        // Being a normal transfer, the Transfer() and BalanceTransfer() are emitted
        // so no need to emit a specific event here
        _transfer(from, to, value, false);

        emit Transfer(from, to, value);
    }

    /**
     * @dev Calculates the balance of the user: principal balance + interest generated by the principal
     * @param user The user whose balance is calculated
     * @return The balance of the user
     *
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
     * updated stored balance divided by the reserve's liquidity index at the moment of the update
     * @param user The user whose balance is calculated
     * @return The scaled balance of the user
     *
     */
    function scaledBalanceOf(address user) external view override returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @dev Returns the scaled balance of the user and the scaled total supply.
     * @param user The address of the user
     * @return The scaled balance of the user
     * @return The scaled balance and the scaled total supply
     *
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
     * @dev calculates the total supply of the specific aToken
     * since the balance of every single user increases over time, the total supply
     * does that too.
     * @return the current total supply
     *
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
     * @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
     * @return the scaled total supply
     *
     */
    function scaledTotalSupply() public view virtual override returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @dev Returns the address of the Aave treasury, receiving the fees on this aToken
     *
     */
    function RESERVE_TREASURY_ADDRESS() public view returns (address) {
        return _treasury;
    }

    /**
     * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     *
     */
    function UNDERLYING_ASSET_ADDRESS() public view override returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev Returns the address of the lending pool where this aToken is used
     *
     */
    function POOL() public view returns (ILendingPool) {
        return _pool;
    }

    /**
     * @dev For internal usage in the logic of the parent contract IncentivizedERC20
     *
     */
    function _getIncentivesController() internal view override returns (IRewarder) {
        return _incentivesController;
    }

    /**
     * @dev Returns the address of the incentives controller contract
     *
     */
    function getIncentivesController() external view override returns (IRewarder) {
        return _getIncentivesController();
    }

    /**
     * @dev Transfers the underlying asset to `target`. Used by the LendingPool to transfer
     * assets in borrow(), withdraw() and flashLoan()
     * @param target The recipient of the aTokens
     * @param amount The amount getting transferred
     * @return The amount transferred
     *
     */
    function transferUnderlyingTo(address target, uint256 amount)
        external
        override
        onlyLendingPool
        returns (uint256)
    {
        _rebalance(amount);
        underlyingAmount = underlyingAmount - amount;
        IERC20(_underlyingAsset).safeTransfer(target, amount);
        return amount;
    }

    /**
     * @dev Invoked to execute actions on the aToken side after a repayment.
     * @param amount The amount getting repaid
     *
     */
    function handleRepayment(address, address, uint256 amount) external override onlyLendingPool {
        underlyingAmount = underlyingAmount + amount;
    }

    /**
     * @dev implements the permit function as for
     * https://github.com/ethereum/EIPs/blob/8a34d644aacf0f9f8f00815307fd7dd5da07655f/EIPS/eip-2612.md
     * @param owner The owner of the funds
     * @param spender The spender
     * @param value The amount
     * @param deadline The deadline timestamp, type(uint256).max for max deadline
     * @param v Signature param
     * @param s Signature param
     * @param r Signature param
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
        //solium-disable-next-line
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
     * (ie checks for valid HF after the transfer) if required
     * @param from The source address
     * @param to The destination address
     * @param amount The amount getting transferred
     * @param validate `true` if the transfer needs to be validated
     *
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
     * @dev Overrides the parent _transfer to force validated transfer() and transferFrom()
     * @param from The source address
     * @param to The destination address
     * @param amount The amount getting transferred
     *
     */
    function _transfer(address from, address to, uint256 amount) internal override {
        _transfer(from, to, amount, true);
    }

    /// --------- Share logic ---------

    /**
     * @dev Transfers the aToken shares between two users. Validates the transfer
     * (ie checks for valid HF after the transfer) if required
     * Restricted to `_aTokenWrapper`.
     * @param from The source address
     * @param to The destination address
     * @param shareAmount The share amount getting transferred
     */
    function transferShare(address from, address to, uint256 shareAmount) external {
        require(msg.sender == _aTokenWrapper, "CALLER_NOT_WRAPPER");

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
     * @param spender The user allowed to spend owner tokens
     * @param shareAmount The share amount getting approved
     */
    function shareApprove(address owner, address spender, uint256 shareAmount) external {
        require(msg.sender == _aTokenWrapper, "CALLER_NOT_WRAPPER");

        _shareAllowances[owner][spender] = shareAmount;
    }

    function shareAllowances(address owner, address spender) external view returns (uint256) {
        return _shareAllowances[owner][spender];
    }

    function WRAPPER_ADDRESS() external view returns (address) {
        return _aTokenWrapper;
    }

    function convertToShares(uint256 assetAmount) external view returns (uint256) {
        return assetAmount.rayDiv(_pool.getReserveNormalizedIncome(_underlyingAsset, RESERVE_TYPE));
    }

    function convertToAssets(uint256 shareAmount) external view returns (uint256) {
        return shareAmount.rayMul(_pool.getReserveNormalizedIncome(_underlyingAsset, RESERVE_TYPE));
    }

    /// --------- Rehypothecation logic ---------

    /// @dev Rebalance so as to free _amountToWithdraw for a future transfer
    function _rebalance(uint256 _amountToWithdraw) internal {
        if (farmingPct == 0 && farmingBal == 0) {
            return;
        }
        // how much has been allocated as per our internal records?
        uint256 currentAllocated = farmingBal;
        // what is the present value of our shares?
        uint256 ownedShares = IERC20(address(vault)).balanceOf(address(this));
        uint256 sharesToAssets = vault.convertToAssets(ownedShares);
        uint256 profit;
        uint256 toWithdraw;
        uint256 toDeposit;
        // if we have profit that's more than the threshold, record it for withdrawal and redistribution
        if (
            sharesToAssets > currentAllocated
                && sharesToAssets - currentAllocated >= claimingThreshold
        ) {
            profit = sharesToAssets - currentAllocated;
        }
        // what % of the final pool balance would the current allocation be?
        uint256 finalBalance = underlyingAmount - _amountToWithdraw;
        uint256 pctOfFinalBal =
            finalBalance == 0 ? type(uint256).max : currentAllocated * 10000 / finalBalance;
        // if abs(percentOfFinalBal - yieldingPercentage) > drift, we will need to deposit more or withdraw some
        uint256 finalFarmingAmount = finalBalance * farmingPct / 10000;
        if (pctOfFinalBal > farmingPct && pctOfFinalBal - farmingPct > farmingPctDrift) {
            // we will end up overallocated, withdraw some
            toWithdraw = currentAllocated - finalFarmingAmount;
            farmingBal = farmingBal - toWithdraw;
        } else if (pctOfFinalBal < farmingPct && farmingPct - pctOfFinalBal > farmingPctDrift) {
            // we will end up underallocated, deposit more
            toDeposit = finalFarmingAmount - currentAllocated;
            farmingBal = farmingBal + toDeposit;
        }
        // + means deposit, - means withdraw
        int256 netAssetMovement = int256(toDeposit) - int256(toWithdraw) - int256(profit);
        if (netAssetMovement > 0) {
            vault.deposit(uint256(netAssetMovement), address(this));
        } else if (netAssetMovement < 0) {
            vault.withdraw(uint256(-netAssetMovement), address(this), address(this));
        }
        // if we recorded profit, recalculate it for precision and distribute
        if (profit != 0) {
            // profit is ultimately (coll at hand) + (coll allocated to yield generator) - (recorded total coll Amount in pool)
            profit =
                IERC20(_underlyingAsset).balanceOf(address(this)) + farmingBal - underlyingAmount;
            if (profit != 0) {
                // distribute to profitHandler
                IERC20(_underlyingAsset).safeTransfer(profitHandler, profit);
            }
        }

        emit Rebalance(address(vault), _amountToWithdraw, netAssetMovement);
    }

    function setFarmingPct(uint256 _farmingPct) external override onlyLendingPool {
        require(address(vault) != address(0), "84");
        require(_farmingPct <= 10000, "82");
        farmingPct = _farmingPct;
    }

    function setClaimingThreshold(uint256 _claimingThreshold) external override onlyLendingPool {
        require(address(vault) != address(0), "84");
        claimingThreshold = _claimingThreshold;
    }

    function setFarmingPctDrift(uint256 _farmingPctDrift) external override onlyLendingPool {
        require(_farmingPctDrift <= 10000, "82");
        require(address(vault) != address(0), "84");
        farmingPctDrift = _farmingPctDrift;
    }

    function setProfitHandler(address _profitHandler) external override onlyLendingPool {
        require(_profitHandler != address(0), "83");
        require(address(vault) != address(0), "84");
        profitHandler = _profitHandler;
    }

    function setVault(address _vault) external override onlyLendingPool {
        require(address(vault) == address(0), "84");
        require(IERC4626(_vault).asset() == _underlyingAsset, "83");
        vault = IERC4626(_vault);
        IERC20(_underlyingAsset).forceApprove(address(vault), type(uint256).max);
    }

    function setTreasury(address treasury) external override onlyLendingPool {
        require(treasury != address(0), "85");
        _treasury = treasury;
    }

    function setIncentivesController(address incentivesController)
        external
        override
        onlyLendingPool
    {
        require(incentivesController != address(0), "85");
        _incentivesController = IRewarder(incentivesController);
    }

    function rebalance() external override onlyLendingPool {
        _rebalance(0);
    }
    /**
     * @dev Returns the total balance of underlying asset of this token, including balance lent to a vault
     *
     */

    function getTotalManagedAssets() public view override returns (uint256) {
        return underlyingAmount;
    }

    function getPool() external view returns (address) {
        return address(_pool);
    }
}
