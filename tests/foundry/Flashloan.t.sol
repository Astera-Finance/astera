// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract FlashloanTest is Common {
    using WadRayMath for uint256;

    event FlashLoan(
        address indexed target,
        address indexed initiator,
        address indexed asset,
        DataTypes.InterestRateMode interestRateMode,
        uint256 amount,
        uint256 premium
    );

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;
    address notTrue = makeAddr("NotTrue");
    address notApproved = makeAddr("NotApproved");

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
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
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );

        commonContracts.mockedVaults =
            fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        uint256[] memory totalAmountsToPay = new uint256[](tokens.length);
        (uint256[] memory balancesBefore, address sender) = abi.decode(params, (uint256[], address)); //uint256[], address
        if ((sender == address(this))) {
            for (uint32 idx = 0; idx < tokens.length; idx++) {
                console2.log("[In] Premium: ", premiums[idx]);
                totalAmountsToPay[idx] = amounts[idx] + premiums[idx];
                assertEq(balancesBefore[idx] + amounts[idx], IERC20(assets[idx]).balanceOf(sender));
                assertEq(assets[idx], tokens[idx]);
                IERC20(assets[idx]).approve(
                    address(deployedContracts.lendingPool), totalAmountsToPay[idx]
                );
            }
            assertEq(sender, address(this));
            return true;
        } else if (sender == notApproved) {
            for (uint32 idx = 0; idx < tokens.length; idx++) {
                console2.log("[In] Premium: ", premiums[idx]);
                totalAmountsToPay[idx] = amounts[idx] + premiums[idx];
                assertEq(
                    balancesBefore[idx] + amounts[idx], IERC20(assets[idx]).balanceOf(address(this))
                );
                assertEq(assets[idx], tokens[idx]);
            }
            return true;
        } else {
            return false;
        }
    }

    struct Balances {
        uint256[] balancesBefore;
        uint256[] aTokenBalancesBefore;
        uint256[] totalManagedAssetsBefore;
    }

    function testFlashloan_Positive() public {
        bool[] memory reserveTypes = new bool[](tokens.length);
        address[] memory tokenAddresses = new address[](tokens.length);
        uint256[] memory amounts = new uint256[](tokens.length);
        uint256[] memory modes = new uint256[](tokens.length);
        Balances memory balances;
        balances.balancesBefore = new uint256[](tokens.length);
        balances.aTokenBalancesBefore = new uint256[](tokens.length);
        balances.totalManagedAssetsBefore = new uint256[](tokens.length);

        for (uint32 idx = 0; idx < tokens.length; idx++) {
            uint256 amountToDeposit = IERC20(tokens[idx]).balanceOf(address(this)) / 2;
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amountToDeposit);
            deployedContracts.lendingPool.deposit(
                address(erc20Tokens[idx]), true, amountToDeposit, address(this)
            );
            reserveTypes[idx] = true;
            tokenAddresses[idx] = address(erc20Tokens[idx]);
            amounts[idx] = IERC20(tokens[idx]).balanceOf(address(this)) / 2;
            modes[idx] = 0;
            balances.balancesBefore[idx] = IERC20(tokens[idx]).balanceOf(address(this));
            balances.aTokenBalancesBefore[idx] =
                IERC20(tokens[idx]).balanceOf(address(commonContracts.aTokens[idx]));
            balances.totalManagedAssetsBefore[idx] =
                AToken(commonContracts.aTokens[idx]).getTotalManagedAssets();
        }

        ILendingPool.FlashLoanParams memory flashloanParams =
            ILendingPool.FlashLoanParams(address(this), tokenAddresses, reserveTypes, address(this));
        bytes memory params = abi.encode(balances.balancesBefore, address(this));
        for (uint32 idx = 0; idx < tokens.length; idx++) {
            vm.expectEmit(true, true, true, false);
            emit FlashLoan(
                address(this),
                address(this),
                tokenAddresses[idx],
                DataTypes.InterestRateMode(0),
                amounts[idx],
                0
            );
        }

        deployedContracts.lendingPool.flashLoan(flashloanParams, amounts, modes, params);

        for (uint32 idx = 0; idx < tokens.length; idx++) {
            console2.log(
                "Balance now: %s vs Balance before: %s",
                IERC20(tokens[idx]).balanceOf(address(commonContracts.aTokens[idx])),
                balances.aTokenBalancesBefore[idx]
            );
            assertGe(
                IERC20(tokens[idx]).balanceOf(address(commonContracts.aTokens[idx])),
                balances.aTokenBalancesBefore[idx]
            );
            console2.log(
                "Managed assets now: %s vs Managed assets before: %s",
                AToken(commonContracts.aTokens[idx]).getTotalManagedAssets(),
                balances.totalManagedAssetsBefore[idx]
            );
            assertGe(
                AToken(commonContracts.aTokens[idx]).getTotalManagedAssets(),
                balances.totalManagedAssetsBefore[idx]
            );
        }
    }

    function testFlashloan_NotTrueReturned() public {
        bool[] memory reserveTypes = new bool[](tokens.length);
        address[] memory tokenAddresses = new address[](tokens.length);
        uint256[] memory amounts = new uint256[](tokens.length);
        uint256[] memory modes = new uint256[](tokens.length);
        uint256[] memory balancesBefore = new uint256[](tokens.length);

        for (uint32 idx = 0; idx < tokens.length; idx++) {
            uint256 amountToDeposit = IERC20(tokens[idx]).balanceOf(address(this)) / 2;
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amountToDeposit);
            deployedContracts.lendingPool.deposit(
                address(erc20Tokens[idx]), true, amountToDeposit, address(this)
            );
            reserveTypes[idx] = true;
            tokenAddresses[idx] = address(erc20Tokens[idx]);
            amounts[idx] = IERC20(tokens[idx]).balanceOf(address(this)) / 2;
            modes[idx] = 0;
            balancesBefore[idx] = IERC20(tokens[idx]).balanceOf(address(this));
        }

        ILendingPool.FlashLoanParams memory flashloanParams =
            ILendingPool.FlashLoanParams(address(this), tokenAddresses, reserveTypes, address(this));
        bytes memory params = abi.encode(balancesBefore, notTrue);
        vm.expectRevert(bytes(Errors.LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN));
        deployedContracts.lendingPool.flashLoan(flashloanParams, amounts, modes, params);
    }

    function testFlashloan_NotApproved() public {
        bool[] memory reserveTypes = new bool[](tokens.length);
        address[] memory tokenAddresses = new address[](tokens.length);
        uint256[] memory amounts = new uint256[](tokens.length);
        uint256[] memory modes = new uint256[](tokens.length);
        uint256[] memory balancesBefore = new uint256[](tokens.length);

        for (uint32 idx = 0; idx < tokens.length; idx++) {
            uint256 amountToDeposit = IERC20(tokens[idx]).balanceOf(address(this)) / 2;
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amountToDeposit);
            deployedContracts.lendingPool.deposit(
                address(erc20Tokens[idx]), true, amountToDeposit, address(this)
            );
            reserveTypes[idx] = true;
            tokenAddresses[idx] = address(erc20Tokens[idx]);
            amounts[idx] = IERC20(tokens[idx]).balanceOf(address(this)) / 2;
            modes[idx] = 0;
            balancesBefore[idx] = IERC20(tokens[idx]).balanceOf(address(this));
        }

        ILendingPool.FlashLoanParams memory flashloanParams =
            ILendingPool.FlashLoanParams(address(this), tokenAddresses, reserveTypes, address(this));
        bytes memory params = abi.encode(balancesBefore, notApproved);
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));
        deployedContracts.lendingPool.flashLoan(flashloanParams, amounts, modes, params);
    }

    function testFlashloanRehypothecation() public {
        bool[] memory reserveTypes = new bool[](tokens.length);
        address[] memory tokenAddresses = new address[](tokens.length);
        uint256[] memory amounts = new uint256[](tokens.length);
        uint256[] memory modes = new uint256[](tokens.length);
        Balances memory balances;
        balances.balancesBefore = new uint256[](tokens.length);
        balances.aTokenBalancesBefore = new uint256[](tokens.length);
        balances.totalManagedAssetsBefore = new uint256[](tokens.length);

        for (uint32 idx = 0; idx < tokens.length; idx++) {
            console2.log(
                "Rehypothecation amt 1: %s",
                IERC20(tokens[idx]).balanceOf(address(commonContracts.aTokens[idx]))
            );

            turnOnRehypothecation(
                deployedContracts.lendingPoolConfigurator,
                address(commonContracts.aTokens[idx]),
                address(commonContracts.mockVaultUnits[idx]),
                admin,
                5000,
                10,
                200
            );

            console2.log(
                "Rehypothecation amt 2: %s",
                IERC20(tokens[idx]).balanceOf(address(commonContracts.aTokens[idx]))
            );

            uint256 amountToDeposit = IERC20(tokens[idx]).balanceOf(address(this)) / 2;
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amountToDeposit);
            deployedContracts.lendingPool.deposit(
                address(erc20Tokens[idx]), true, amountToDeposit, address(this)
            );

            console2.log(
                "Rehypothecation amt 3: %s",
                IERC20(tokens[idx]).balanceOf(address(commonContracts.aTokens[idx]))
            );

            reserveTypes[idx] = true;
            tokenAddresses[idx] = address(erc20Tokens[idx]);
            amounts[idx] = IERC20(tokens[idx]).balanceOf(address(this)) / 2;
            modes[idx] = 0;

            balances.balancesBefore[idx] = IERC20(tokens[idx]).balanceOf(address(this));
            balances.aTokenBalancesBefore[idx] =
                IERC20(tokens[idx]).balanceOf(address(commonContracts.aTokens[idx]));
            balances.totalManagedAssetsBefore[idx] =
                AToken(commonContracts.aTokens[idx]).getTotalManagedAssets();
        }

        ILendingPool.FlashLoanParams memory flashloanParams =
            ILendingPool.FlashLoanParams(address(this), tokenAddresses, reserveTypes, address(this));
        bytes memory params = abi.encode(balances.balancesBefore, address(this));

        deployedContracts.lendingPool.flashLoan(flashloanParams, amounts, modes, params);

        for (uint32 idx = 0; idx < tokens.length; idx++) {
            console2.log(
                "Rehypothecation amt 4: %s",
                IERC20(tokens[idx]).balanceOf(address(commonContracts.aTokens[idx]))
            );
            console2.log(
                "Rehypothecation amt 5: %s", commonContracts.aTokens[idx]._underlyingAmount()
            );
            console2.log("Rehypothecation amt 6: %s", commonContracts.aTokens[idx]._farmingBal());
            console2.log("--------------------------------");

            assertApproxEqRel(
                commonContracts.aTokens[idx]._farmingBal(),
                commonContracts.aTokens[idx]._underlyingAmount()
                    * commonContracts.aTokens[idx]._farmingPct() / 10000,
                commonContracts.aTokens[idx]._farmingPctDrift() * 1e14
            );
        }
    }

    function testFlashloan_INVALID_INTEREST_RATE_MODE() public {
        bool[] memory reserveTypes = new bool[](1);
        address[] memory tokenAddresses = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);
        Balances memory balances;
        balances.balancesBefore = new uint256[](1);
        balances.aTokenBalancesBefore = new uint256[](1);
        balances.totalManagedAssetsBefore = new uint256[](1);

        for (uint32 idx = 0; idx < 1; idx++) {
            uint256 amountToDeposit = IERC20(tokens[idx]).balanceOf(address(this)) / 2;
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amountToDeposit);
            deployedContracts.lendingPool.deposit(
                address(erc20Tokens[idx]), true, amountToDeposit, address(this)
            );
            reserveTypes[idx] = true;
            tokenAddresses[idx] = address(erc20Tokens[idx]);
            amounts[idx] = IERC20(tokens[idx]).balanceOf(address(this)) / 2;
            modes[idx] = 2;
            balances.balancesBefore[idx] = IERC20(tokens[idx]).balanceOf(address(this));
            balances.aTokenBalancesBefore[idx] =
                IERC20(tokens[idx]).balanceOf(address(commonContracts.aTokens[idx]));
            balances.totalManagedAssetsBefore[idx] =
                AToken(commonContracts.aTokens[idx]).getTotalManagedAssets();
        }

        ILendingPool.FlashLoanParams memory flashloanParams =
            ILendingPool.FlashLoanParams(address(this), tokenAddresses, reserveTypes, address(this));
        bytes memory params = abi.encode(balances.balancesBefore, address(this));

        vm.expectRevert(bytes(Errors.VL_INVALID_INTEREST_RATE_MODE));
        deployedContracts.lendingPool.flashLoan(flashloanParams, amounts, modes, params);
    }
}
