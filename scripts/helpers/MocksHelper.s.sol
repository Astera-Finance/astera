// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "contracts/mocks/tokens/MintableERC20.sol";
import "contracts/mocks/oracle/MockAggregator.sol";
import {Oracle} from "contracts/protocol/core/Oracle.sol";

contract MocksHelper {
    function _deployERC20Mocks(
        string[] memory names,
        string[] memory symbols,
        uint8[] memory decimals,
        int256[] memory prices
    ) internal returns (address[] memory, Oracle) {
        address[] memory tokens = new address[](names.length);
        address[] memory aggregators = new address[](names.length);
        uint256[] memory timeouts = new uint256[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            tokens[i] = address(_deployERC20Mock(names[i], symbols[i], decimals[i]));
            aggregators[i] = address(_deployMockAggregator(tokens[i], prices[i]));
            timeouts[i] = type(uint256).max;
        }
        //mock tokens, mock aggregators, fallbackOracle, baseCurrency, baseCurrencyUnit
        Oracle oracle =
            _deployOracle(tokens, aggregators, timeouts, address(0), address(0), 100000000);
        return (tokens, oracle);
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

    function _deployOracle(
        address[] memory assets,
        address[] memory sources,
        uint256[] memory timeouts,
        address fallbackOracle,
        address baseCurrency,
        uint256 baseCurrencyUnit
    ) internal returns (Oracle) {
        Oracle oracle =
            new Oracle(assets, sources, timeouts, fallbackOracle, baseCurrency, baseCurrencyUnit);
        return oracle;
    }
}
