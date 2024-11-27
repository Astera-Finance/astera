// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IMiniPoolRewarder} from "../../contracts/interfaces/IMiniPoolRewarder.sol";
import {IMiniPool} from "../../contracts/interfaces/IMiniPool.sol";
import {IERC6909} from "../../contracts/interfaces/IERC6909.sol";

/**
 * @title IAERC6909
 * @author Cod3x
 */
interface IAERC6909 is IERC6909 {
    event TokenInitialized(
        uint256 indexed id, string name, string symbol, uint8 decimals, address underlyingAsset
    );

    function initialize(address provider, uint256 minipoolId) external;

    function initReserve(
        address underlyingAsset,
        string calldata name,
        string calldata symbol,
        uint8 decimals
    ) external returns (uint256 aTokenID, uint256 debtTokenID, bool isTranche);

    function setIncentivesController(IMiniPoolRewarder controller) external;

    function getUnderlyingAsset(uint256 id) external view returns (address);

    function transfer(address to, uint256 id, uint256 amount) external override returns (bool);

    function transferFrom(address from, address to, uint256 id, uint256 amount)
        external
        override
        returns (bool);

    function transferUnderlyingTo(address to, uint256 id, uint256 amount, bool unwrap) external;

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

    function getNextIdForUnderlying(address underlying)
        external
        view
        returns (uint256 aTokenID, uint256 debtTokenID, bool isTranche);

    function mintToCod3xTreasury(uint256 id, uint256 amount, uint256 index) external;

    function mintToMinipoolOwnerTreasury(uint256 id, uint256 amount, uint256 index) external;

    function mint(address user, address onBehalfOf, uint256 id, uint256 amount, uint256 index)
        external
        returns (bool);

    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 id,
        uint256 amount,
        bool unwrap,
        uint256 index
    ) external;

    function approveDelegation(address delegatee, uint256 id, uint256 amount) external;

    function handleRepayment(address user, address onBehalfOf, uint256 id, uint256 amount)
        external;

    function isTranche(uint256 id) external view returns (bool);

    function transferOnLiquidation(address from, address to, uint256 id, uint256 amount) external;

    function getMinipoolAddress() external view returns (address);

    function getMinipoolId() external view returns (uint256);

    function ATOKEN_ADDRESSABLE_ID() external view returns (uint256);

    function DEBT_TOKEN_ADDRESSABLE_ID() external view returns (uint256);
}
