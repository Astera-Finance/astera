// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {SignedSafeMath} from '../../../dependencies/openzeppelin/contracts/SignedSafeMath.sol';
import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {ILendingPool} from '../../../interfaces/ILendingPool.sol';
import {IAToken} from '../../../interfaces/IAToken.sol';
import {WadRayMath} from '../../libraries/math/WadRayMath.sol';
import {Errors} from '../../libraries/helpers/Errors.sol';
import {VersionedInitializable} from '../../libraries/upgradeability/VersionedInitializable.sol';
import {IncentivizedERC6909} from './IncentivizedERC6909.sol';
import {IRewarder} from '../../../interfaces/IRewarder.sol';
import {IERC4626} from '../../../interfaces/IERC4626.sol';

contract ATokenERC6909 is IncentivizedERC6909(), VersionedInitializable {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using SignedSafeMath for int256;

  uint256 public constant ATOKEN_REVISION = 0x1;
  uint256 private _totalTokens;

  ILendingPool public POOL;
  IRewarder public INCENTIVES_CONTROLLER;

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
}