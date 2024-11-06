// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {LendingPoolConfigurator} from
    "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import {MiniPoolConfigurator} from "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import "forge-std/StdUtils.sol";
import {MathUtils} from "contracts/protocol/libraries/math/MathUtils.sol";
import "./LendingPoolFixtures.t.sol";
import "./MiniPoolFixtures.t.sol";

contract Cod3xLendDataProvider is MiniPoolFixtures, LendingPoolFixtures {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    ERC20[] erc20Tokens;

    function setUp() public override(MiniPoolFixtures, LendingPoolFixtures) {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.protocolDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        mockedVaults = fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));
        miniPoolContracts = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool)
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] = address(aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        configAddresses.protocolDataProvider = address(miniPoolContracts.miniPoolAddressesProvider);
        configAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool = fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts);
        vm.label(miniPool, "MiniPool");
    }

    function testGetLpReserveStaticData(uint256 usdcDepositAmount) public {
        TokenTypes memory usdcTypes = TokenTypes({
            token: erc20Tokens[0],
            aToken: aTokens[0],
            debtToken: variableDebtTokens[0]
        });

        TokenTypes memory wbtcTypes = TokenTypes({
            token: erc20Tokens[1],
            aToken: aTokens[1],
            debtToken: variableDebtTokens[1]
        });
        fixture_depositAndBorrow(
            usdcTypes, wbtcTypes, address(this), address(this), usdcDepositAmount
        );
    }
}
