// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {SignedSafeMath} from '../../../dependencies/openzeppelin/contracts/SignedSafeMath.sol';
import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {ILendingPool} from '../../../interfaces/ILendingPool.sol';
import {IAToken} from '../../../interfaces/IAToken.sol';
import {WadRayMath} from '../../libraries/math/WadRayMath.sol';
import {Errors} from '../../libraries/helpers/Errors.sol';
import {VersionedInitializable} from '../../libraries/upgradeability/VersionedInitializable.sol';
import {DataTypes} from '../../libraries/types/DataTypes.sol';
import {ReserveLogic} from '../../libraries/logic/ReserveLogic.sol';
import {IncentivizedERC6909} from './IncentivizedERC6909.sol';
import {IRewarder} from '../../../interfaces/IRewarder.sol';
import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {IMiniPoolAddressesProvider} from '../../../interfaces/IMiniPoolAddressesProvider.sol';
import {IMiniPool} from '../../../interfaces/IMiniPool.sol';

contract ATokenERC6909 is IncentivizedERC6909(), VersionedInitializable {
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



/***
    * @dev Mapping of the underlying asset address to the aToken id
    * @param underlyingAssetAddresses The address of the underlying asset
    * @param id The id of the aToken
    * @notice while the underlying asset address here is the actual asset underlying,
    * (i.e. USDC) the aToken here is double nested and what is actually deposited is aTokens from the general Pool
    * (i.e. aUSDC) this allows for double rate incentives / penalties on lending
    * You can think of it is a nested aToken
 */

  mapping(uint256 => address) private _underlyingAssetAddresses;
  mapping(uint256 => bool) private _isTranche;
  uint256 private _minipoolId;


  function getRevision() internal pure virtual override returns (uint256) {
    return ATOKEN_REVISION;
  }

  function initialize(
    address provider,
    uint256 minipoolId
    ) public initializer {
    require(address(provider) != address(0), Errors.LP_NOT_CONTRACT);
    _addressesProvider = IMiniPoolAddressesProvider(provider);
    _minipoolId = minipoolId;
  }

  function _initializeATokenID(uint256 id, address underlyingAsset, string memory name, string memory symbol, uint8 decimals) internal {
    require(underlyingAsset != address(0), Errors.LP_NOT_CONTRACT);
    require(bytes(name).length != 0);
    require(bytes(symbol).length != 0);
    require(decimals != 0);
    _setName(id, string.concat('Granary Interest Bearing ', name));
    _setSymbol(id, string.concat('grain',symbol));
    _setDecimals(id, decimals);
    _setUnderlyingAsset(id, underlyingAsset);
    
  }

  function _initializeDebtTokenID(uint256 id, address underlyingAsset, string memory name, string memory symbol, uint8 decimals) internal {
    require(underlyingAsset != address(0), Errors.LP_NOT_CONTRACT);
    require(bytes(name).length != 0);
    require(bytes(symbol).length != 0);
    require(decimals != 0);
    _setName(id, string.concat('Variable Debt ', name));
    _setSymbol(id, string.concat('vDebt',symbol));
    _setDecimals(id, decimals);
    _setUnderlyingAsset(id, underlyingAsset);
  }

  function initReserve(
    address underlyingAsset,
    string memory name,
    string memory symbol,
    uint8 decimals
  ) external {
    require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
    (uint256 aTokenID, uint256 debtTokenID, bool isTranche) = getIdForUnderlying(underlyingAsset);
    if(isTranche) {
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

    function _beforeTokenTransfer(
    address from,
    address to,
    uint256 id,
    uint256 amount
    ) internal override {
        if(isDebtToken(id)) {
            revert();
        }
    }

    function _afterTokenTransfer(
    address from,
    address to,
    uint256 id,
    uint256 amount
    ) internal override {
        if(from == address(0) && to != address(0)) {
            _incrementTotalSupply(id, amount);
        } else if(to == address(0) && from != address(0)) {
            _decrementTotalSupply(id, amount);
        }
    }

    function getIndexForUnderlyingAsset(address underlyingAsset) public view returns (uint256 index) {
        ILendingPool pool = ILendingPool(_addressesProvider.getLendingPool());
        index = pool.getReserveData(underlyingAsset, true).liquidityIndex;

    }

    function getIndexForOverlyingAsset(uint256 id) public view returns (uint256 index) {
        uint256 underlyingIndex = getIndexForUnderlyingAsset(_underlyingAssetAddresses[id]);
        index = 1e27;
        index = index.rayMul(underlyingIndex).rayDiv(1E27);
    }

    function transferUnderlyingTo(uint256 id, address to, uint256 amount) external {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        if(_isTranche[id]) {
            //pool.transferAndUnwrap(_underlyingAssetAddresses[id], to, amount);
        }else{
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

  function isDebtToken(uint256 id) public pure returns (bool) {
    return id >= DebtTokenAddressableIDs;
  }

  function getIdForUnderlying(address underlying) public view returns (uint256 aTokenID, uint256 debtTokenID, bool isTranche) {
   ILendingPool pool = ILendingPool(_addressesProvider.getLendingPool());
   if(_determineIfAToken(underlying, address(pool))) {
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
}