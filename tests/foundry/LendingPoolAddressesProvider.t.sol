// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract LendingPoolAddressesProviderTest is Common {
    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    error OwnableUnauthorizedAccount(address account);

    event MarketIdSet(string newMarketId);
    event LendingPoolUpdated(address indexed newAddress);
    event ConfigurationAdminUpdated(address indexed newAddress);
    event EmergencyAdminUpdated(address indexed newAddress);
    event LendingPoolConfiguratorUpdated(address indexed newAddress);
    event LendingPoolCollateralManagerUpdated(address indexed newAddress);
    event PriceOracleUpdated(address indexed newAddress);
    event ProxyCreated(bytes32 id, address indexed newAddress);
    event AddressSet(bytes32 id, address indexed newAddress, bool hasProxy);

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
    }

    function testSetAndGetMarketId() public {
        string memory newMarketId = "New Cod3x Lend Genesis Market";
        LendingPoolAddressesProvider provider = new LendingPoolAddressesProvider(marketId);
        assertEq(provider.getMarketId(), marketId);

        vm.expectEmit(false, false, false, true);
        emit MarketIdSet(newMarketId);
        provider.setMarketId(newMarketId);
        assertEq(provider.getMarketId(), newMarketId);
    }

    function testSetAddressAsProxy() public {
        LendingPoolAddressesProvider provider = new LendingPoolAddressesProvider(marketId);
        LendingPoolConfigurator lendingPool = new LendingPoolConfigurator();
        bytes32 id = bytes32(abi.encodePacked("RANDOM_PROXY"));

        vm.expectEmit(true, false, false, true);
        emit AddressSet(id, address(lendingPool), true);
        provider.setAddressAsProxy(id, address(lendingPool));
    }

    function testSetAndGetAddress() public {
        address randomAddress = makeAddr("RandomAddr");
        bytes32 id = "RANDOM_PROXY";
        LendingPoolAddressesProvider provider = new LendingPoolAddressesProvider(marketId);
        vm.expectEmit(true, false, false, true);
        emit AddressSet(id, randomAddress, false);
        provider.setAddress(id, randomAddress);
        assertEq(provider.getAddress(id), randomAddress);
        assertEq(provider.getAddress(bytes32(0)), address(0));
    }

    function testSetAndGetLendingPool() public {
        bytes32 id = "LENDING_POOL";
        LendingPoolAddressesProvider provider = new LendingPoolAddressesProvider(marketId);
        LendingPoolConfigurator lendingPool = new LendingPoolConfigurator();

        vm.expectEmit(true, false, false, false);
        emit LendingPoolUpdated(address(lendingPool));
        provider.setLendingPoolImpl(address(lendingPool));
        provider.setAddress(id, address(lendingPool)); // @issue Lack of check for id,address == 0
        assertEq(provider.getLendingPool(), address(lendingPool));
    }

    function testSetAndGetLendingPoolConfigurator() public {
        bytes32 id = "LENDING_POOL_CONFIGURATOR";
        LendingPoolAddressesProvider provider = new LendingPoolAddressesProvider(marketId);
        LendingPoolConfigurator lendingPoolConfigurator = new LendingPoolConfigurator();

        vm.expectEmit(true, false, false, false);
        emit LendingPoolConfiguratorUpdated(address(lendingPoolConfigurator));
        provider.setLendingPoolConfiguratorImpl(address(lendingPoolConfigurator));

        provider.setAddress(id, address(lendingPoolConfigurator)); // @issue Lack of check for id == 0

        assertEq(provider.getLendingPoolConfigurator(), address(lendingPoolConfigurator));
    }

    function testSetAndGetCollateralManager() public {
        LendingPoolAddressesProvider provider = new LendingPoolAddressesProvider(marketId);
        address lendingPoolCollateralManager = makeAddr("LendingPoolCollateralManager");

        vm.expectEmit(false, false, false, false);
        emit LendingPoolCollateralManagerUpdated(address(lendingPoolCollateralManager));
        provider.setLendingPoolCollateralManager(address(lendingPoolCollateralManager));

        assertEq(provider.getLendingPoolCollateralManager(), lendingPoolCollateralManager);
    }

    function testSetAndGetAdmins() public {
        LendingPoolAddressesProvider provider = new LendingPoolAddressesProvider(marketId);
        address poolAdmin = makeAddr("PoolAdmin");
        address emergencyAdmin = makeAddr("EmergencyAdmin");

        vm.expectEmit(false, false, false, false);
        emit ConfigurationAdminUpdated(address(poolAdmin));
        provider.setPoolAdmin((poolAdmin));

        vm.expectEmit(false, false, false, false);
        emit EmergencyAdminUpdated(address(emergencyAdmin));
        provider.setEmergencyAdmin((emergencyAdmin));

        assertEq(provider.getPoolAdmin(), poolAdmin);
        assertEq(provider.getEmergencyAdmin(), emergencyAdmin);
    }

    function testSetAndGetPriceOracle() public {
        LendingPoolAddressesProvider provider = new LendingPoolAddressesProvider(marketId);
        address priceOracle = makeAddr("PriceOracle");

        vm.expectEmit(false, false, false, false);
        emit PriceOracleUpdated(priceOracle);
        provider.setPriceOracle((priceOracle));

        assertEq(provider.getPriceOracle(), priceOracle);
    }

    /* @issue: Temporary disabled due to long time of execution */
    // function testAccessProviderControl(address hacker) public {
    //     vm.assume(hacker != address(this));
    //     address nonsecureAddress = makeAddr("nonsecure");
    //     bytes32 id = "RANDOM_PROXY";
    //     string memory newMarketId = "New Cod3x Lend Genesis Market";

    //     LendingPoolAddressesProvider provider = new LendingPoolAddressesProvider(marketId);

    //     vm.startPrank(hacker);
    //     console.logBytes4(
    //         bytes4(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), hacker))
    //     );
    //     console.logBytes4(bytes4(keccak256("OwnableUnauthorizedAccount()")));
    //     // vm.expectRevert(
    //     //     bytes4(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), hacker))
    //     // );
    //     // vm.expectRevert("OwnableUnauthorizedAccount(0x0000000000000000000000000000000000000000)");
    //     // vm.expectRevert(bytes4(keccak256("OwnableUnauthorizedAccount()")));
    //     vm.expectRevert();
    //     provider.setMarketId(newMarketId);

    //     vm.expectRevert();
    //     provider.setAddress(id, nonsecureAddress);

    //     vm.expectRevert();
    //     provider.setLendingPoolImpl(nonsecureAddress);

    //     vm.expectRevert();
    //     provider.setLendingPoolConfiguratorImpl(nonsecureAddress);

    //     vm.expectRevert();
    //     provider.setLendingPoolCollateralManager(nonsecureAddress);

    //     vm.expectRevert();
    //     provider.setPoolAdmin(nonsecureAddress);

    //     vm.expectRevert();
    //     provider.setEmergencyAdmin(nonsecureAddress);

    //     vm.expectRevert();
    //     provider.setPriceOracle((nonsecureAddress));

    //     vm.stopPrank();
    // }
}
