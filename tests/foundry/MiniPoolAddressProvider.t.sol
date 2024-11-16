// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import "forge-std/StdUtils.sol";
import {MockedContractToUpdate} from "contracts/mocks/dependencies/MockedContractToUpdate.sol";

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
            address(deployedContracts.cod3xLendDataProvider),
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
        (miniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            address(0)
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] = address(aTokens[idx - tokens.length]);
            }
        }

        configAddresses.cod3xLendDataProvider = address(miniPoolContracts.miniPoolAddressesProvider);
        configAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts, 0);
        vm.label(miniPool, "MiniPool");
    }

    function testSetMiniPoolImpl() public {
        /* Test update of existing impl */
        {
            address miniPoolImpl = address(new MockedContractToUpdate()); // Second version of aToken6909
            /* Test update */
            console.log("1. Impl: ", miniPoolImpl);
            console.log(
                "1. aToken6909Impl", miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0)
            );
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(miniPoolImpl, 0);
            address aToken6909Proxy = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
            console.log("2. aToken6909Impl", aToken6909Proxy);
            vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider));
            assertEq(
                miniPoolImpl,
                InitializableImmutableAdminUpgradeabilityProxy(payable((aToken6909Proxy)))
                    .implementation(),
                "1 Wrong aToken"
            );
            vm.stopPrank();
        }
        /* Reverts */
        {
            MiniPoolAddressesProvider miniPoolAddressesProvider = new MiniPoolAddressesProvider(
                ILendingPoolAddressesProvider(
                    address(deployedContracts.lendingPoolAddressesProvider)
                )
            );
            address miniPoolImpl = address(new MiniPool());

            /* Set on not deployed miniPool */
            console.log("Revert 1");
            vm.expectRevert(bytes(Errors.PAP_POOL_ID_OUT_OF_RANGE));
            miniPoolAddressesProvider.setMiniPoolImpl(miniPoolImpl, 0);

            /* Test setting impl with older or the same version (shall revert) */
            console.log("Revert 2");
            vm.expectRevert();
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(miniPoolImpl, 0);

            /* Test setting of the same address (shall revert) */
            console.log("Revert 3");
            miniPoolImpl = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
            vm.expectRevert();
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(miniPoolImpl, 0);

            /* Set with Id out of range */
            console.log("Revert 4");
            address newMiniPoolImpl = address(new MockedContractToUpdate());
            vm.expectRevert(bytes(Errors.PAP_POOL_ID_OUT_OF_RANGE));
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(newMiniPoolImpl, 2);
        }
    }

    function testSetAToken6909Impl() public {
        /* Test update of existing impl */
        {
            address aToken6909Impl = address(new MockedContractToUpdate()); // Second version of aToken6909
            /* Test update */
            console.log("1. Impl: ", aToken6909Impl);
            console.log(
                "1. aToken6909Impl", miniPoolContracts.miniPoolAddressesProvider.getAToken6909(0)
            );
            miniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(aToken6909Impl, 0);
            address aToken6909Proxy = miniPoolContracts.miniPoolAddressesProvider.getAToken6909(0);
            console.log("2. aToken6909Impl", aToken6909Proxy);
            vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider));
            assertEq(
                aToken6909Impl,
                InitializableImmutableAdminUpgradeabilityProxy(payable((aToken6909Proxy)))
                    .implementation(),
                "1 Wrong aToken"
            );
            vm.stopPrank();
        }
        /* Reverts */
        {
            MiniPoolAddressesProvider miniPoolAddressesProvider = new MiniPoolAddressesProvider(
                ILendingPoolAddressesProvider(
                    address(deployedContracts.lendingPoolAddressesProvider)
                )
            );
            address aToken6909Impl = address(new ATokenERC6909());

            /* Set on not deployed miniPool */
            console.log("Revert 1");
            vm.expectRevert(bytes(Errors.PAP_POOL_ID_OUT_OF_RANGE));
            miniPoolAddressesProvider.setAToken6909Impl(aToken6909Impl, 0);

            /* Test setting impl with older or the same version (shall revert) */
            console.log("Revert 2");
            vm.expectRevert();
            miniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(aToken6909Impl, 0);

            /* Test setting of the same address (shall revert) */
            console.log("Revert 3");
            aToken6909Impl = miniPoolContracts.miniPoolAddressesProvider.getAToken6909(0);
            vm.expectRevert();
            miniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(aToken6909Impl, 0);

            /* Set with Id out of range */
            console.log("Revert 4");
            address newAToken6909Impl = address(new MockedContractToUpdate());
            vm.expectRevert(bytes(Errors.PAP_POOL_ID_OUT_OF_RANGE));
            miniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(newAToken6909Impl, 2);
        }
    }

    function testSetMiniPoolConfigurator() public {
        MiniPoolAddressesProvider miniPoolAddressesProvider = new MiniPoolAddressesProvider(
            ILendingPoolAddressesProvider(address(deployedContracts.lendingPoolAddressesProvider))
        );
        /* Test update of existing impl */
        {
            address miniPoolConfigImpl = address(new MockedContractToUpdate()); // Second version of MiniPoolConfig
            /* Test update */
            console.log("1. Impl: ", miniPoolConfigImpl);
            console.log(
                "1. MiniPoolConfigurator",
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator()
            );
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolConfigurator(miniPoolConfigImpl);
            address miniPoolConfigProxy =
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator();
            console.log("2. MiniPoolConfigurator", miniPoolConfigProxy);
            vm.prank(address(miniPoolContracts.miniPoolAddressesProvider));
            assertEq(
                InitializableImmutableAdminUpgradeabilityProxy(payable(miniPoolConfigProxy))
                    .implementation(),
                miniPoolConfigImpl,
                "Wrong mini pool configurator"
            );
        }
        /* Test initialization (with new address provider) */
        {
            address miniPoolConfigImpl = address(new MiniPoolConfigurator());
            console.log("3. Impl: ", miniPoolConfigImpl);
            console.log(
                "3. MiniPoolConfigurator", miniPoolAddressesProvider.getMiniPoolConfigurator()
            );
            miniPoolAddressesProvider.setMiniPoolConfigurator(miniPoolConfigImpl);
            address miniPoolConfigProxy = miniPoolAddressesProvider.getMiniPoolConfigurator();
            console.log("2. MiniPoolConfigurator", miniPoolConfigProxy);
            vm.prank(address(miniPoolAddressesProvider));
            assertEq(
                InitializableImmutableAdminUpgradeabilityProxy(payable(miniPoolConfigProxy))
                    .implementation(),
                miniPoolConfigImpl,
                "Wrong mini pool configurator"
            );
            /* Set IMPL again - expect revert */
            vm.expectRevert();
            miniPoolAddressesProvider.setMiniPoolConfigurator(address(miniPoolConfigImpl));
        }
    }

    function testSimpleSetters() public {
        // MiniPoolAddressesProvider miniPoolAddressesProvider = new MiniPoolAddressesProvider(
        //     ILendingPoolAddressesProvider(address(deployedContracts.lendingPoolAddressesProvider))
        // );
        /* ***** Treasury ***** */
        {
            address treasury = makeAddr("Treasury");
            console.log(
                "1. Treasury", miniPoolContracts.miniPoolAddressesProvider.getMiniPoolTreasury(0)
            );
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolToTreasury(0, treasury);
            console.log(
                "2. Treasury", miniPoolContracts.miniPoolAddressesProvider.getMiniPoolTreasury(0)
            );
            assertEq(
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolTreasury(0),
                treasury,
                "Wrong treasury"
            );
            /* Revert when try to get treasury from not existing id */
            vm.expectRevert(bytes(Errors.PAP_POOL_ID_OUT_OF_RANGE));
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolToTreasury(10, treasury);
        }

        /* ***** Flow limit ***** */
        {
            uint256 flowLimit;
            flowLimit = bound(
                flowLimit,
                miniPoolContracts.flowLimiter.currentFlow(
                    tokens[0], address(miniPoolContracts.miniPoolImpl)
                ) + 1,
                1e27
            );

            console.log(
                "1. FlowLimit",
                miniPoolContracts.flowLimiter.getFlowLimit(
                    tokens[0], address(miniPoolContracts.miniPoolImpl)
                )
            );
            miniPoolContracts.miniPoolAddressesProvider.setFlowLimit(
                tokens[0], address(miniPoolContracts.miniPoolImpl), flowLimit
            );
            console.log(
                "2. FlowLimit",
                miniPoolContracts.flowLimiter.getFlowLimit(
                    tokens[0], address(miniPoolContracts.miniPoolImpl)
                )
            );
            assertEq(
                miniPoolContracts.flowLimiter.getFlowLimit(
                    tokens[0], address(miniPoolContracts.miniPoolImpl)
                ),
                flowLimit,
                "Wrong limits"
            );
            // vm.expectRevert();
            // miniPoolAddressesProvider.setFlowLimit(
            //     tokens[0], address(miniPoolContracts.miniPoolImpl), flowLimit
            // );
        }
    }

    function testMultipleDeployments() public {
        address miniPoolImpl = address(new MiniPool());
        address aTokenImpl = address(new ATokenERC6909());

        address lastMiniPoolImpl = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
        address lastAToken6909Impl = miniPoolContracts.miniPoolAddressesProvider.getAToken6909(0);

        address[] memory miniPoolList =
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolList();

        miniPoolContracts.miniPoolAddressesProvider.deployMiniPool(miniPoolImpl, aTokenImpl);

        assertTrue(
            lastMiniPoolImpl != miniPoolContracts.miniPoolAddressesProvider.getMiniPool(1),
            "LastMiniPoolImpl not updated"
        );
        assertTrue(
            lastAToken6909Impl != miniPoolContracts.miniPoolAddressesProvider.getAToken6909(1),
            "LastAToken6909Impl not updated"
        );
        miniPoolList = miniPoolContracts.miniPoolAddressesProvider.getMiniPoolList();
        assertEq(miniPoolList.length, 2, "Wrong mini pools number");
        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider));
        assertEq(
            InitializableImmutableAdminUpgradeabilityProxy(payable(miniPoolList[1])).implementation(
            ),
            miniPoolImpl,
            "Wrong implementation after deployment"
        );

        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPoolList[1]),
            miniPoolContracts.miniPoolAddressesProvider.getAToken6909(1),
            "Wrong AToken implementation after deployment"
        );

        assertEq(
            1,
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolId(
                miniPoolContracts.miniPoolAddressesProvider.getMiniPool(1)
            )
        );
        /* getMiniPool shall revert when id not found */
        vm.expectRevert(bytes(Errors.PAP_NO_MINI_POOL_ID_FOR_ADDRESS));
        miniPoolContracts.miniPoolAddressesProvider.getMiniPoolId(makeAddr("Random"));
    }
}
