// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {ERC20} from "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {IERC20} from "contracts/dependencies/openzeppelin/contracts/IERC20.sol";

/**
 * @title MockERC4626
 * @dev MockERC4626 emulate vault behaviour
 */
contract MockERC4626 is ERC20 {
    address public token;
    uint256 public totalDeposited;
    uint8 private _decimals;

    constructor(address _token, string memory _name, string memory _symbol, uint8 _decimals)
        ERC20(_name, _symbol)
    {
        token = _token;
        _setupDecimals(_decimals);
    }

    function asset() external view returns (address assetTokenAddress) {
        return token;
    }

    function totalAssets() external view returns (uint256 totalManagedAssets) {
        return totalDeposited;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        IERC20(token).transferFrom(msg.sender, address(this), assets);
        totalDeposited += assets;
        if (totalSupply() == 0) {
            shares = assets;
        } else {
            shares = (assets * totalDeposited) / IERC20(token).balanceOf(address(this));
        }
        _mint(receiver, shares);
    }

    function maxWithdraw(address owner) public view returns (uint256 maxAssets) {
        return convertToAssets(balanceOf(owner));
    }

    function withdraw(uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares)
    {
        shares = (IERC20(token).balanceOf(address(this)) * assets) / totalDeposited;
        _burn(owner, assets);
        totalDeposited -= assets;
        IERC20(token).transfer(receiver, shares);
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        if (totalDeposited == 0) return shares;
        return (shares * IERC20(token).balanceOf(address(this)) / totalDeposited);
    }

    /// Can artificially be increased by sending token to this contract
    function getPricePerFullShare() public view returns (uint256) {
        return totalDeposited == 0
            ? 10 ** decimals()
            : (IERC20(token).balanceOf(address(this)) * 10 ** decimals()) / totalDeposited;
    }

    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
