// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import "./IMiniPoolRewarder.sol";
import "./IMiniPool.sol";
import "./IERC6909.sol";

interface IAERC6909 is IERC6909 {
    function initialize(address provider, uint256 minipoolId) external;
    function initReserve(
        address underlyingAsset,
        string calldata name,
        string calldata symbol,
        uint8 decimals
    ) external returns (uint256 aTokenID, uint256 debtTokenID, bool isTranche);
    function setIncentivesController(IMiniPoolRewarder controller) external;
    function setPool(IMiniPool pool) external;
    function setUnderlyingAsset(uint256 id, address underlyingAsset) external;
    function getUnderlyingAsset(uint256 id) external view returns (address);
    function transfer(address to, uint256 id, uint256 amount) external override returns (bool);
    function transferFrom(address from, address to, uint256 id, uint256 amount)
        external
        override
        returns (bool);
    function getIndexForUnderlyingAsset(address underlyingAsset)
        external
        view
        returns (uint256 index);
    function getIndexForOverlyingAsset(uint256 id) external view returns (uint256 index);
    function transferUnderlyingTo(address to, uint256 id, uint256 amount) external;
    function getScaledUserBalanceAndSupply(address user, uint256 id)
        external
        view
        returns (uint256, uint256);
    function totalSupply(uint256 id) external view returns (uint256);
    function scaledTotalSupply(uint256 id) external view returns (uint256);
    function isAToken(uint256 id) external pure returns (bool);
    function isDebtToken(uint256 id) external pure returns (bool);
    function getIdForUnderlying(address underlying)
        external
        view
        returns (uint256 aTokenID, uint256 debtTokenID, bool isTranche);
    function mintToTreasury(uint256 id, uint256 amount, uint256 index) external;
    function mint(address user, address onBehalfOf, uint256 id, uint256 amount, uint256 index)
        external
        returns (bool);
    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 id,
        uint256 amount,
        uint256 index
    ) external;
    function approveDelegation(address delegatee, uint256 id, uint256 amount) external;
    function handleRepayment(address user, address onBehalfOf, uint256 id, uint256 amount)
        external;
    function isTranche(uint256 id) external view returns (bool);
    function transferOnLiquidation(address from, address to, uint256 id, uint256 amount) external;
    function borrowAllowances(address delegator, address delegatee, uint256 id)
        external
        returns (uint256);
}
