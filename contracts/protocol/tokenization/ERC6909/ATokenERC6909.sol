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
import {IERC4626} from '../../../interfaces/IERC4626.sol';

contract ATokenERC6909 is IncentivizedERC6909(), VersionedInitializable {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using SignedSafeMath for int256;
  using ReserveLogic for DataTypes.ReserveData;

  uint256 public constant ATOKEN_REVISION = 0x1;
  uint256 private _totalTokens;

  ILendingPool public POOL;
  IRewarder public INCENTIVES_CONTROLLER;
  uint const ATokenAddressableIDs = 1000; // This is the first ID for aToken
  uint const DebtTokenAddressableIDs = 2000; // This is the first ID for debtToken

    // @dev Mapping of the underlying aToken address to the data of the reserve for the wrapped aToken
    mapping(address => DataTypes.ReserveData) private _reserves;

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


  function getRevision() internal pure virtual override returns (uint256) {
    return ATOKEN_REVISION;
  }

  function initialize(
    ILendingPool pool,
    address[] memory underlyingAssetAddresses,
    string[] memory names,
    string[] memory symbols,
    uint8[] memory decimals
  ) public initializer {
    require(address(pool) != address(0), Errors.LP_NOT_CONTRACT);
    
    _totalTokens = underlyingAssetAddresses.length;
    require(
        _totalTokens == names.length &&
        _totalTokens == symbols.length &&
        _totalTokens == decimals.length,
        Errors.AT_VL_INVALID_ATOKEN_PARAMS
    );
    
    for(uint i = 0; i < _totalTokens; i++) {
        require(underlyingAssetAddresses[i] != address(0), Errors.LP_NOT_CONTRACT);
        require(bytes(names[i]).length != 0);
        require(bytes(symbols[i]).length != 0);
        require(decimals[i] != 0);
        _setName(i, names[i]);
        _setSymbol(i, symbols[i]);
        _setDecimals(i, decimals[i]);
        _setUnderlyingAsset(i, underlyingAssetAddresses[i]);
    }
  }

  function _getIncentivesController() internal view override returns (IRewarder) {
    return INCENTIVES_CONTROLLER;
  }

  function setIncentivesController(IRewarder controller) external {
    require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
    INCENTIVES_CONTROLLER = controller;
  }

  function setPool(ILendingPool pool) external {
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
            revert;
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
        index = 1E27;
    }

    function getIndexForOverlyingAsset(uint256 id) public view returns (uint256 index) {
        uint256 underlyingIndex = getIndexForUnderlyingAsset(_underlyingAssetAddresses[id]);
        index = 1e27;
        index = index.rayMul(underlyingIndex).rayDiv(1E27);
    }

    function transferUnderlyingTo(uint256 id, address to, uint256 amount) external {
        require(msg.sender == address(POOL), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        IERC20(_underlyingAssetAddresses[id]).transfer(to, amount);
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

  function getIdForUnderlying(address underlying) public view returns (uint256 aTokenID, uint256 debtTokenID) {
    //query lendingpool for tokens ID
    //if !found, assign to next available ID + max lendingpool tokens

  }
}