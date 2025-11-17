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
            address(deployedContracts.asteraDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(commonContracts.aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        commonContracts.mockedVaults =
            fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));
        (miniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.asteraDataProvider),
            miniPoolContracts
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] =
                    address(commonContracts.aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }

        configAddresses.asteraDataProvider = address(miniPoolContracts.miniPoolAddressesProvider);
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
            console2.log("1. Impl: ", miniPoolImpl);
            console2.log(
                "1. aToken6909Impl", miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0)
            );
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(miniPoolImpl, 0);
            address aToken6909Proxy = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
            console2.log("2. aToken6909Impl", aToken6909Proxy);
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
            console2.log("Revert 1");
            vm.expectRevert(bytes(Errors.PAP_POOL_ID_OUT_OF_RANGE));
            miniPoolAddressesProvider.setMiniPoolImpl(miniPoolImpl, 0);

            /* Test setting impl with older or the same version (shall revert) */
            console2.log("Revert 2");
            vm.expectRevert();
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(miniPoolImpl, 0);

            /* Test setting of the same address (shall revert) */
            console2.log("Revert 3");
            miniPoolImpl = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
            vm.expectRevert();
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(miniPoolImpl, 0);

            /* Set with Id out of range */
            console2.log("Revert 4");
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
            console2.log("1. Impl: ", aToken6909Impl);
            console2.log(
                "1. aToken6909Impl",
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(0)
            );
            miniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(aToken6909Impl, 0);
            address aToken6909Proxy =
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(0);
            console2.log("2. aToken6909Impl", aToken6909Proxy);
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
            console2.log("Revert 1");
            vm.expectRevert(bytes(Errors.PAP_POOL_ID_OUT_OF_RANGE));
            miniPoolAddressesProvider.setAToken6909Impl(aToken6909Impl, 0);

            /* Test setting impl with older or the same version (shall revert) */
            console2.log("Revert 2");
            vm.expectRevert();
            miniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(aToken6909Impl, 0);

            /* Test setting of the same address (shall revert) */
            console2.log("Revert 3");
            aToken6909Impl = miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(0);
            vm.expectRevert();
            miniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(aToken6909Impl, 0);

            /* Set with Id out of range */
            console2.log("Revert 4");
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
            console2.log("1. Impl: ", miniPoolConfigImpl);
            console2.log(
                "1. MiniPoolConfigurator",
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator()
            );
            miniPoolContracts.miniPoolAddressesProvider.setMiniPoolConfigurator(miniPoolConfigImpl);
            address miniPoolConfigProxy =
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator();
            console2.log("2. MiniPoolConfigurator", miniPoolConfigProxy);
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
            console2.log("3. Impl: ", miniPoolConfigImpl);
            console2.log(
                "3. MiniPoolConfigurator", miniPoolAddressesProvider.getMiniPoolConfigurator()
            );
            miniPoolAddressesProvider.setMiniPoolConfigurator(miniPoolConfigImpl);
            address miniPoolConfigProxy = miniPoolAddressesProvider.getMiniPoolConfigurator();
            console2.log("2. MiniPoolConfigurator", miniPoolConfigProxy);
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
            console2.log(
                "1. Treasury",
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolAsteraTreasury()
            );
            vm.prank(address(miniPoolContracts.miniPoolConfigurator));
            miniPoolContracts.miniPoolAddressesProvider.setAsteraTreasury(treasury);
            console2.log(
                "2. Treasury",
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolAsteraTreasury()
            );
            assertEq(
                miniPoolContracts.miniPoolAddressesProvider.getMiniPoolAsteraTreasury(),
                treasury,
                "Wrong treasury"
            );
        }

        /* ***** Flow limit ***** */
        {
            uint256 flowLimit;
            flowLimit = bound(
                flowLimit,
                miniPoolContracts.flowLimiter
                    .currentFlow(tokens[0], address(miniPoolContracts.miniPoolImpl)) + 1,
                1e27
            );

            console2.log(
                "1. FlowLimit",
                miniPoolContracts.flowLimiter
                    .getFlowLimit(tokens[0], address(miniPoolContracts.miniPoolImpl))
            );
            vm.prank(address(miniPoolContracts.miniPoolConfigurator));
            miniPoolContracts.miniPoolAddressesProvider
                .setFlowLimit(tokens[0], address(miniPool), flowLimit);
            console2.log(
                "2. FlowLimit",
                miniPoolContracts.flowLimiter.getFlowLimit(tokens[0], address(miniPool))
            );
            assertEq(
                miniPoolContracts.flowLimiter.getFlowLimit(tokens[0], address(miniPool)),
                flowLimit,
                "Wrong limits"
            );
        }
    }

    function testSetFlowLimitMax() public {
        uint256 numberOfReservesWithFlowBorrowing =
            miniPoolContracts.miniPoolAddressesProvider.getNumberOfReservesWithFlowBorrowing();
        uint256 maxReservesWithFlowBorrowing =
            miniPoolContracts.miniPoolAddressesProvider.getMaxReservesWithFlowBorrowing();

        assertEq(
            numberOfReservesWithFlowBorrowing, 0, "Wrong number of reserves with flow borrowing"
        );
        assertEq(maxReservesWithFlowBorrowing, 6, "Wrong max reserves with flow borrowing");

        vm.prank(address(miniPoolContracts.miniPoolConfigurator));
        miniPoolContracts.miniPoolAddressesProvider.setFlowLimit(tokens[0], address(miniPool), 1000);

        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getNumberOfReservesWithFlowBorrowing(),
            1,
            "Wrong number of reserves with flow borrowing"
        );
        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getMaxReservesWithFlowBorrowing(),
            6,
            "Wrong max reserves with flow borrowing"
        );

        vm.prank(address(miniPoolContracts.miniPoolConfigurator));
        miniPoolContracts.miniPoolAddressesProvider.setFlowLimit(tokens[1], address(miniPool), 1000);

        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getNumberOfReservesWithFlowBorrowing(),
            2,
            "Wrong number of reserves with flow borrowing"
        );
        vm.expectRevert(bytes(Errors.VL_INVALID_INPUT));
        miniPoolContracts.miniPoolAddressesProvider.setMaxReservesWithFlowBorrowing(1);

        miniPoolContracts.miniPoolAddressesProvider.setMaxReservesWithFlowBorrowing(2);

        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getMaxReservesWithFlowBorrowing(),
            2,
            "Wrong max reserves with flow borrowing"
        );

        vm.prank(address(miniPoolContracts.miniPoolConfigurator));
        vm.expectRevert(bytes(Errors.VL_MAX_RESERVES_WITH_FLOW_BORROWING_REACHED));
        miniPoolContracts.miniPoolAddressesProvider.setFlowLimit(tokens[2], address(miniPool), 1000);

        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getNumberOfReservesWithFlowBorrowing(),
            2,
            "Wrong number of reserves with flow borrowing"
        );

        vm.prank(address(miniPoolContracts.miniPoolConfigurator));
        miniPoolContracts.miniPoolAddressesProvider.setFlowLimit(tokens[1], address(miniPool), 0);

        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getNumberOfReservesWithFlowBorrowing(),
            1,
            "Wrong number of reserves with flow borrowing"
        );

        vm.prank(address(miniPoolContracts.miniPoolConfigurator));
        miniPoolContracts.miniPoolAddressesProvider.setFlowLimit(tokens[0], address(miniPool), 0);

        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getNumberOfReservesWithFlowBorrowing(),
            0,
            "Wrong number of reserves with flow borrowing"
        );

        // vm.prank(address(miniPoolContracts.miniPoolConfigurator));
        miniPoolContracts.miniPoolAddressesProvider.setMaxReservesWithFlowBorrowing(0);

        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getMaxReservesWithFlowBorrowing(),
            0,
            "Wrong max reserves with flow borrowing"
        );
    }

    function testMultipleDeployments() public {
        address miniPoolImpl = address(new MiniPool());
        address aTokenImpl = address(new ATokenERC6909());

        address lastMiniPoolImpl = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
        address lastAToken6909Impl =
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(0);

        address[] memory miniPoolList =
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolList();

        miniPoolContracts.miniPoolAddressesProvider.deployMiniPool(miniPoolImpl, aTokenImpl, admin);

        assertTrue(
            lastMiniPoolImpl != miniPoolContracts.miniPoolAddressesProvider.getMiniPool(1),
            "LastMiniPoolImpl not updated"
        );
        assertTrue(
            lastAToken6909Impl
                != miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(1),
            "LastAToken6909Impl not updated"
        );
        miniPoolList = miniPoolContracts.miniPoolAddressesProvider.getMiniPoolList();
        assertEq(miniPoolList.length, 2, "Wrong mini pools number");
        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider));
        assertEq(
            InitializableImmutableAdminUpgradeabilityProxy(payable(miniPoolList[1]))
                .implementation(),
            miniPoolImpl,
            "Wrong implementation after deployment"
        );

        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPoolList[1]),
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(1),
            "Wrong AToken implementation after deployment"
        );

        assertEq(
            1,
            miniPoolContracts.miniPoolAddressesProvider
                .getMiniPoolId(miniPoolContracts.miniPoolAddressesProvider.getMiniPool(1))
        );
        /* getMiniPool shall revert when id not found */
        vm.expectRevert(bytes(Errors.PAP_NO_MINI_POOL_ID_FOR_ADDRESS));
        miniPoolContracts.miniPoolAddressesProvider.getMiniPoolId(makeAddr("Random"));
    }

    function testAccessControlOfSetters(uint256 randomNumber) public {
        address randomAddress = makeAddr("randomAddress");
        bytes32 randomBytes = (bytes32("randomBytes"));
        randomNumber = bound(randomNumber, 1, 100);
        address mockedContractToUpdate = address(new MockedContractToUpdate());
        address miniPool = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);

        /* Only owner */
        vm.startPrank(address(this));
        miniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(mockedContractToUpdate, 0);
        miniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(mockedContractToUpdate, 0);
        miniPoolContracts.miniPoolAddressesProvider.setAddress(randomBytes, randomAddress);
        miniPoolContracts.miniPoolAddressesProvider
            .deployMiniPool(mockedContractToUpdate, mockedContractToUpdate, randomAddress);
        miniPoolContracts.miniPoolAddressesProvider.setMiniPoolConfigurator(mockedContractToUpdate);
        vm.stopPrank();

        /* Only configurator */
        vm.startPrank(address(miniPoolContracts.miniPoolConfigurator));
        miniPoolContracts.miniPoolAddressesProvider
            .setFlowLimit(address(erc20Tokens[0]), miniPool, randomNumber);
        miniPoolContracts.miniPoolAddressesProvider.setPoolAdmin(0, randomAddress);
        miniPoolContracts.miniPoolAddressesProvider.setAsteraTreasury(address(0));
        miniPoolContracts.miniPoolAddressesProvider
            .setMinipoolOwnerTreasuryToMiniPool(0, randomAddress);
        vm.stopPrank();

        vm.startPrank(randomAddress);
        // vm.expectRevert("OwnableUnauthorizedAccount(0xe899D4fE48da746223F9Ad56f1511FB146EC86fF)");
        // vm.expectRevert(
        //     bytes4(
        //         abi.encodeWithSelector(
        //             bytes4(keccak256("OwnableUnauthorizedAccount(address)")), randomAddress
        //         )
        //     )
        // );
        vm.expectRevert();
        miniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(mockedContractToUpdate, 0);
        vm.expectRevert();
        miniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(mockedContractToUpdate, 0);
        vm.expectRevert();
        miniPoolContracts.miniPoolAddressesProvider.setAddress(randomBytes, randomAddress);
        vm.expectRevert();
        miniPoolContracts.miniPoolAddressesProvider
            .deployMiniPool(mockedContractToUpdate, mockedContractToUpdate, randomAddress);
        vm.expectRevert();
        miniPoolContracts.miniPoolAddressesProvider.setMiniPoolConfigurator(mockedContractToUpdate);

        vm.expectRevert(bytes(Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR));
        miniPoolContracts.miniPoolAddressesProvider
            .setFlowLimit(address(erc20Tokens[0]), miniPool, randomNumber);
        vm.expectRevert(bytes(Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR));
        miniPoolContracts.miniPoolAddressesProvider.setPoolAdmin(0, randomAddress);
        vm.expectRevert(bytes(Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR));
        miniPoolContracts.miniPoolAddressesProvider.setAsteraTreasury(address(0));
        vm.expectRevert(bytes(Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR));
        miniPoolContracts.miniPoolAddressesProvider
            .setMinipoolOwnerTreasuryToMiniPool(0, randomAddress);
        vm.stopPrank();
    }
}
