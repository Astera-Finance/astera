import {IAToken} from "./IAToken.sol";
import {ILendingPool} from "./ILendingPool.sol";
import {IRewarder} from "./IRewarder.sol";
import {IERC6909} from "./IERC6909.sol";

interface IAERC6909 is IERC6909{
    function getRevision() external pure returns (uint256);
    function initialize(
        ILendingPool pool,
        address[] memory underlyingAssetAddresses,
        string[] memory names,
        string[] memory symbols,
        uint8[] memory decimals
    ) external;
    function setIncentivesController(IRewarder controller) external;
    function setPool(ILendingPool pool) external;
    function setUnderlyingAsset(uint256 id, address underlyingAsset) external;
    function getUnderlyingAsset(uint256 id) external view returns (address);
    function getIndexForUnderlyingAsset(address underlyingAsset) external view returns (uint256 index);
    function getIndexForOverlyingAsset(uint id) external view returns (uint256 index);
    function getScaledUserBalanceAndSupply(address user, uint256 id) external view returns (uint256 scaledBalance, uint256 supply);
    function totalSupply(uint256 id) external view returns (uint256);
    function isDebtToken(uint256 id) external view returns (bool);
    function getIdForUnderlying(address underlying) external view returns (uint256 aTokenId, uint256 debtTokenId);
    


}