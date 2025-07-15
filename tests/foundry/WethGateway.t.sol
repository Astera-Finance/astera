//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {WETHGateway} from "contracts/misc/WETHGateway.sol";
import {IWETHGateway} from "contracts/interfaces/base/IWETHGateway.sol";
import {IWETH} from "contracts/interfaces/base/IWETH.sol";
import {Common, ERC20, AToken, IAERC6909} from "./Common.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

import {console2} from "forge-std/console2.sol";

contract WethGatewayTest is Common {
    using WadRayMath for uint256;

    event Received(address, uint256);

    IWETHGateway public wethGateway;
    IWETH public weth;
    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    DeployedMiniPoolContracts miniPoolContracts;

    ConfigAddresses configLpAddresses;
    address aTokensErc6909Addr;
    address miniPool;

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();

        configLpAddresses = ConfigAddresses(
            address(deployedContracts.asteraLendDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(commonContracts.aToken),
            configLpAddresses,
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
            address(deployedContracts.asteraLendDataProvider),
            miniPoolContracts
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console2.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] =
                    address(commonContracts.aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        configLpAddresses.asteraLendDataProvider =
            address(miniPoolContracts.miniPoolAddressesProvider);
        configLpAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configLpAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configLpAddresses, miniPoolContracts, 0);
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setMinDebtThreshold(0, IMiniPool(miniPool));
        vm.label(miniPool, "MiniPool");
        console2.log("ETH balance: ", address(this).balance);
        console2.log("Initial borrow from main pool");
        borrowETH(address(this));
        console2.log("Initial borrow from mini pool");
        borrowETHMiniPool(address(this));
        console2.log("warping time by 1 week");
        vm.warp(block.timestamp + 1 weeks);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // fallback() external payable {
    //     emit Received(msg.sender, msg.value);
    // }

    function testDepositETH() public {
        depositETH(makeAddr("user"));
    }

    function depositETH(address user) public {
        vm.assume(user != address(0));
        uint256 amount = 1 ether;
        deal(address(user), amount);
        uint256 initialBalance = ERC20(address(tokens[WETH_OFFSET])).balanceOf(
            address(commonContracts.aTokens[WETH_OFFSET])
        );
        uint256 initialATokenBalance = commonContracts.aTokensWrapper[WETH_OFFSET].balanceOf(user);

        commonContracts.wETHGateway.authorizeLendingPool(address(deployedContracts.lendingPool));
        vm.startPrank(user);
        // Call the depositETH function
        commonContracts.wETHGateway.depositETH{value: amount}(
            address(deployedContracts.lendingPool), true, user
        );
        vm.stopPrank();
        // Check the balance of the contract
        assertEq(
            ERC20(address(tokens[WETH_OFFSET])).balanceOf(
                address(commonContracts.aTokens[WETH_OFFSET])
            ),
            initialBalance + amount,
            "Wrong WETH balance after deposit"
        );
        assertEq(
            commonContracts.aTokensWrapper[WETH_OFFSET].balanceOf(user),
            initialATokenBalance + commonContracts.wETHGateway.AWETH().convertToShares(amount),
            "Wrong aWETH balance after deposit"
        );
        assertEq(initialBalance - amount, user.balance, "Wrong ETH balance");
    }

    function testDepositETHMiniPool() public {
        depositETHMiniPool(makeAddr("user"));
    }

    function depositETHMiniPool(address user) public {
        vm.assume(user != address(0));
        uint256 amount = 1 ether;

        IAERC6909 aTokensErc6909 =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        commonContracts.wETHGateway.authorizeMiniPool(address(miniPool));
        uint256 initialBalance = ERC20(
            address(
                fixture_getATokensWrapper(tokens, deployedContracts.asteraLendDataProvider)[WETH_OFFSET]
            )
        ).balanceOf(address(aTokensErc6909));
        uint256 initialATokenBalance = aTokensErc6909.balanceOf(user, 1000 + WETH_OFFSET);

        deal(address(user), amount);
        uint256 initialUserBalance = user.balance;
        vm.prank(user);
        // Call the depositETH function
        commonContracts.wETHGateway.depositETHMiniPool{value: amount}(miniPool, true, user);

        // Check the balance of the contract
        assertEq(
            ERC20(
                address(
                    fixture_getATokensWrapper(tokens, deployedContracts.asteraLendDataProvider)[WETH_OFFSET]
                )
            ).balanceOf(address(aTokensErc6909)),
            initialBalance + commonContracts.wETHGateway.AWETH().convertToShares(amount),
            "Wrong aWETH balance"
        );
        console2.log(
            "NormalizedIncome: ", IMiniPool(miniPool).getReserveNormalizedIncome(address(WETH))
        );
        assertEq(
            aTokensErc6909.balanceOf(user, 1000 + WETH_OFFSET),
            initialATokenBalance + commonContracts.wETHGateway.AWETH().convertToShares(amount),
            "Wrong aMpWETH balance"
        );
        assertEq(initialUserBalance - amount, user.balance, "Wrong ETH balance");
    }

    // function testDepositETHMiniPoolSender(address user) public {
    //     depositETHMiniPoolSender(makeAddr("user"));
    // }

    // function depositETHMiniPoolSender(address user) public {
    //     vm.assume(user != address(0));
    //     uint256 amount = 0.01 ether;
    //     user = 0xF29dA3595351dBFd0D647857C46F8D63Fc2e68C5;
    //     vm.deal(user, 0.02 ether);
    //     uint256 initialUserBalance = 0xF29dA3595351dBFd0D647857C46F8D63Fc2e68C5.balance;

    //     console2.log("Initial balance of Sender: ", initialUserBalance);
    //     IAERC6909 aTokensErc6909 =
    //         IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
    //     uint256 initialBalance = ERC20(
    //         address(
    //             fixture_getATokensWrapper(tokens, deployedContracts.asteraLendDataProvider)[WETH_OFFSET]
    //         )
    //     ).balanceOf(address(aTokensErc6909));
    //     commonContracts.wETHGateway.authorizeMiniPool(address(miniPool));
    //     vm.startPrank(user);
    //     // Call the depositETH function
    //     commonContracts.wETHGateway.depositETHMiniPool{value: amount}(miniPool, true, user);
    //     vm.stopPrank();
    //     // Check the balance of the contract
    //     assertEq(
    //         ERC20(
    //             address(
    //                 fixture_getATokensWrapper(tokens, deployedContracts.asteraLendDataProvider)[WETH_OFFSET]
    //             )
    //         ).balanceOf(address(aTokensErc6909)),
    //         initialBalance + commonContracts.wETHGateway.AWETH().convertToShares(amount),
    //         "Wrong aWETH balance"
    //     );
    //     assertEq(
    //         aTokensErc6909.balanceOf(user, 1000 + WETH_OFFSET), amount, "Wrong aMpWETH balance"
    //     );
    //     assertEq(initialUserBalance - amount, user.balance, "Wrong ETH balance");
    // }

    function testWithdrawETH() public {
        withdrawETH(makeAddr("user"));
    }

    function withdrawETH(address user) public {
        console2.log("testWithdrawETH");
        vm.assume(user != address(0));
        uint256 amount = 1 ether;
        uint256 initialBalance = ERC20(address(tokens[WETH_OFFSET])).balanceOf(
            address(commonContracts.aTokens[WETH_OFFSET])
        );
        console2.log("Initial WETH balance: ", initialBalance);
        commonContracts.wETHGateway.authorizeLendingPool(address(deployedContracts.lendingPool));

        vm.startPrank(user);
        deal(address(user), amount);
        // Call the depositETH function
        commonContracts.wETHGateway.depositETH{value: amount}(
            address(deployedContracts.lendingPool), true, user
        );

        //Test withdraw
        uint256 initialUserBalance = user.balance;

        // Call the withdrawETH function
        commonContracts.aTokens[WETH_OFFSET].approve(address(commonContracts.wETHGateway), amount);
        commonContracts.wETHGateway.withdrawETH(
            address(deployedContracts.lendingPool), true, amount, user
        );

        // Check the balance of the contract
        assertEq(
            ERC20(address(tokens[WETH_OFFSET])).balanceOf(
                address(commonContracts.aTokens[WETH_OFFSET])
            ),
            initialBalance,
            "Wrong WETH balance after withdraw"
        );
        assertEq(
            commonContracts.aTokensWrapper[WETH_OFFSET].balanceOf(user),
            0,
            "Wrong aWETH balance after withdraw"
        );
        assertEq(initialUserBalance + amount, user.balance, "Wrong ETH user balance");
    }

    function testWithdrawETHMiniPool() public {
        withdrawETHMiniPool(makeAddr("user"));
    }

    function withdrawETHMiniPool(address user) public {
        vm.assume(user != address(0));
        uint256 amount = 1 ether;
        IAERC6909 aTokensErc6909 =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        commonContracts.wETHGateway.authorizeMiniPool(address(miniPool));
        uint256 initialBalance = ERC20(
            address(
                fixture_getATokensWrapper(tokens, deployedContracts.asteraLendDataProvider)[WETH_OFFSET]
            )
        ).balanceOf(address(aTokensErc6909));
        deal(address(user), amount);
        vm.startPrank(user);
        // Call the depositETH function
        commonContracts.wETHGateway.depositETHMiniPool{value: amount}(miniPool, true, user);

        //Test withdraw
        uint256 initialUserBalance = user.balance;

        // Call the withdrawETH function
        aTokensErc6909.approve(address(commonContracts.wETHGateway), 1000 + WETH_OFFSET, amount);
        commonContracts.wETHGateway.withdrawETHMiniPool(miniPool, amount, true, user);

        vm.stopPrank();

        // Check the balance of the contract
        assertEq(
            ERC20(
                address(
                    fixture_getATokensWrapper(tokens, deployedContracts.asteraLendDataProvider)[WETH_OFFSET]
                )
            ).balanceOf(address(aTokensErc6909)),
            initialBalance,
            "Wrong aWETH balance after withdrawal"
        );
        assertEq(
            aTokensErc6909.balanceOf(user, 1000 + WETH_OFFSET),
            0,
            "Wrong aMpWETH balance after withdrawal"
        );
        assertEq(initialUserBalance + amount, user.balance, "Wrong ETH user balance");
    }

    function testBorrowETH(address user) public {
        borrowETH(makeAddr("user"));
    }

    function borrowETH(address user) public {
        vm.assume(user != address(0));
        uint256 initialBalance = ERC20(address(tokens[WETH_OFFSET])).balanceOf(
            address(commonContracts.aTokens[WETH_OFFSET])
        );
        uint256 amount = 1 ether;
        commonContracts.wETHGateway.authorizeLendingPool(address(deployedContracts.lendingPool));
        deal(address(user), amount);
        vm.startPrank(user);
        // Call the depositETH function
        commonContracts.wETHGateway.depositETH{value: amount}(
            address(deployedContracts.lendingPool), true, user
        );

        //Test borrow
        initialBalance = user.balance;

        // Call the borrowETH function
        commonContracts.variableDebtTokens[WETH_OFFSET].approveDelegation(
            address(commonContracts.wETHGateway), amount / 2
        );
        console2.log(
            "Borrow allowance: ",
            commonContracts.variableDebtTokens[WETH_OFFSET].borrowAllowance(
                user, address(commonContracts.wETHGateway)
            )
        );
        commonContracts.wETHGateway.borrowETH(
            address(deployedContracts.lendingPool), true, amount / 2
        );
        vm.stopPrank();
        // Check the balance of the contract
        assertEq(initialBalance + amount / 2, user.balance, "Wrong ETH balance after repay");
    }

    function test_BorrowAndRepayETH() public {
        borrowAndRepayETH(makeAddr("user"));
    }

    function borrowAndRepayETH(address user) public {
        vm.assume(user != address(0));
        uint256 amount = 1 ether;
        uint256 initialBalance = ERC20(address(tokens[WETH_OFFSET])).balanceOf(
            address(commonContracts.aTokens[WETH_OFFSET])
        );
        commonContracts.wETHGateway.authorizeLendingPool(address(deployedContracts.lendingPool));
        // Call the depositETH function
        console2.log("Call the depositETH function");
        deal(address(user), amount);

        vm.startPrank(user);
        commonContracts.wETHGateway.depositETH{value: amount}(
            address(deployedContracts.lendingPool), true, user
        );

        //Test borrow
        initialBalance = user.balance;

        // Call the borrowETH function
        commonContracts.variableDebtTokens[WETH_OFFSET].approveDelegation(
            address(commonContracts.wETHGateway), amount / 2
        );
        console2.log(
            "Borrow allowance: ",
            commonContracts.variableDebtTokens[WETH_OFFSET].borrowAllowance(
                user, address(commonContracts.wETHGateway)
            )
        );
        commonContracts.wETHGateway.borrowETH(
            address(deployedContracts.lendingPool), true, amount / 2
        );

        // Check the balance of the contract
        assertEq(initialBalance + amount / 2, user.balance, "Wrong ETH balance after borrow");

        //Test repay

        uint256 initialBalance2 = user.balance;

        console2.log("repayWeth function");
        // Call the repayWeth function
        commonContracts.wETHGateway.repayETH{value: amount / 2}(
            address(deployedContracts.lendingPool), true, amount / 2, user
        );
        vm.stopPrank();
        // Check the balance of the contract
        assertEq(initialBalance2 - amount / 2, user.balance, "Wrong ETH balance after repay");
    }

    function testBorrowETHMiniPool() public {
        borrowETHMiniPool(makeAddr("user"));
    }

    function borrowETHMiniPool(address user) public {
        vm.assume(user != address(0));
        uint256 initialBalance = user.balance;
        uint256 amount = 1 ether;
        IAERC6909 aTokensErc6909 =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        commonContracts.wETHGateway.authorizeMiniPool(address(miniPool));
        deal(address(user), amount);
        vm.startPrank(user);
        // Call the depositETH function
        commonContracts.wETHGateway.depositETHMiniPool{value: amount}(address(miniPool), true, user);

        //Test borrow
        initialBalance = user.balance;
        console2.log("Initial balance: ", initialBalance);
        console2.log("Borrowing amount: ", amount / 2);

        // Call the borrowETH function
        aTokensErc6909.approveDelegation(
            address(commonContracts.wETHGateway), 2000 + WETH_OFFSET, amount / 2
        );
        commonContracts.wETHGateway.borrowETHMiniPool(address(miniPool), amount / 2, true);
        vm.stopPrank();
        // Check the balance of the contract
        assertEq(initialBalance + amount / 2, user.balance, "Wrong ETH balance");
    }

    function testBorrowAndRepayETHMiniPool() public {
        borrowAndRepayETHMiniPool(makeAddr("user"));
    }

    function borrowAndRepayETHMiniPool(address user) public {
        vm.assume(user != address(0));
        uint256 amount = 1 ether;
        IAERC6909 aTokensErc6909 =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        commonContracts.wETHGateway.authorizeMiniPool(address(miniPool));
        deal(address(user), amount);
        vm.startPrank(user);
        // Call the depositETH function
        commonContracts.wETHGateway.depositETHMiniPool{value: amount}(address(miniPool), true, user);

        //Test borrow
        uint256 initialBalance = user.balance;

        // Call the borrowETH function
        console2.log("borrowETH function");
        aTokensErc6909.approveDelegation(
            address(commonContracts.wETHGateway), 2000 + WETH_OFFSET, amount / 2
        );
        commonContracts.wETHGateway.borrowETHMiniPool(address(miniPool), amount / 2, true);

        // Check the balance of the contract
        assertEq(initialBalance + amount / 2, user.balance, "Wrong ETH balance");

        //Test repay

        uint256 initialBalance2 = user.balance;

        // Call the repayWeth function
        console2.log("repayWeth function");
        commonContracts.wETHGateway.repayETHMiniPool{value: amount / 2}(
            address(miniPool), amount / 2, true, user
        );
        vm.stopPrank();
        // Check the balance of the contract
        assertEq(initialBalance2 - amount / 2, user.balance, "Wrong ETH balance after repay");
    }
}
