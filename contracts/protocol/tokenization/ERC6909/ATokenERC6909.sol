// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {SignedSafeMath} from "../../../dependencies/openzeppelin/contracts/SignedSafeMath.sol";
import {SafeMath} from "../../../dependencies/openzeppelin/contracts/SafeMath.sol";
import {ILendingPool} from "../../../interfaces/ILendingPool.sol";
import {IAToken} from "../../../interfaces/IAToken.sol";
import {WadRayMath} from "../../libraries/math/WadRayMath.sol";
import {Errors} from "../../libraries/helpers/Errors.sol";
import {VersionedInitializable} from "../../libraries/upgradeability/VersionedInitializable.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {ReserveLogic} from "../../libraries/logic/ReserveLogic.sol";
import {IncentivizedERC6909} from "./IncentivizedERC6909.sol";
import {IRewarder} from "../../../interfaces/IRewarder.sol";
import {IERC20} from "../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {IMiniPoolAddressesProvider} from "../../../interfaces/IMiniPoolAddressesProvider.sol";
import {IMiniPool} from "../../../interfaces/IMiniPool.sol";

contract ATokenERC6909 is IncentivizedERC6909, VersionedInitializable {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using SignedSafeMath for int256;
    using ReserveLogic for DataTypes.ReserveData;

    uint256 public constant ATOKEN_REVISION = 0x1;
    uint256 private _totalTokens;
    uint256 private _totalUniqueTokens;
    uint256 private _totalTrancheTokens;

    IMiniPoolAddressesProvider private _addressesProvider;
    IRewarder private INCENTIVES_CONTROLLER;
    IMiniPool private POOL;
    uint256 constant ATokenAddressableIDs = 1000; // This is the first ID for aToken
    uint256 constant DebtTokenAddressableIDs = 2000; // This is the first ID for debtToken

    event TokenInitialized(
        uint256 indexed id, string name, string symbol, uint8 decimals, address underlyingAsset
    );

    mapping(uint256 => address) private _underlyingAssetAddresses;
    mapping(uint256 => bool) private _isTranche;
    uint256 private _minipoolId;
    //ID -> User -> Delegate -> Allowance
    mapping(uint256 => mapping(address => mapping(address => uint256))) private _borrowAllowances;

    function getRevision() internal pure virtual override returns (uint256) {
        return ATOKEN_REVISION;
    }

    function initialize(address provider, uint256 minipoolId) public initializer {
        require(address(provider) != address(0), Errors.LP_NOT_CONTRACT);
        uint256 chainId;

        //solium-disable-next-line
        assembly {
            chainId := chainid()
        }
        _addressesProvider = IMiniPoolAddressesProvider(provider);
        _minipoolId = minipoolId;
        POOL = IMiniPool(_addressesProvider.getMiniPool(minipoolId));
    }

    function _initializeATokenID(
        uint256 id,
        address underlyingAsset,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal {
        require(underlyingAsset != address(0), Errors.LP_NOT_CONTRACT);
        require(bytes(name).length != 0);
        require(bytes(symbol).length != 0);
        require(decimals != 0);
        require(id < DebtTokenAddressableIDs, Errors.AT_INVALID_ATOKEN_ID);
        _setName(id, string.concat("Cod3x Lend Interest Bearing ", name));
        _setSymbol(id, string.concat("grain", symbol));
        _setDecimals(id, decimals);
        _setUnderlyingAsset(id, underlyingAsset);
        emit TokenInitialized(id, name, symbol, decimals, underlyingAsset);
    }

    function _initializeDebtTokenID(
        uint256 id,
        address underlyingAsset,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal {
        require(underlyingAsset != address(0), Errors.LP_NOT_CONTRACT);
        require(bytes(name).length != 0);
        require(bytes(symbol).length != 0);
        require(decimals != 0);
        _setName(id, string.concat("Variable Debt ", name));
        _setSymbol(id, string.concat("vDebt", symbol));
        _setDecimals(id, decimals);
        _setUnderlyingAsset(id, underlyingAsset);
        emit TokenInitialized(id, name, symbol, decimals, underlyingAsset);
    }

    function initReserve(
        address underlyingAsset,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external returns (uint256 aTokenID, uint256 debtTokenID, bool isTranche) {
        require(
            msg.sender == address(_addressesProvider.getMiniPoolConfigurator()),
            Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
        (aTokenID, debtTokenID, isTranche) = getIdForUnderlying(underlyingAsset);
        if (isTranche) {
            _totalTrancheTokens++;
            _isTranche[aTokenID] = true;
            _isTranche[debtTokenID] = true;
        } else {
            _totalUniqueTokens++;
        }
        _initializeATokenID(aTokenID, underlyingAsset, name, symbol, decimals);
        _initializeDebtTokenID(debtTokenID, underlyingAsset, name, symbol, decimals);
    }

    function _getIncentivesController() internal view override returns (IRewarder) {
        return INCENTIVES_CONTROLLER;
    }

    function setIncentivesController(IRewarder controller) external {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        INCENTIVES_CONTROLLER = controller;
    }

    function setPool(IMiniPool pool) external {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        POOL = pool;
    }

    function setUnderlyingAsset(uint256 id, address underlyingAsset) external {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        _setUnderlyingAsset(id, underlyingAsset);
    }

    function _setUnderlyingAsset(uint256 id, address underlyingAsset) internal {
        require(underlyingAsset != address(0), Errors.LP_NOT_CONTRACT);
        _underlyingAssetAddresses[id] = underlyingAsset;
    }

    function getUnderlyingAsset(uint256 id) external view returns (address) {
        return _underlyingAssetAddresses[id];
    }

    function _beforeTokenTransfer(address from, address to, uint256 id, uint256 amount)
        internal
        override
    {
        if (isDebtToken(id)) {
            require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 id, uint256 amount)
        internal
        override
    {
        if (from == address(0) && to != address(0)) {
            _incrementTotalSupply(id, amount);
        } else if (to == address(0) && from != address(0)) {
            _decrementTotalSupply(id, amount);
        }
    }

    function transfer(address to, uint256 id, uint256 amount)
        public
        payable
        override
        returns (bool)
    {
        if (isAToken(id)) {
            address underlyingAsset = _underlyingAssetAddresses[id];

            uint256 index = POOL.getReserveNormalizedIncome(underlyingAsset, true);
            uint256 fromBalanceBefore = super.balanceOf(msg.sender, id).rayMul(index);
            uint256 toBalanceBefore = super.balanceOf(to, id).rayMul(index);

            super.transfer(to, id, amount.rayDiv(index));

            POOL.finalizeTransfer(
                _underlyingAssetAddresses[id],
                true,
                msg.sender,
                to,
                amount,
                fromBalanceBefore,
                toBalanceBefore
            );
        } else {
            super.transfer(to, id, amount);
        }
    }

    function transferFrom(address from, address to, uint256 id, uint256 amount)
        public
        payable
        override
        returns (bool)
    {
        if (isAToken(id)) {
            address underlyingAsset = _underlyingAssetAddresses[id];

            uint256 index = POOL.getReserveNormalizedIncome(underlyingAsset, true);
            uint256 fromBalanceBefore = super.balanceOf(from, id).rayMul(index);
            uint256 toBalanceBefore = super.balanceOf(to, id).rayMul(index);

            super.transferFrom(from, to, id, amount.rayDiv(index));

            POOL.finalizeTransfer(
                _underlyingAssetAddresses[id],
                true,
                from,
                to,
                amount,
                fromBalanceBefore,
                toBalanceBefore
            );
        } else {
            super.transferFrom(from, to, id, amount);
        }
    }

    function getIndexForUnderlyingAsset(address underlyingAsset)
        public
        view
        returns (uint256 index)
    {
        ILendingPool pool = ILendingPool(_addressesProvider.getLendingPool());
        index = pool.getReserveData(underlyingAsset, true).liquidityIndex;
    }

    function getIndexForOverlyingAsset(uint256 id) public view returns (uint256 index) {
        uint256 underlyingIndex = getIndexForUnderlyingAsset(_underlyingAssetAddresses[id]);
        index = POOL.getReserveNormalizedIncome(_underlyingAssetAddresses[id], true);
        index = index.rayMul(underlyingIndex).rayDiv(1e27);
    }

    function transferUnderlyingTo(address to, uint256 id, uint256 amount) public {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        if (_isTranche[id]) {
            IERC20(_underlyingAssetAddresses[id]).transfer(to, amount);
            //pool.transferAndUnwrap(_underlyingAssetAddresses[id], to, amount);
        } else {
            IERC20(_underlyingAssetAddresses[id]).transfer(to, amount);
        }
    }

    function getScaledUserBalanceAndSupply(address user, uint256 id)
        external
        view
        returns (uint256, uint256)
    {
        return (super.balanceOf(user, id), super.totalSupply(id));
    }

    function totalSupply(uint256 id) public view override returns (uint256) {
        uint256 currentSupplyScaled = super.totalSupply(id);

        if (currentSupplyScaled == 0) {
            return 0;
        }
        return currentSupplyScaled.rayMul(getIndexForOverlyingAsset(id));
    }

    function scaledTotalSupply(uint256 id) public view returns (uint256) {
        return super.totalSupply(id);
    }

    function isAToken(uint256 id) public pure returns (bool) {
        return id < DebtTokenAddressableIDs && id >= ATokenAddressableIDs;
    }

    function isDebtToken(uint256 id) public pure returns (bool) {
        return id >= DebtTokenAddressableIDs;
    }

    function getIdForUnderlying(address underlying)
        public
        view
        returns (uint256 aTokenID, uint256 debtTokenID, bool isTranche)
    {
        ILendingPool pool = ILendingPool(_addressesProvider.getLendingPool());
        if (_determineIfAToken(underlying, address(pool))) {
            address tokenUnderlying = IAToken(underlying).UNDERLYING_ASSET_ADDRESS();
            uint256 tokenID = pool.getReserveData(tokenUnderlying, true).id;
            return (tokenID + ATokenAddressableIDs, tokenID + DebtTokenAddressableIDs, true);
        } else {
            uint256 offset = pool.MAX_NUMBER_RESERVES();
            uint256 tokenID = offset + _totalUniqueTokens;
            return (tokenID + ATokenAddressableIDs, tokenID + DebtTokenAddressableIDs, false);
        }
    }

    function _determineIfAToken(address underlying, address MLP) internal view returns (bool) {
        try IAToken(underlying).getPool() returns (address pool) {
            return pool == MLP;
        } catch {
            return false;
        }
    }

    function mintToTreasury(uint256 id, uint256 amount, uint256 index) external {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        if (amount == 0) {
            return;
        }

        address treasury = _addressesProvider.getMiniPoolTreasury(_minipoolId);

        // Compared to the normal mint, we don't check for rounding errors.
        // The amount to mint can easily be very small since it is a fraction of the interest ccrued.
        // In that case, the treasury will experience a (very small) loss, but it
        // wont cause potentially valid transactions to fail.
        _mint(treasury, id, amount.rayDiv(index));
    }

    function mint(address user, address onBehalfOf, uint256 id, uint256 amount, uint256 index)
        external
        returns (bool)
    {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        if (amount == 0) {
            return false;
        }

        uint256 previousBalance;

        if (id >= DebtTokenAddressableIDs) {
            if (onBehalfOf != user) {
                require(
                    _borrowAllowances[id][onBehalfOf][user] >= amount,
                    Errors.BORROW_ALLOWANCE_NOT_ENOUGH
                );
                _decreaseBorrowAllowance(onBehalfOf, user, id, amount);
            }
            previousBalance = super.balanceOf(onBehalfOf, id);
            uint256 amountScaled = amount.rayDiv(index);
            require(amountScaled != 0, Errors.CT_INVALID_MINT_AMOUNT);
            _mint(onBehalfOf, id, amountScaled);
        } else {
            previousBalance = super.balanceOf(onBehalfOf, id);
            uint256 amountScaled = amount.rayDiv(index);
            require(amountScaled != 0, Errors.CT_INVALID_MINT_AMOUNT);
            _mint(onBehalfOf, id, amountScaled);
        }

        return previousBalance == 0;
    }

    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 id,
        uint256 amount,
        uint256 index
    ) external {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        if (isDebtToken(id)) {
            uint256 amountScaled = amount.rayDiv(index);
            require(amountScaled != 0, Errors.CT_INVALID_BURN_AMOUNT);
            _burn(user, id, amountScaled);
        } else {
            uint256 amountScaled = amount.rayDiv(index);
            require(amountScaled != 0, Errors.CT_INVALID_BURN_AMOUNT);
            _burn(user, id, amountScaled);
            transferUnderlyingTo(receiverOfUnderlying, id, amount);
        }
    }

    function _decreaseBorrowAllowance(
        address delegator,
        address delegatee,
        uint256 id,
        uint256 amount
    ) internal {
        uint256 newAllowance = _borrowAllowances[id][delegator][delegatee].sub(
            amount, Errors.BORROW_ALLOWANCE_NOT_ENOUGH
        );
        _borrowAllowances[id][delegator][delegatee] = newAllowance;
    }

    function approveDelegation(address delegatee, uint256 id, uint256 amount) external {
        _borrowAllowances[id][msg.sender][delegatee] = amount;
    }

    function balanceOf(address user, uint256 id) public view override returns (uint256) {
        return super.balanceOf(user, id).rayMul(
            POOL.getReserveNormalizedIncome(_underlyingAssetAddresses[id], true)
        );
    }

    function handleRepayment(address user, address onBehalfOf, uint256 id, uint256 amount)
        external
        view
    {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
    }

    function isTranche(uint256 id) public view returns (bool) {
        return _isTranche[id];
    }

    function transferOnLiquidation(address from, address to, uint256 id, uint256 amount) external {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        _transferForLiquidation(from, to, id, amount);
    }

    function _transferForLiquidation(address from, address to, uint256 id, uint256 amount)
        internal
    {
        if (isAToken(id)) {
            address underlyingAsset = _underlyingAssetAddresses[id];

            uint256 index = POOL.getReserveNormalizedIncome(underlyingAsset, true);

            super._transfer(address(0), from, to, id, amount.rayDiv(index));
        }
    }
}
