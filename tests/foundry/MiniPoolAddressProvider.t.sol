// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
// import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
// import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
// import {ReserveConfiguration} from "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

import "forge-std/StdUtils.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";



contract MiniPoolAddressProvider is Common {
    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    DeployedMiniPoolContracts miniPoolContracts;

    ConfigAddresses configAddresses;
    address aTokensErc6909Addr;
    address miniPool;

    uint256[] grainTokenIds = [1000, 1001, 1002, 1003];
    uint256[] tokenIds = [1128, 1129, 1130, 1131];

    function setUp() public {
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
        mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));
        miniPoolContracts = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider), address(deployedContracts.lendingPool)
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] = address(aTokens[idx - tokens.length]);
            }
        }

        miniPool = fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts);
        vm.label(miniPool, "MiniPool");

    }


    function testSetMiniPoolConfigurator() public{
        MiniPoolAddressesProvider miniPoolAddressesProvider =
            new MiniPoolAddressesProvider(ILendingPoolAddressesProvider(address(deployedContracts.lendingPoolAddressesProvider)));
        address miniPoolConfigIMPL = address(new MiniPoolConfigurator());
        console.log("1. MiniPoolConfigurator", miniPoolAddressesProvider.getMiniPoolConfigurator());
        //@issue: MiniPoolConfiurator is not set during initialization and cannot be updated 
        miniPoolAddressesProvider.setMiniPoolConfigurator(address(miniPoolConfigIMPL));
        console.log("1. MiniPoolConfigurator", miniPoolAddressesProvider.getMiniPoolConfigurator());

        console.log("2. MiniPoolConfigurator", miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator());
        miniPoolContracts.miniPoolAddressesProvider.setMiniPoolConfigurator(address(miniPoolConfigIMPL));
        console.log("2. MiniPoolConfigurator", miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator());
        // miniPoolContracts.miniPoolAddressesProvider.setMiniPoolConfigurator(randomAddress);

    }
}