// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AggregatedMiniPoolReservesData} from "contracts/interfaces/IAsteraDataProvider2.sol";
import {MiniPoolDefaultReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {
    AsteraDataProvider2,
    MiniPoolUserReserveData,
    UserReserveData
} from "contracts/misc/AsteraDataProvider2.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";
import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";
import {IERC20Detailed} from "contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {IMiniPoolConfigurator} from "contracts/interfaces/IMiniPoolConfigurator.sol";
// import {MiniPoolV2} from "contracts/protocol/core/minipool/MiniPoolV2.sol";
import {ATokenERC6909V2} from "contracts/protocol/tokenization/ERC6909/ATokenERC6909V2.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";

contract TestTransferOutUpgradeTest is Test {
    address constant ORACLE = 0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87;
    address constant MINI_POOL_ADDRESS_PROVIDER = 0x9399aF805e673295610B17615C65b9d0cE1Ed306;
    address constant MINI_POOL_CONFIGURATOR = 0x41296B58279a81E20aF1c05D32b4f132b72b1B01;
    address constant DATA_PROVIDER = 0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e;

    address constant LENDING_POOL_ADDRESS_PROVIDER = 0x9a460e7BD6D5aFCEafbE795e05C48455738fB119;
    address constant LENDING_POOL_CONFIGURATOR = 0x5af0d031A3dA7c2D3b1fA9F00683004F176c28d0;
    address constant LENDING_POOL = 0x17d8a5305A37fe93E13a28f09c46db5bE24E1B9E;
    address constant ADMIN = 0x7D66a2e916d79c0988D41F1E50a1429074ec53a4;
    address constant EMERGENCY = 0xDa77d6C0281fCb3e41BD966aC393502a1C524224;

    address constant LINEA_MINI_POOL = 0x52280eA8979d52033E14df086F4dF555a258bEb4;
    address constant LINEA_AERC6909 = 0xc596AeF495cC08ac642A616919A8ee6213f533bb;

    function setUp() public {
        // LINEA setup
        string memory lineaRpc = vm.envString("LINEA_RPC_URL");
        uint256 lineaFork = vm.createSelectFork(lineaRpc);
        assertEq(vm.activeFork(), lineaFork);
    }

    function testUpgradeAndTransferOutFunctionality() public {
        ATokenERC6909V2 newAERC6909 = new ATokenERC6909V2();
        uint256 id =
            IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).getMiniPoolId(LINEA_MINI_POOL);
        console2.log("Mini pool id: ", id);

        // Upgrade erc6909 impl
        vm.prank(ADMIN);
        IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).setAToken6909Impl(
            address(newAERC6909), id
        );

        // Unpause pools
        vm.startPrank(EMERGENCY);
        ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setPoolPause(false);
        IMiniPoolConfigurator(MINI_POOL_CONFIGURATOR).setPoolPause(
            false, IMiniPool(LINEA_MINI_POOL)
        );
        vm.stopPrank();

        (address[] memory reservesList,) = IMiniPool(LINEA_MINI_POOL).getReservesList();

        // Get Admin and ERC6909 balance before
        console2.log("---------------------BEFORE---------------------");
        uint256[] memory adminBalances = new uint256[](reservesList.length);
        for (uint8 i = 0; i < reservesList.length; i++) {
            address token = ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).getIsAToken(
                reservesList[i]
            ) ? IAToken(reservesList[i]).UNDERLYING_ASSET_ADDRESS() : reservesList[i];
            adminBalances[i] = IERC20Detailed(token).balanceOf(ADMIN);
            console2.log("%s ADMIN balance: ", IERC20Detailed(token).symbol(), adminBalances[i]);
        }
        uint256[] memory erc6909Balances = new uint256[](reservesList.length);
        for (uint8 i = 0; i < reservesList.length; i++) {
            if (ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).getIsAToken(reservesList[i])) {
                erc6909Balances[i] = IAToken(reservesList[i]).convertToAssets(
                    IERC20Detailed(reservesList[i]).balanceOf(LINEA_AERC6909)
                );
            } else {
                erc6909Balances[i] = IERC20Detailed(reservesList[i]).balanceOf(LINEA_AERC6909);
            }

            console2.log(
                "%s ERC6909 balance: ", IERC20Detailed(reservesList[i]).symbol(), erc6909Balances[i]
            );
        }

        // Transfer out
        vm.prank(ADMIN);
        ATokenERC6909V2(LINEA_AERC6909).transferAllUnderlyingOut();

        // Get Admin and ERC6909 balance after
        console2.log("---------------------AFTER---------------------");
        for (uint8 i = 0; i < reservesList.length; i++) {
            address token = ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).getIsAToken(
                reservesList[i]
            ) ? IAToken(reservesList[i]).UNDERLYING_ASSET_ADDRESS() : reservesList[i];
            console2.log(
                "%s ADMIN balance: ",
                IERC20Detailed(token).symbol(),
                IERC20Detailed(token).balanceOf(ADMIN)
            );
            assertEq(
                IERC20Detailed(token).balanceOf(ADMIN),
                adminBalances[i] + erc6909Balances[i],
                "Balance of treasury doesn't include all erc 6909 balance"
            );
        }
        for (uint8 i = 0; i < reservesList.length; i++) {
            if (ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).getIsAToken(reservesList[i])) {
                console2.log(
                    "%s ERC6909 balance: ",
                    IERC20Detailed(reservesList[i]).symbol(),
                    IAToken(reservesList[i]).convertToAssets(
                        IERC20Detailed(reservesList[i]).balanceOf(LINEA_AERC6909)
                    )
                );
                assertEq(
                    IAToken(reservesList[i]).convertToAssets(
                        IERC20Detailed(reservesList[i]).balanceOf(LINEA_AERC6909)
                    ),
                    0,
                    "Balance in ERC6909 is not 0"
                );
            } else {
                console2.log(
                    "%s ERC6909 balance: ",
                    IERC20Detailed(reservesList[i]).symbol(),
                    IERC20Detailed(reservesList[i]).balanceOf(LINEA_AERC6909)
                );
                assertEq(
                    IERC20Detailed(reservesList[i]).balanceOf(LINEA_AERC6909),
                    0,
                    "Balance in ERC6909 is not 0"
                );
            }
        }

        // Access control
        // vm.prank(makeAddr("sb"));
        // ATokenERC6909(0xc596AeF495cC08ac642A616919A8ee6213f533bb).transferAllUnderlyingOut();
    }

    function testAccessControls(address user) public {
        ATokenERC6909V2 newAERC6909 = new ATokenERC6909V2();
        uint256 id =
            IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).getMiniPoolId(LINEA_MINI_POOL);
        console2.log("Mini pool id: ", id);

        // Upgrade erc6909 impl
        vm.prank(ADMIN);
        IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).setAToken6909Impl(
            address(newAERC6909), id
        );

        // Unpause pools
        vm.startPrank(EMERGENCY);
        ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setPoolPause(false);
        IMiniPoolConfigurator(MINI_POOL_CONFIGURATOR).setPoolPause(
            false, IMiniPool(LINEA_MINI_POOL)
        );
        vm.stopPrank();

        vm.assume(user != ADMIN && user != LINEA_MINI_POOL);

        vm.startPrank(user);
        vm.expectRevert(bytes("V2: OnlyOwner"));
        ATokenERC6909V2(LINEA_AERC6909).transferAllUnderlyingOut();
        vm.expectRevert(bytes(Errors.AT_CALLER_MUST_BE_LENDING_POOL));
        ATokenERC6909V2(LINEA_AERC6909).transferUnderlyingTo(user, 1000, 1e2, true);
        vm.stopPrank();

        // Pool still can do transfers
        vm.startPrank(LINEA_MINI_POOL);
        ATokenERC6909V2(LINEA_AERC6909).transferUnderlyingTo(user, 1000, 1e2, true);
    }

    function testTransferUnderlyingTo() public {
        ATokenERC6909V2 newAERC6909 = new ATokenERC6909V2();
        uint256 id =
            IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).getMiniPoolId(LINEA_MINI_POOL);
        console2.log("Mini pool id: ", id);

        // Upgrade erc6909 impl
        vm.prank(ADMIN);
        IMiniPoolAddressesProvider(MINI_POOL_ADDRESS_PROVIDER).setAToken6909Impl(
            address(newAERC6909), id
        );

        // Unpause pools
        vm.startPrank(EMERGENCY);
        ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).setPoolPause(false);
        IMiniPoolConfigurator(MINI_POOL_CONFIGURATOR).setPoolPause(
            false, IMiniPool(LINEA_MINI_POOL)
        );
        vm.stopPrank();

        (address[] memory reservesList,) = IMiniPool(LINEA_MINI_POOL).getReservesList();

        // Get Admin balance before
        console2.log("---------------------BEFORE---------------------");
        uint256[] memory adminBalances = new uint256[](reservesList.length);
        for (uint8 i = 0; i < reservesList.length; i++) {
            address token = ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).getIsAToken(
                reservesList[i]
            ) ? IAToken(reservesList[i]).UNDERLYING_ASSET_ADDRESS() : reservesList[i];
            adminBalances[i] = IERC20Detailed(token).balanceOf(ADMIN);
            console2.log("%s ADMIN balance: ", IERC20Detailed(token).symbol(), adminBalances[i]);
        }

        vm.startPrank(ADMIN);
        ATokenERC6909V2(LINEA_AERC6909).transferUnderlyingTo(ADMIN, 1000, 1e2, true);
        ATokenERC6909V2(LINEA_AERC6909).transferUnderlyingTo(ADMIN, 1001, 1e2, true);
        ATokenERC6909V2(LINEA_AERC6909).transferUnderlyingTo(ADMIN, 1002, 1e2, true);
        ATokenERC6909V2(LINEA_AERC6909).transferUnderlyingTo(ADMIN, 1003, 1e2, true);
        ATokenERC6909V2(LINEA_AERC6909).transferUnderlyingTo(ADMIN, 1128, 1e2, false);
        ATokenERC6909V2(LINEA_AERC6909).transferUnderlyingTo(ADMIN, 1129, 1e2, false);
        ATokenERC6909V2(LINEA_AERC6909).transferUnderlyingTo(ADMIN, 1130, 1e2, false);
        vm.stopPrank();

        // Get Admin balance after
        console2.log("---------------------AFTER---------------------");
        for (uint8 i = 0; i < reservesList.length; i++) {
            address token;
            uint256 expectedAmount;
            if (ILendingPoolConfigurator(LENDING_POOL_CONFIGURATOR).getIsAToken(reservesList[i])) {
                token = IAToken(reservesList[i]).UNDERLYING_ASSET_ADDRESS();
                expectedAmount = IAToken(reservesList[i]).convertToAssets(1e2);
            } else {
                token = reservesList[i];
                expectedAmount = 1e2;
            }
            console2.log(
                "%s ADMIN balance: ",
                IERC20Detailed(token).symbol(),
                IERC20Detailed(token).balanceOf(ADMIN)
            );
            assertEq(
                IERC20Detailed(token).balanceOf(ADMIN),
                adminBalances[i] + expectedAmount,
                "Balance of treasury doesn't include transfer underlying"
            );
        }
    }
}
