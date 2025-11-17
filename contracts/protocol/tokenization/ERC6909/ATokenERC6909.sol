// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {IAToken} from "../../../../contracts/interfaces/IAToken.sol";
import {WadRayMath} from "../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {
    VersionedInitializable
} from "../../../../contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveLogic} from "../../../../contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
import {
    IncentivizedERC6909
} from "../../../../contracts/protocol/tokenization/ERC6909/IncentivizedERC6909.sol";
import {IMiniPoolRewarder} from "../../../../contracts/interfaces/IMiniPoolRewarder.sol";
import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {
    IMiniPoolAddressesProvider
} from "../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IMiniPool} from "../../../../contracts/interfaces/IMiniPool.sol";
import {
    ATokenNonRebasing
} from "../../../../contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {SafeERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {
    IMiniPoolAddressProviderUpdatable
} from "../../../../contracts/interfaces/IMiniPoolAddressProviderUpdatable.sol";
import {
    ILendingPoolConfigurator
} from "../../../../contracts/interfaces/ILendingPoolConfigurator.sol";
import {
    ILendingPoolAddressesProvider
} from "../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";

/**
 * @title ERC6909-MultiToken
 * @author Conclave - 0xGoober
 * @notice Built to service all collateral and debt tokens for a specific MiniPool.
 * @dev Current implementation allows for 128 tranched tokens from the Main Pool and 1000-128 unique tokens
 *      from the MiniPool.
 */
