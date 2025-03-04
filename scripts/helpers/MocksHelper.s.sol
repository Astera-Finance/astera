// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "contracts/mocks/tokens/MintableERC20.sol";
import "contracts/mocks/oracle/MockAggregator.sol";
import {Oracle} from "contracts/protocol/core/Oracle.sol";

contract MocksHelper {
    function _deployERC20Mocks(
        string[] memory names,
        string[] memory symbols,
        uint8[] memory decimals
    ) internal returns (address[] memory) {
        address[] memory tokens = new address[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            tokens[i] = address(_deployERC20Mock(names[i], symbols[i], decimals[i]));
        }
        return tokens;
    }

    function _deployERC20Mock(string memory name, string memory symbol, uint8 decimals)
        internal
        returns (MintableERC20)
    {
        MintableERC20 token = new MintableERC20(name, symbol, decimals);
        return token;
    }

    function _deployMockAggregator(address token, int256 price) internal returns (MockAggregator) {
        MockAggregator aggregator =
            new MockAggregator(price, int256(int8(MintableERC20(token).decimals())));
        return aggregator;
    }
}
