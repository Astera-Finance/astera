pragma solidity ^0.8.0;

import {ERC20} from "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {IERC20} from "contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IExternalContract} from "contracts/mocks/dependencies/IExternalContract.sol";

contract ExternalContract is IExternalContract {
    address public want;

    constructor(address _want) {
        want = _want;
    }

    function withdraw(uint256 _amount) external returns (uint256 returned) {
        IERC20(want).transfer(msg.sender, _amount);
        return _amount;
    }

    function withdrawAll() external returns (uint256) {
        IERC20(want).transfer(msg.sender, balance());
        return balance();
    }

    function deposit(uint256 _amount) public {
        IERC20(want).transferFrom(msg.sender, address(this), _amount);
    }

    function balance() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }
}