contract ATokenERC6909 is
    IncentivizedERC6909,
    VersionedInitializable,
    IMiniPoolAddressProviderUpdatable
{
    using WadRayMath for uint256;
    using ReserveLogic for DataTypes.ReserveData;
    using SafeERC20 for IERC20;

    // ======================= Events =======================

    /**
     * @notice Emitted when a new token is initialized.
     * @param id The identifier of the token.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param decimals The number of decimals of the token.
     * @param underlyingAsset The address of the underlying asset.
     */
    event TokenInitialized(
        uint256 indexed id, string name, string symbol, uint8 decimals, address underlyingAsset
    );

    /**
     * @notice Emitted when a token is minted.
     * @param user The address of the user receiving the minted tokens
     * @param id The identifier of the token
     * @param amount The amount of tokens minted
     * @param index The index of the reserve at the time of minting
     */
    event Mint(address indexed user, uint256 indexed id, uint256 amount, uint256 index);

    /**
     * @notice Emitted when a token is burned.
     * @param user The address of the user whose tokens are being burned
     * @param id The identifier of the token
     * @param amount The amount of tokens burned
     * @param index The index of the reserve at the time of burning
     */
    event Burn(address indexed user, uint256 indexed id, uint256 amount, uint256 index);

    /**
     * @notice Emitted when the incentives controller is set.
     * @param controller The new incentives controller address.
     */
    event IncentivesControllerSet(address controller);

    // ======================= Constant =======================

    /// @notice The revision number for the AToken implementation.
    uint256 public constant ATOKEN_REVISION = 0x1;
    /// @notice The first ID for aToken. This is the first ID for aToken.
    uint256 public constant ATOKEN_ADDRESSABLE_ID = 1000;
    /// @notice The first ID for debtToken. This is the first ID for debtToken.
    uint256 public constant DEBT_TOKEN_ADDRESSABLE_ID = 2000;

    // ======================= Storage =======================

    /// @notice The incentives controller for rewards distribution.
    IMiniPoolRewarder private _incentivesController;
    /// @notice The MiniPool contract.
    IMiniPool private POOL;

    /// @notice The total number of unique tokens.
    uint256 private _totalUniqueTokens;
    /// @notice The addresses provider for the MiniPool.
    IMiniPoolAddressesProvider private _addressesProvider;
    /// @notice The ID of the MiniPool.
    uint256 private _minipoolId;

    /// @notice Mapping from token `id` to underlying asset address.
    mapping(uint256 => address) private _underlyingAssetAddresses;
    /// @notice Mapping from token `id` to tranche status.
    mapping(uint256 => bool) private _isTranche;
    /// @notice Mapping from token `id` to user to delegate to allowance amount. ID -> User -> Delegate -> Allowance.
    mapping(uint256 => mapping(address => mapping(address => uint256))) private _borrowAllowances;

    constructor() {
        _blockInitializing();
    }

    // ======================= External Function =======================

    /**
     * @notice Initializes the AToken contract.
     * @param provider The address of the MiniPool addresses provider.
     * @param minipoolId The ID of the MiniPool.
     * @dev This function can only be called once through the initializer modifier.
     */
    function initialize(address provider, uint256 minipoolId) public initializer {
        require(address(provider) != address(0), Errors.LP_NOT_CONTRACT);
        uint256 chainId;

        assembly {
            chainId := chainid()
        }
        _addressesProvider = IMiniPoolAddressesProvider(provider);
        _minipoolId = minipoolId;
        POOL = IMiniPool(_addressesProvider.getMiniPool(minipoolId));
    }

    /**
     * @notice Initializes a new reserve with aToken and debtToken.
     * @param underlyingAsset The address of the underlying asset.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param decimals The number of decimals of the token.
     * @return aTokenID The ID of the created aToken.
     * @return debtTokenID The ID of the created debtToken.
     * @return isTrancheRet Whether the created tokens are tranche tokens.
     */
    function initReserve(
        address underlyingAsset,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external returns (uint256 aTokenID, uint256 debtTokenID, bool isTrancheRet) {
        require(
            msg.sender == address(_addressesProvider.getMiniPoolConfigurator()),
            Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
        (aTokenID, debtTokenID, isTrancheRet) = getNextIdForUnderlying(underlyingAsset);
        if (isTrancheRet) {
            _isTranche[aTokenID] = true;
            _isTranche[debtTokenID] = true;

            // Ensure reserveType == True. (`assert` because it must never be `false`).
            assert(IAToken(underlyingAsset).RESERVE_TYPE());

            // Ensure the AToken address is the Non Rebasing version.
            require(
                ATokenNonRebasing(underlyingAsset).ATOKEN_ADDRESS() != address(0),
                Errors.AT_INVALID_ATOKEN_ADDRESS
            );
        } else {
            _totalUniqueTokens++;
        }

        _initializeATokenID(aTokenID, underlyingAsset, name, symbol, decimals);
        _initializeDebtTokenID(debtTokenID, underlyingAsset, name, symbol, decimals);
    }

    /**
     * @notice Sets the incentives controller for the token.
     * @param controller The address of the new incentives controller.
     */
    function setIncentivesController(IMiniPoolRewarder controller) external {
        require(msg.sender == address(POOL), Errors.AT_CALLER_MUST_BE_LENDING_POOL);
        _incentivesController = controller;

        emit IncentivesControllerSet(address(controller));
    }

    /**
     * @notice Transfers tokens to another address.
     * @param to The recipient address.
     * @param id The token ID.
     * @param amount The amount to transfer.
     * @return A boolean indicating success.
     */
    function transfer(address to, uint256 id, uint256 amount)
        public
        payable
        override
        returns (bool)
    {
        if (isAToken(id)) {
            address underlyingAsset = _underlyingAssetAddresses[id];

            uint256 index = POOL.getReserveNormalizedIncome(underlyingAsset);
            uint256 fromBalanceBefore = super.balanceOf(msg.sender, id).rayMul(index);
            uint256 toBalanceBefore = super.balanceOf(to, id).rayMul(index);

            super.transfer(to, id, amount.rayDiv(index));

            POOL.finalizeTransfer(
                underlyingAsset, msg.sender, to, amount, fromBalanceBefore, toBalanceBefore
            );
        } else {
            // Restricted to `POOL`, see `_beforeTokenTransfer()`. Not used for now.
            address underlyingAsset = _underlyingAssetAddresses[id];
            uint256 index = POOL.getReserveNormalizedVariableDebt(underlyingAsset);

            super.transfer(to, id, amount.rayDiv(index));
        }

        return true;
    }

    /**
     * @notice Transfers tokens from one address to another.
     * @param from The sender address.
     * @param to The recipient address.
     * @param id The token ID.
     * @param amount The amount to transfer.
     * @return A boolean indicating success.
     */
    function transferFrom(address from, address to, uint256 id, uint256 amount)
        public
        payable
        override
        returns (bool)
    {
        if (isAToken(id)) {
            address underlyingAsset = _underlyingAssetAddresses[id];

            uint256 index = POOL.getReserveNormalizedIncome(underlyingAsset);
            uint256 fromBalanceBefore = super.balanceOf(from, id).rayMul(index);
            uint256 toBalanceBefore = super.balanceOf(to, id).rayMul(index);

            super.transferFrom(from, to, id, amount.rayDiv(index));

            POOL.finalizeTransfer(
                underlyingAsset, from, to, amount, fromBalanceBefore, toBalanceBefore
            );
        } else {
            // Restricted to `POOL`, see `_beforeTokenTransfer()`. Not used for now.
            address underlyingAsset = _underlyingAssetAddresses[id];
            uint256 index = POOL.getReserveNormalizedVariableDebt(underlyingAsset);

            super.transferFrom(from, to, id, amount.rayDiv(index));
        }

        return true;
    }

    /**
     * @notice Transfers the underlying asset to a specified address.
     * @param to The recipient address.
     * @param id The token ID.
     * @param amount The amount to transfer.
     * @param unwrap Whether to unwrap the underlying asset.
     */
    function transferUnderlyingTo(address to, uint256 id, uint256 amount, bool unwrap) public {
        require(msg.sender == address(POOL), Errors.AT_CALLER_MUST_BE_LENDING_POOL);

        address underlyingAsset = _underlyingAssetAddresses[id];
        if (
            unwrap
                && ILendingPoolConfigurator(
                        ILendingPoolAddressesProvider(
                                _addressesProvider.getLendingPoolAddressesProvider()
                            ).getLendingPoolConfigurator()
                    ).getIsAToken(underlyingAsset)
        ) {
            ATokenNonRebasing asset = ATokenNonRebasing(underlyingAsset);
            ILendingPool(_addressesProvider.getLendingPool())
                .withdraw(asset.UNDERLYING_ASSET_ADDRESS(), true, asset.convertToAssets(amount), to);
        } else {
            IERC20(underlyingAsset).safeTransfer(to, amount);
        }
    }

    /**
     * @notice Mints tokens to the Astera treasury.
     * @param id The token ID.
     * @param amount The amount to mint.
     * @param index The current liquidity index.
     */
    function mintToAsteraTreasury(uint256 id, uint256 amount, uint256 index) external {
        address treasury = _addressesProvider.getMiniPoolAsteraTreasury();
        _mintToTreasury(id, amount, index, treasury);
    }

    /**
     * @notice Mints tokens to the MiniPool owner treasury.
     * @param id The token ID.
     * @param amount The amount to mint.
     * @param index The current liquidity index.
     */
    function mintToMinipoolOwnerTreasury(uint256 id, uint256 amount, uint256 index) external {
        address treasury = _addressesProvider.getMiniPoolOwnerTreasury(_minipoolId);
        _mintToTreasury(id, amount, index, treasury);
    }

    /**
     * @notice Mints tokens to a specified address.
     * @param user The address initiating the mint.
     * @param onBehalfOf The address receiving the minted tokens.
     * @param id The token ID.
     * @param amount The amount to mint.
     * @param index The current liquidity index.
     * @return A boolean indicating if this was the first mint for the recipient.
     */
    function mint(address user, address onBehalfOf, uint256 id, uint256 amount, uint256 index)
        external
        returns (bool)
    {
        require(msg.sender == address(POOL), Errors.AT_CALLER_MUST_BE_LENDING_POOL);
        if (amount == 0) {
            return false;
        }

        if (isDebtToken(id) && onBehalfOf != user) {
            _decreaseBorrowAllowance(onBehalfOf, user, id, amount);
        }

        uint256 previousBalance = super.balanceOf(onBehalfOf, id);
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.AT_INVALID_MINT_AMOUNT);
        _mint(onBehalfOf, id, amountScaled);

        emit Mint(onBehalfOf, id, amountScaled, index);

        return previousBalance == 0;
    }

    /**
     * @notice Burns tokens from a user.
     * @param user The address to burn tokens from.
     * @param receiverOfUnderlying The address to receive the underlying asset.
     * @param id The token ID.
     * @param amount The amount to burn.
     * @param unwrap Whether to unwrap the underlying asset.
     * @param index The current liquidity index.
     */
    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 id,
        uint256 amount,
        bool unwrap,
        uint256 index
    ) external {
        require(msg.sender == address(POOL), Errors.AT_CALLER_MUST_BE_LENDING_POOL);

        uint256 amountScaled = amount.rayDiv(index);

        require(amountScaled != 0, Errors.AT_INVALID_BURN_AMOUNT);
        if (isAToken(id)) {
            transferUnderlyingTo(receiverOfUnderlying, id, amount, unwrap);
        }
        _burn(user, id, amountScaled);

        emit Burn(user, id, amountScaled, index);
    }

    /**
     * @notice Approves delegation of borrowing power.
     * @dev This view function only works for debt tokens id.
     * @param delegatee The address receiving the delegation.
     * @param id The token ID.
     * @param amount The amount of borrowing power to delegate.
     */
    function approveDelegation(address delegatee, uint256 id, uint256 amount) external {
        require(isDebtToken(id), Errors.AT_INVALID_ATOKEN_ID);
        _borrowAllowances[id][msg.sender][delegatee] = amount;
    }

    /**
     * @notice Transfers tokens during liquidation.
     * @param from The address to transfer from.
     * @param to The address to transfer to.
     * @param id The token ID.
     * @param amount The amount to transfer.
     */
    function transferOnLiquidation(address from, address to, uint256 id, uint256 amount) external {
        require(msg.sender == address(POOL), Errors.AT_CALLER_MUST_BE_LENDING_POOL);
        _transferForLiquidation(from, to, id, amount);
    }

    /**
     * @notice Handles repayment of debt.
     */
    function handleRepayment(address, address, uint256, uint256) external view {}

    // ======================= Internal Function =======================

    /**
     * @notice Sets the underlying asset address for a token ID.
     * @param id The token ID to set the underlying asset for.
     * @param underlyingAsset The address of the underlying asset.
     * @dev Reverts if `underlyingAsset` is zero address.
     */
    function _setUnderlyingAsset(uint256 id, address underlyingAsset) internal {
        require(underlyingAsset != address(0), Errors.LP_NOT_CONTRACT);
        _underlyingAssetAddresses[id] = underlyingAsset;
    }

    /**
     * @notice Hook that is called before any token transfer.
     * @param id The token ID being transferred.
     * @dev For debt tokens, only allows transfers from the lending pool.
     */
    function _beforeTokenTransfer(address, address, uint256 id, uint256) internal view override {
        if (isDebtToken(id)) {
            require(msg.sender == address(POOL), Errors.AT_CALLER_MUST_BE_LENDING_POOL);
        }
    }

    /**
     * @notice Hook that is called after any token transfer to handle incentives.
     * @param from The address tokens are transferred from.
     * @param to The address tokens are transferred to.
     * @param id The token ID being transferred.
     * @param amount The amount being transferred in shares.
     * @dev Updates incentives based on transfer type (mint/burn/transfer).
     * @dev this hook gets called from solday's `ERC6909` which only deals with shares
     */
    function _afterTokenTransfer(address from, address to, uint256 id, uint256 amount)
        internal
        override
    {
        uint256 oldSupply = super.totalSupply(id);
        uint256 oldFromBalance = super.balanceOf(from, id);
        uint256 oldToBalance = super.balanceOf(to, id);

        //If the token was minted.
        if (from == address(0) && to != address(0)) {
            oldSupply = _incrementTotalSupply(id, amount);
            oldToBalance = oldToBalance - amount;
            if (address(_incentivesController) != address(0)) {
                _incentivesController.handleAction(id, to, oldSupply, oldToBalance);
            }
            //If the token was burned.
        } else if (to == address(0) && from != address(0)) {
            oldSupply = _decrementTotalSupply(id, amount);
            oldFromBalance = oldFromBalance + amount;
            if (address(_incentivesController) != address(0)) {
                _incentivesController.handleAction(id, from, oldSupply, oldFromBalance);
            }
        }
        //The token was transferred.
        else {
            oldFromBalance = oldFromBalance + amount;
            oldToBalance = oldToBalance - amount;
            if (address(_incentivesController) != address(0)) {
                _incentivesController.handleAction(id, from, oldSupply, oldFromBalance);

                if (from != to) {
                    _incentivesController.handleAction(id, to, oldSupply, oldToBalance);
                }
            }
        }
    }

    /**
     * @notice Determines if an address is an AToken in the lending pool.
     * @param underlying The address to check.
     * @param MLP The MiniLendingPool address to validate against.
     * @return bool True if the address is an AToken, false otherwise.
     */
    function _determineIfAToken(address underlying, address MLP) internal returns (bool) {
        (bool success, bytes memory data) = underlying.call(abi.encodeCall(IAToken.getPool, ()));

        // Check if call was successful, returned data is 32 bytes (address size + padding),
        // and decoded value fits in address space (160 bits)
        if (success && data.length == 32 && abi.decode(data, (uint256)) <= type(uint160).max) {
            return abi.decode(data, (address)) == MLP;
        } else {
            return false;
        }
    }

    /**
     * @notice Gets the next available token IDs for a new underlying asset.
     * @param underlying The underlying asset address.
     * @return A tuple containing (aTokenID, debtTokenID, isTrancheRet).
     * @dev For ATokens, returns IDs based on reserve data. For other assets, generates new IDs.
     */
    function _getNextIdForUnderlying(address underlying) internal returns (uint256, uint256, bool) {
        ILendingPool pool = ILendingPool(_addressesProvider.getLendingPool());
        if (_determineIfAToken(underlying, address(pool))) {
            address tokenUnderlying = IAToken(underlying).UNDERLYING_ASSET_ADDRESS();

            // Ensure LendingPool reserve is initialized.
            require(
                pool.getReserveData(tokenUnderlying, true).aTokenAddress != address(0),
                Errors.RL_RESERVE_NOT_INITIALIZED
            );
            // Thanks to the above check, `getReserveData.id` returns the correct value.
            uint256 tokenID = pool.getReserveData(tokenUnderlying, true).id;
            // Check if aToken is in underlyingAsset mapping - if it isn't it means aToken is not initialized in the erc6909
            require(
                _underlyingAssetAddresses[tokenID + ATOKEN_ADDRESSABLE_ID] == address(0),
                Errors.RL_RESERVE_ALREADY_INITIALIZED
            );

            return (tokenID + ATOKEN_ADDRESSABLE_ID, tokenID + DEBT_TOKEN_ADDRESSABLE_ID, true);
        } else {
            uint256 offset = pool.MAX_NUMBER_RESERVES();
            uint256 tokenID = offset + _totalUniqueTokens;
            // Loop through all ids associated with ERC20 tokens and check if underlying asset occurs
            for (
                uint256 id = offset + ATOKEN_ADDRESSABLE_ID;
                id < tokenID + ATOKEN_ADDRESSABLE_ID;
                id++
            ) {
                require(
                    _underlyingAssetAddresses[id] != underlying,
                    Errors.RL_RESERVE_ALREADY_INITIALIZED
                );
            }

            return (tokenID + ATOKEN_ADDRESSABLE_ID, tokenID + DEBT_TOKEN_ADDRESSABLE_ID, false);
        }
    }

    /**
     * @notice Mints tokens to the treasury.
     * @param id The token ID to mint.
     * @param amount The amount to mint.
     * @param index The price index to scale the amount.
     * @param treasury The treasury address to mint to.
     * @dev Only callable by the lending pool. Skips rounding checks for small amounts.
     */
    function _mintToTreasury(uint256 id, uint256 amount, uint256 index, address treasury) internal {
        require(msg.sender == address(POOL), Errors.AT_CALLER_MUST_BE_LENDING_POOL);
        if (amount == 0) {
            return;
        }

        // Compared to the normal mint, we don't check for rounding errors.
        // The amount to mint can easily be very small since it is a fraction of the interest accrued.
        // In that case, the treasury will experience a (very small) loss, but it
        // won't cause potentially valid transactions to fail.
        uint256 amountScaled = amount.rayDiv(index);
        _mint(treasury, id, amountScaled);

        emit Mint(treasury, id, amountScaled, index);
    }

    /**
     * @notice Decreases the borrow allowance for a delegatee.
     * @param delegator The address delegating borrowing power.
     * @param delegatee The address receiving delegation.
     * @param id The token ID.
     * @param amount The amount to decrease allowance by.
     * @dev Reverts if allowance would go below zero.
     */
    function _decreaseBorrowAllowance(
        address delegator,
        address delegatee,
        uint256 id,
        uint256 amount
    ) internal {
        uint256 oldAllowance = _borrowAllowances[id][delegator][delegatee];
        require(oldAllowance >= amount, Errors.AT_BORROW_ALLOWANCE_NOT_ENOUGH);
        uint256 newAllowance = oldAllowance - amount;
        _borrowAllowances[id][delegator][delegatee] = newAllowance;
    }

    /**
     * @notice Initializes a new AToken ID with metadata.
     * @param id The token ID to initialize.
     * @param underlyingAsset The underlying asset address.
     * @param name The token name.
     * @param symbol The token symbol.
     * @param decimals The number of decimals.
     * @dev Sets name as "Astera Minipool {minipoolId}{name}" and symbol as "cl-{minipoolId}-{symbol}".
     */
    function _initializeATokenID(
        uint256 id,
        address underlyingAsset,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal {
        require(bytes(name).length != 0);
        require(bytes(symbol).length != 0);
        require(decimals != 0);
        require(id < DEBT_TOKEN_ADDRESSABLE_ID, Errors.AT_INVALID_ATOKEN_ID);
        _setName(id, string.concat("Astera Minipool ", Strings.toString(_minipoolId), " ", name));
        _setSymbol(id, string.concat("as-", Strings.toString(_minipoolId), "-", symbol)); // cl-{minipoolId}-{symbol}
        _setDecimals(id, decimals);
        _setUnderlyingAsset(id, underlyingAsset);
        emit TokenInitialized(id, name, symbol, decimals, underlyingAsset);
    }

    /**
     * @notice Initializes a new debt token ID with metadata.
     * @param id The token ID to initialize.
     * @param underlyingAsset The underlying asset address.
     * @param name The token name.
     * @param symbol The token symbol.
     * @param decimals The number of decimals.
     * @dev Sets name as "Variable Debt {name}" and symbol as "vDebt{symbol}".
     */
    function _initializeDebtTokenID(
        uint256 id,
        address underlyingAsset,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal {
        require(bytes(name).length != 0);
        require(bytes(symbol).length != 0);
        require(decimals != 0);
        _setName(id, string.concat("Variable Debt ", Strings.toString(_minipoolId), " ", name));
        _setSymbol(id, string.concat("asDebt-", Strings.toString(_minipoolId), "-", symbol));
        _setDecimals(id, decimals);
        _setUnderlyingAsset(id, underlyingAsset);

        emit TokenInitialized(id, name, symbol, decimals, underlyingAsset);
    }

    /**
     * @notice Handles token transfers during liquidation.
     * @param from The address to transfer from.
     * @param to The address to transfer to.
     * @param id The token ID.
     * @param amount The amount to transfer.
     * @dev Only transfers ATokens, scaling amount by normalized income.
     */
    function _transferForLiquidation(address from, address to, uint256 id, uint256 amount)
        internal
    {
        if (isAToken(id)) {
            address underlyingAsset = _underlyingAssetAddresses[id];

            uint256 index = POOL.getReserveNormalizedIncome(underlyingAsset);

            super._transfer(address(0), from, to, id, amount.rayDiv(index));
        }
    }

    // ======================= View/Pure Function =======================

    /**
     * @notice Gets the total supply for a token ID.
     * @param id The token ID.
     * @return The total supply scaled by normalized income.
     */
    function totalSupply(uint256 id) public view override returns (uint256) {
        uint256 currentSupplyScaled = super.totalSupply(id);

        if (currentSupplyScaled == 0) {
            return 0;
        }

        if (isDebtToken(id)) {
            return currentSupplyScaled.rayMul(
                POOL.getReserveNormalizedVariableDebt(_underlyingAssetAddresses[id])
            );
        } else {
            return currentSupplyScaled.rayMul(
                POOL.getReserveNormalizedIncome(_underlyingAssetAddresses[id])
            );
        }
    }

    /**
     * @notice Gets the balance of tokens for an address.
     * @param user The address to check.
     * @param id The token ID.
     * @return The balance scaled by normalized income/debt.
     */
    function balanceOf(address user, uint256 id) public view override returns (uint256) {
        if (isDebtToken(id)) {
            return super.balanceOf(user, id)
                .rayMul(POOL.getReserveNormalizedVariableDebt(_underlyingAssetAddresses[id]));
        } else {
            return super.balanceOf(user, id)
                .rayMul(POOL.getReserveNormalizedIncome(_underlyingAssetAddresses[id]));
        }
    }

    /**
     * @notice Gets the scaled total supply for a token `id` without applying the income index.
     * @param id The token identifier.
     * @return The raw total supply before income scaling.
     */
    function scaledTotalSupply(uint256 id) public view returns (uint256) {
        return super.totalSupply(id);
    }

    /**
     * @notice Checks if a token `id` represents an AToken by validating its range.
     * @param id The token identifier to check.
     * @return True if the `id` is between `ATOKEN_ADDRESSABLE_ID` and `DEBT_TOKEN_ADDRESSABLE_ID`, false otherwise.
     */
    function isAToken(uint256 id) public pure returns (bool) {
        return id < DEBT_TOKEN_ADDRESSABLE_ID && id >= ATOKEN_ADDRESSABLE_ID;
    }

    /**
     * @notice Checks if a token `id` represents a debt token by validating its range.
     * @param id The token identifier to check.
     * @return True if the `id` is greater than or equal to `DEBT_TOKEN_ADDRESSABLE_ID`, false otherwise.
     */
    function isDebtToken(uint256 id) public pure returns (bool) {
        return id >= DEBT_TOKEN_ADDRESSABLE_ID;
    }

    /**
     * @notice Returns the borrow allowance of the user.
     * @dev This view function only works for debt tokens id.
     * @param id The token ID.
     * @param fromUser The user giving allowance.
     * @param toUser The user to give allowance to.
     * @return The current allowance of `toUser`.
     */
    function borrowAllowance(uint256 id, address fromUser, address toUser)
        external
        view
        returns (uint256)
    {
        require(isDebtToken(id), Errors.AT_INVALID_ATOKEN_ID);
        return _borrowAllowances[id][fromUser][toUser];
    }

    /**
     * @notice Checks if a token represents a tranche token by querying internal mapping.
     * @param id The token identifier to check.
     * @return True if the `id` represents a tranche token, false otherwise.
     */
    function isTranche(uint256 id) public view returns (bool) {
        return _isTranche[id];
    }

    /**
     * @notice Gets the scaled balance and total supply for a user.
     * @param user The user address.
     * @param id The token ID.
     * @return A tuple of (scaled balance, scaled total supply).
     */
    function getScaledUserBalanceAndSupply(address user, uint256 id)
        external
        view
        returns (uint256, uint256)
    {
        return (super.balanceOf(user, id), super.totalSupply(id));
    }

    /**
     * @notice Gets the next available token IDs for a new underlying asset.
     * @param underlying The underlying asset address.
     * @return aTokenID The AToken ID.
     * @return debtTokenID The debt token ID.
     * @return isTrancheRet Whether the token is a tranche token.
     * @dev Reverts if reserve is already initialized.
     */
    function getNextIdForUnderlying(address underlying)
        public
        returns (uint256 aTokenID, uint256 debtTokenID, bool isTrancheRet)
    {
        (aTokenID, debtTokenID, isTrancheRet) = _getNextIdForUnderlying(underlying);

        require(
            _underlyingAssetAddresses[aTokenID] == address(0), Errors.RL_RESERVE_ALREADY_INITIALIZED
        );
    }

    /**
     * @notice Gets the token IDs for an existing underlying asset.
     * @param underlying The underlying asset address.
     * @return aTokenID The AToken ID.
     * @return debtTokenID The debt token ID.
     * @return isTrancheRet Whether the token is a tranche token.
     * @dev Reverts if reserve is not initialized.
     */
    function getIdForUnderlying(address underlying)
        public
        view
        returns (uint256 aTokenID, uint256 debtTokenID, bool isTrancheRet)
    {
        DataTypes.MiniPoolReserveData memory reserveData =
            IMiniPool(POOL).getReserveData(underlying);
        aTokenID = reserveData.aTokenID;
        debtTokenID = reserveData.variableDebtTokenID;
        isTrancheRet = isTranche(aTokenID);

        require(
            _underlyingAssetAddresses[aTokenID] != address(0), Errors.RL_RESERVE_NOT_INITIALIZED
        );
    }

    /**
     * @notice Returns the underlying asset address for a given token ID.
     * @param id The token identifier.
     * @return The address of the underlying asset corresponding to `id`.
     */
    function getUnderlyingAsset(uint256 id) external view returns (address) {
        return _underlyingAssetAddresses[id];
    }

    /**
     * @notice Returns the revision number of the contract implementation.
     * @return The `ATOKEN_REVISION` value.
     */
    function getRevision() internal pure virtual override returns (uint256) {
        return ATOKEN_REVISION;
    }

    /**
     * @notice Returns the address of the associated MiniPool contract.
     * @return The address of the `POOL` contract.
     */
    function getMinipoolAddress() external view returns (address) {
        return address(POOL);
    }

    /**
     * @notice Returns the identifier of the associated MiniPool.
     * @return The value of `_minipoolId`.
     */
    function getMinipoolId() external view returns (uint256) {
        return _minipoolId;
    }

    /**
     * @notice Returns the incentives controller used for rewards distribution.
     * @return The `_incentivesController` contract interface.
     */
    function getIncentivesController() external view returns (IMiniPoolRewarder) {
        return _incentivesController;
    }
}
