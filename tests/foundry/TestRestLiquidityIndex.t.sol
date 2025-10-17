// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {
    AsteraDataProvider2,
    UserReserveData
} from "contracts/misc/AsteraDataProvider2.sol";
import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IERC20Detailed} from "contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
// import {MiniPoolV2} from "contracts/protocol/core/minipool/MiniPoolV2.sol";
import {LendingPoolV2} from "contracts/protocol/core/lendingpool/LendingPoolV2.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";

contract TestResetLiquidityIndexTest is Test {
    address constant DATA_PROVIDER = 0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e;

    address constant LENDING_POOL_CONFIGURATOR = 0x5af0d031A3dA7c2D3b1fA9F00683004F176c28d0;
    address constant ADMIN = 0x7D66a2e916d79c0988D41F1E50a1429074ec53a4;
    address constant EMERGENCY = 0xDa77d6C0281fCb3e41BD966aC393502a1C524224;

    address constant LENDING_POOL_ADDRESSES_PROVIDER = 0x9a460e7BD6D5aFCEafbE795e05C48455738fB119;
    address constant LENDING_POOL_PROXY = 0x17d8a5305A37fe93E13a28f09c46db5bE24E1B9E;

    address constant USDT = 0xA219439258ca9da29E9Cc4cE5596924745e12B93;
    uint128 constant NEW_LQUIDITY_INDEX = 1050000000000000000000000000;

    function setUp() public {
        // LINEA setup
        string memory lineaRpc = vm.envString("LINEA_RPC_URL");
        uint256 lineaFork = vm.createSelectFork(lineaRpc);
        assertEq(vm.activeFork(), lineaFork);
    }

    function testResetLiquidiyIndex() public {
        LendingPoolV2 newLendingPool = new LendingPoolV2();

        // Upgrade pool impl
        vm.prank(ADMIN);
        ILendingPoolAddressesProvider(LENDING_POOL_ADDRESSES_PROVIDER).setLendingPoolImpl(
            address(newLendingPool)
        );

        // Unpause pool
        vm.startPrank(EMERGENCY);
        ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setPoolPause(false);
        vm.stopPrank();

        // Update index
        vm.prank(ADMIN);
        newLendingPool.setIndexUsdt(NEW_LQUIDITY_INDEX);
        vm.stopPrank();

        // Mint as-USDT
        vm.prank(ADMIN);
        newLendingPool.mintDonatedAmountToTreasury(USDT, true);
        vm.stopPrank();

        // Initial USDT balance
        console2.log("Initial USDT balance: ", IERC20Detailed(USDT).balanceOf(ADMIN));

        // Withdraw USDT
        vm.prank(ADMIN);
        newLendingPool.withdraw(USDT, true, type(uint256).max, ADMIN);
        vm.stopPrank();

        // Final USDT balance
        console2.log("Final USDT balance: ", IERC20Detailed(USDT).balanceOf(ADMIN));

    }
}
