// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// import "contracts/interfaces/ILendingPool.sol";
// import "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import 'contracts/dependencies/openzeppelin/contracts/ERC20.sol';
import 'contracts/flashloan/base/FlashLoanReceiverBase.sol';

contract User is FlashLoanReceiverBase {
    
    constructor(ILendingPoolAddressesProvider _addressesProvider) FlashLoanReceiverBase(_addressesProvider) {}

    function proxy(
        address target,
        bytes memory data
    ) public returns (bool success, bytes memory err) {
        return target.call(data);
    }

    function approveERC20(IERC20 target, address spender) public {
        target.approve(spender, type(uint256).max);
    }

    function execFl(
        ILendingPool.FlashLoanParams memory flp,
        uint256[] calldata amounts, 
        uint256[] calldata modes, 
        bytes calldata params
    ) public {
        LENDING_POOL.flashLoan(
            flp,
            amounts,
            modes,
            params
        );

        for (uint256 i = 0; i < flp.assets.length; i++) {
            IERC20(flp.assets[i]).approve(address(LENDING_POOL), type(uint256).max);
        }
    }
    
    // flashloanable user
    function executeOperation(
        address[] calldata _assets,
        uint256[] calldata _amounts,
        uint256[] calldata _premiums,
        address _initiator,
        bytes calldata _params
    ) external returns (bool) {
        
        /// we make sur lending pool can transferFrom more than `_amounts[i] + _premiums[i]`.
        for (uint256 i = 0; i < _assets.length; i++) {
            IERC20(_assets[i]).approve(address(LENDING_POOL), _amounts[i] + _premiums[i]);
        }

        return true;
    }
}
