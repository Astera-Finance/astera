//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {WETHGateway} from "contracts/misc/WETHGateway.sol";
import {IWETHGateway} from "contracts/interfaces/base/IWETHGateway.sol";
import {IWETH} from "contracts/interfaces/base/IWETH.sol";
import {Common, ERC20, AToken, IAERC6909} from "./Common.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";

import {console2} from "forge-std/console2.sol";

contract WethGatewayTest is Common {
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
            address(deployedContracts.cod3xLendDataProvider),
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
            address(deployedContracts.cod3xLendDataProvider),
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
        configLpAddresses.cod3xLendDataProvider =
            address(miniPoolContracts.miniPoolAddressesProvider);
        configLpAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configLpAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configLpAddresses, miniPoolContracts, 0);
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setMinDebtThreshold(0, IMiniPool(miniPool));
        vm.label(miniPool, "MiniPool");
        console2.log("ETH balance: ", address(this).balance);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function testDepositETH() public {
        uint256 amount = 1 ether;
        address onBehalfOf = address(this);

        uint256 initialBalance = address(this).balance;

        commonContracts.wETHGateway.authorizeLendingPool(address(deployedContracts.lendingPool));
        // Call the depositETH function
        commonContracts.wETHGateway.depositETH{value: amount}(
            address(deployedContracts.lendingPool), true, onBehalfOf
        );

        // Check the balance of the contract
        assertEq(
            ERC20(address(tokens[WETH_OFFSET])).balanceOf(
                address(commonContracts.aTokens[WETH_OFFSET])
            ),
            amount,
            "Wrong WETH balance"
        );
        assertEq(
            commonContracts.aTokensWrapper[WETH_OFFSET].balanceOf(address(this)),
            amount,
            "Wrong aWETH balance"
        );
        assertEq(initialBalance - amount, address(this).balance, "Wrong ETH balance");
    }

    function testDepositETHMiniPool() public {
        uint256 amount = 1 ether;
        address onBehalfOf = address(this);
        uint256 initialBalance = address(this).balance;
        IAERC6909 aTokensErc6909 =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        commonContracts.wETHGateway.authorizeMiniPool(address(miniPool));
        // Call the depositETH function
        commonContracts.wETHGateway.depositETHMiniPool{value: amount}(miniPool, true, onBehalfOf);

        // Check the balance of the contract
        assertEq(
            ERC20(
                address(
                    fixture_getATokensWrapper(tokens, deployedContracts.cod3xLendDataProvider)[WETH_OFFSET]
                )
            ).balanceOf(address(aTokensErc6909)),
            amount,
            "Wrong aWETH balance"
        );
        assertEq(
            aTokensErc6909.balanceOf(address(this), 1000 + WETH_OFFSET),
            amount,
            "Wrong aMpWETH balance"
        );
        assertEq(initialBalance - amount, address(this).balance, "Wrong ETH balance");
    }

    function testWithdrawETH() public {
        uint256 amount = 1 ether;
        address onBehalfOf = address(this);
        commonContracts.wETHGateway.authorizeLendingPool(address(deployedContracts.lendingPool));
        // Call the depositETH function
        commonContracts.wETHGateway.depositETH{value: amount}(
            address(deployedContracts.lendingPool), true, onBehalfOf
        );

        // Check the balance of the contract
        assertEq(
            ERC20(address(tokens[WETH_OFFSET])).balanceOf(
                address(commonContracts.aTokens[WETH_OFFSET])
            ),
            amount,
            "Wrong WETH balance"
        );
        assertEq(
            commonContracts.aTokensWrapper[WETH_OFFSET].balanceOf(address(this)),
            amount,
            "Wrong aWETH balance"
        );

        //Test withdraw

        uint256 initialBalance = address(this).balance;

        // Call the withdrawETH function
        commonContracts.aTokens[WETH_OFFSET].approve(address(commonContracts.wETHGateway), amount);
        commonContracts.wETHGateway.withdrawETH(
            address(deployedContracts.lendingPool), true, amount, onBehalfOf
        );

        // Check the balance of the contract
        assertEq(
            ERC20(address(tokens[WETH_OFFSET])).balanceOf(
                address(commonContracts.aTokens[WETH_OFFSET])
            ),
            0,
            "Wrong WETH balance"
        );
        assertEq(
            commonContracts.aTokensWrapper[WETH_OFFSET].balanceOf(address(this)),
            0,
            "Wrong aWETH balance"
        );
        assertEq(initialBalance + amount, address(this).balance, "Wrong ETH balance");
    }

    function testWithdrawETHMiniPool() public {
        uint256 amount = 1 ether;
        address onBehalfOf = address(this);
        IAERC6909 aTokensErc6909 =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        commonContracts.wETHGateway.authorizeMiniPool(address(miniPool));
        // Call the depositETH function
        commonContracts.wETHGateway.depositETHMiniPool{value: amount}(miniPool, true, onBehalfOf);

        // Check the balance of the contract
        assertEq(
            ERC20(
                address(
                    fixture_getATokensWrapper(tokens, deployedContracts.cod3xLendDataProvider)[WETH_OFFSET]
                )
            ).balanceOf(address(aTokensErc6909)),
            amount,
            "Wrong aWETH balance"
        );
        assertEq(
            aTokensErc6909.balanceOf(address(this), 1000 + WETH_OFFSET),
            amount,
            "Wrong aMpWETH balance"
        );

        //Test withdraw

        uint256 initialBalance = address(this).balance;

        // Call the withdrawETH function
        aTokensErc6909.approve(address(commonContracts.wETHGateway), 1000 + WETH_OFFSET, amount);
        commonContracts.wETHGateway.withdrawETHMiniPool(miniPool, amount, true, address(this));

        // Check the balance of the contract
        assertEq(
            ERC20(
                address(
                    fixture_getATokensWrapper(tokens, deployedContracts.cod3xLendDataProvider)[WETH_OFFSET]
                )
            ).balanceOf(address(aTokensErc6909)),
            0,
            "Wrong aWETH balance"
        );
        assertEq(
            aTokensErc6909.balanceOf(address(this), 1000 + WETH_OFFSET), 0, "Wrong aMpWETH balance"
        );
        assertEq(initialBalance + amount, address(this).balance, "Wrong ETH balance");
    }

    function testBorrowAndRepayETH() public {
        uint256 amount = 1 ether;
        address onBehalfOf = address(this);
        commonContracts.wETHGateway.authorizeLendingPool(address(deployedContracts.lendingPool));
        // Call the depositETH function
        commonContracts.wETHGateway.depositETH{value: amount}(
            address(deployedContracts.lendingPool), true, onBehalfOf
        );

        // Check the balance of the contract
        assertEq(
            ERC20(address(tokens[WETH_OFFSET])).balanceOf(
                address(commonContracts.aTokens[WETH_OFFSET])
            ),
            amount,
            "Wrong WETH balance"
        );
        assertEq(
            commonContracts.aTokensWrapper[WETH_OFFSET].balanceOf(address(this)),
            amount,
            "Wrong aWETH balance"
        );

        //Test borrow

        uint256 initialBalance = address(this).balance;

        // Call the borrowETH function
        commonContracts.variableDebtTokens[WETH_OFFSET].approveDelegation(
            address(commonContracts.wETHGateway), amount / 2
        );
        console2.log(
            "Borrow allowance: ",
            commonContracts.variableDebtTokens[WETH_OFFSET].borrowAllowance(
                address(this), address(commonContracts.wETHGateway)
            )
        );
        commonContracts.wETHGateway.borrowETH(
            address(deployedContracts.lendingPool), true, amount / 2
        );

        // Check the balance of the contract
        assertEq(initialBalance + amount / 2, address(this).balance, "Wrong ETH balance");

        //Test repay

        uint256 initialBalance2 = address(this).balance;

        // Call the repayWeth function
        commonContracts.wETHGateway.repayETH{value: amount / 2}(
            address(deployedContracts.lendingPool), true, amount / 2, onBehalfOf
        );

        // Check the balance of the contract
        assertEq(initialBalance2 - amount / 2, address(this).balance, "Wrong ETH balance");
    }

    function testBorrowAndRepayETHMiniPool() public {
        uint256 amount = 1 ether;
        address onBehalfOf = address(this);
        IAERC6909 aTokensErc6909 =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        commonContracts.wETHGateway.authorizeMiniPool(address(miniPool));
        // Call the depositETH function
        commonContracts.wETHGateway.depositETHMiniPool{value: amount}(
            address(miniPool), true, onBehalfOf
        );

        //Test borrow

        uint256 initialBalance = address(this).balance;

        // Call the borrowETH function
        aTokensErc6909.approveDelegation(
            address(commonContracts.wETHGateway), 2000 + WETH_OFFSET, amount / 2
        );
        commonContracts.wETHGateway.borrowETHMiniPool(address(miniPool), amount / 2, true);

        // Check the balance of the contract
        assertEq(initialBalance + amount / 2, address(this).balance, "Wrong ETH balance");

        //Test repay

        uint256 initialBalance2 = address(this).balance;

        // Call the repayWeth function
        commonContracts.wETHGateway.repayETHMiniPool{value: amount / 2}(
            address(miniPool), amount / 2, true, onBehalfOf
        );

        // Check the balance of the contract
        assertEq(initialBalance2 - amount / 2, address(this).balance, "Wrong ETH balance");
    }
}
