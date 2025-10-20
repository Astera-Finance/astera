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
import {IVariableDebtToken} from "contracts/interfaces/IVariableDebtToken.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";

contract TestResetLiquidityIndexTest is Test {
    address constant DATA_PROVIDER = 0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e;

    address constant LENDING_POOL_CONFIGURATOR = 0x5af0d031A3dA7c2D3b1fA9F00683004F176c28d0;
    address constant ADMIN = 0x7D66a2e916d79c0988D41F1E50a1429074ec53a4;
    address constant EMERGENCY = 0xDa77d6C0281fCb3e41BD966aC393502a1C524224;

    address constant LENDING_POOL_ADDRESSES_PROVIDER = 0x9a460e7BD6D5aFCEafbE795e05C48455738fB119;
    address constant LENDING_POOL_PROXY = 0x17d8a5305A37fe93E13a28f09c46db5bE24E1B9E;

    address constant USDT = 0xA219439258ca9da29E9Cc4cE5596924745e12B93;
    address constant ASUSDT = 0xD66aD16105B0805e18DdAb6bF7792c4704568827;
    address constant VDUSDT = 0x1Cc0D772B187693Ebf20107E44aC7F1029578e1F;
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
        vm.startPrank(ADMIN);
        ILendingPoolAddressesProvider(LENDING_POOL_ADDRESSES_PROVIDER).setLendingPoolImpl(
            address(newLendingPool)
        );
        vm.stopPrank();

        // Unpause pool
        vm.startPrank(EMERGENCY);
        ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setPoolPause(false);
        vm.stopPrank();

        // Initial admin as-USDT balance
        console2.log("Initial admin as-USDT balance: ", IAToken(ASUSDT).balanceOf(ADMIN));
        // Initial USDT balance
        console2.log("Initial admin USDT balance: ", IERC20Detailed(USDT).balanceOf(ADMIN));
        // Initial total supply
        console2.log("Initial total supply: ", IAToken(ASUSDT).totalSupply());
        // Initial asToken balance
        console2.log("Initial asToken USDT balance: ", IERC20Detailed(USDT).balanceOf(ASUSDT));
        // Initial variable debt toota supply
        console2.log("Initial variable debt total supply: ", IVariableDebtToken(VDUSDT).totalSupply());
        // Initial liquidity index
        console2.log("Initial liquidity index: ", IAToken(ASUSDT).convertToAssets(1e27));

        // Update index
        vm.startPrank(ADMIN);
        LendingPoolV2(LENDING_POOL_PROXY).setIndexUsdt(NEW_LQUIDITY_INDEX);

        // Mint as-USDT
        LendingPoolV2(LENDING_POOL_PROXY).mintDonatedAmountToTreasury(USDT, true);

        // Withdraw USDT
        LendingPoolV2(LENDING_POOL_PROXY).withdraw(USDT, true, type(uint256).max, ADMIN);
        vm.stopPrank();

        // Final admin as-USDT balance
        console2.log("Final admin as-USDT balance: ", IAToken(ASUSDT).balanceOf(ADMIN));
        // Final USDT balance
        console2.log("Final admin USDT balance: ", IERC20Detailed(USDT).balanceOf(ADMIN));
        // Final total supply
        console2.log("Final total supply: ", IAToken(ASUSDT).totalSupply());
        // Final asToken balance
        console2.log("Final asToken USDT balance: ", IERC20Detailed(USDT).balanceOf(ASUSDT));
        // Final variable debt toota supply
        console2.log("Final variable debt total supply: ", IVariableDebtToken(VDUSDT).totalSupply());
        // Final liquidity index
        console2.log("Final liquidity index: ", IAToken(ASUSDT).convertToAssets(1e27));

        assertEq(IAToken(ASUSDT).convertToAssets(1e27), NEW_LQUIDITY_INDEX);
        assertEq(IAToken(ASUSDT).totalSupply(), IERC20Detailed(USDT).balanceOf(ASUSDT) + IVariableDebtToken(VDUSDT).totalSupply());
    }
}
