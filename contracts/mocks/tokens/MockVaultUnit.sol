//SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.20;

import {
    IERC20,
    ERC20,
    IERC20Metadata
} from "../../../contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {Math} from "../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";

contract MockVaultUnit is ERC20 {
    using Math for uint256;

    IERC20 private immutable _asset;
    uint8 private immutable _underlyingDecimals;

    /**
     * @dev Attempted to withdraw more assets than the max amount for `receiver`.
     */
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

    /**
     * @dev Attempted to deposit more assets than the max amount for `receiver`.
     */
    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    constructor(IERC20 asset_) ERC20("MockVaultUnit", "UnitVault") {
        (bool success, uint8 assetDecimals) = _tryGetAssetDecimals(asset_);
        _underlyingDecimals = success ? assetDecimals : 18;
        _asset = asset_;
    }

    /**
     * @dev See {IERC4626-totalAssets}.
     */
    function totalAssets() public view virtual returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /**
     * @dev See {IERC4626-convertToShares}.
     */
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /**
     * @dev See {IERC4626-convertToAssets}.
     */
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /**
     * @dev See {IERC4626-maxDeposit}.
     */
    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    /**
     * @dev See {IERC4626-previewDeposit}.
     */
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /**
     * @dev Attempts to fetch the asset decimals. A return value of false indicates that the attempt failed in some way.
     */
    function _tryGetAssetDecimals(IERC20 asset_) private view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) =
            address(asset_).staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }

    /**
     * @dev See {IERC4626-withdraw}.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        returns (uint256)
    {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @dev See {IERC4626-previewWithdraw}.
     */
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);
        SafeERC20.safeTransfer(_asset, receiver, assets);

        // emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev See {IERC4626-deposit}.
     */
    function deposit(uint256 assets, address receiver) public virtual returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
    {
        // If _asset is ERC777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        _mint(receiver, shares);
    }

    /**
     * @dev See {IERC4626-maxWithdraw}.
     */
    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
    }

    function asset() external view returns (address) {
        return address(_asset);
    }
}
