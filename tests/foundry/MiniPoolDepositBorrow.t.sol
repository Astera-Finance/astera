// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolFixtures.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import "contracts/misc/Cod3xLendDataProvider.sol";

import "forge-std/StdUtils.sol";
import "forge-std/console.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract MiniPoolDepositBorrowTest is MiniPoolFixtures {
    ERC20[] erc20Tokens;

    function setUp() public override {
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
            address(aToken),
            configLpAddresses,
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
            console.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] = address(aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        configLpAddresses.cod3xLendDataProvider =
            address(miniPoolContracts.miniPoolAddressesProvider);
        configLpAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configLpAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configLpAddresses, miniPoolContracts, 0);
        vm.label(miniPool, "MiniPool");
    }

    function testInitalizeReserveWithReserveTypeFalse() public {
        address user = address(0x1223);
        MintableERC20 mockToken = new MintableERC20("a", "a", 18);

        vm.prank(user);
        mockToken.mint(100 ether);

        {
            ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
                new ILendingPoolConfigurator.InitReserveInput[](1);
            ATokensAndRatesHelper.ConfigureReserveInput[] memory inputConfigParams =
                new ATokensAndRatesHelper.ConfigureReserveInput[](1);

            string memory tmpSymbol = ERC20(mockToken).symbol();
            address interestStrategy = isStableStrategy[0] != false
                ? configAddresses.stableStrategy
                : configAddresses.volatileStrategy;
            // console.log("[common] main interestStartegy: ", interestStrategy);
            initInputParams[0] = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: address(aToken),
                variableDebtTokenImpl: address(variableDebtToken),
                underlyingAssetDecimals: ERC20(mockToken).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: address(mockToken),
                reserveType: false,
                treasury: configAddresses.treasury,
                incentivesController: configAddresses.rewarder,
                underlyingAssetName: tmpSymbol,
                aTokenName: string.concat("Cod3x Lend ", tmpSymbol),
                aTokenSymbol: string.concat("cl", tmpSymbol),
                variableDebtTokenName: string.concat("Cod3x Lend variable debt bearing ", tmpSymbol),
                variableDebtTokenSymbol: string.concat("variableDebt", tmpSymbol),
                params: "0x10"
            });

            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.batchInitReserve(initInputParams);

            inputConfigParams[0] = ATokensAndRatesHelper.ConfigureReserveInput({
                asset: address(mockToken),
                reserveType: false,
                baseLTV: 8000,
                liquidationThreshold: 8500,
                liquidationBonus: 10500,
                reserveFactor: 1500,
                borrowingEnabled: true
            });

            deployedContracts.lendingPoolAddressesProvider.setPoolAdmin(
                address(deployedContracts.aTokensAndRatesHelper)
            );
            ATokensAndRatesHelper(deployedContracts.aTokensAndRatesHelper).configureReserves(
                inputConfigParams
            );
            deployedContracts.lendingPoolAddressesProvider.setPoolAdmin(admin);
        }

        address[] memory aTokensW = new address[](1);

        (address _aTokenAddress,) = Cod3xLendDataProvider(deployedContracts.cod3xLendDataProvider)
            .getLpTokens(address(mockToken), false);
        console.log("AToken ::::  ", _aTokenAddress);
        aTokensW[0] = address(AToken(_aTokenAddress).WRAPPER_ADDRESS());

        {
            IMiniPoolConfigurator.InitReserveInput[] memory initInputParams =
                new IMiniPoolConfigurator.InitReserveInput[](aTokensW.length);
            console.log("Getting Mini pool: ");
            address miniPool = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);

            string memory tmpSymbol = ERC20(aTokensW[0]).symbol();
            string memory tmpName = ERC20(aTokensW[0]).name();

            address interestStrategy = configAddresses.volatileStrategy;
            // console.log("[common]interestStartegy: ", interestStrategy);
            initInputParams[0] = IMiniPoolConfigurator.InitReserveInput({
                underlyingAssetDecimals: ERC20(aTokensW[0]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: aTokensW[0],
                underlyingAssetName: tmpName,
                underlyingAssetSymbol: tmpSymbol
            });

            vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin()));
            vm.expectRevert(bytes(Errors.RL_RESERVE_NOT_INITIALIZED));
            miniPoolContracts.miniPoolConfigurator.batchInitReserve(
                initInputParams, IMiniPool(miniPool)
            );

            vm.stopPrank();
        }
    }

    function testMiniPoolDeposits(uint256 amount, uint256 offset) public {
        /* Fuzz vector creation */
        address user = makeAddr("user");
        offset = bound(offset, 0, tokens.length - 1);
        TokenParams memory tokenParams = TokenParams(erc20Tokens[offset], aTokensWrapper[offset], 0);

        /* Assumptions */
        vm.assume(amount <= tokenParams.token.balanceOf(address(this)) / 2);
        vm.assume(amount > 10 ** tokenParams.token.decimals() / 100);

        /* Deposit tests */
        fixture_MiniPoolDeposit(amount, offset, user, tokenParams);
    }

    function testMiniPoolNormalBorrow(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * Test Scenario:
         * 1. User adds token as collateral into the miniPool
         * 2. User borrows token
         * Invariants:
         * 1. Balance of debtToken for user in IERC6909 standard increased
         * 2. Total supply of debtToken shall increase
         * 3. Health of user's position shall decrease
         * 4. User shall have borrowed assets
         *
         */

        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
        console.log("[collateral]Offset: ", collateralOffset);
        console.log("[borrow]Offset: ", borrowOffset);

        /* Test vars */
        address user = makeAddr("user");
        TokenParams memory collateralTokenParams = TokenParams(
            erc20Tokens[collateralOffset],
            aTokensWrapper[collateralOffset],
            oracle.getAssetPrice(address(erc20Tokens[collateralOffset]))
        );
        TokenParams memory borrowTokenParams = TokenParams(
            erc20Tokens[borrowOffset],
            aTokensWrapper[borrowOffset],
            oracle.getAssetPrice(address(erc20Tokens[borrowOffset]))
        );
        /* Assumptions */
        amount = bound(
            amount,
            10 ** (borrowTokenParams.token.decimals() - 2),
            borrowTokenParams.token.balanceOf(address(this)) / 10
        );
        deal(
            address(collateralTokenParams.token),
            user,
            collateralTokenParams.token.balanceOf(address(this))
        );
        fixture_miniPoolBorrow(
            amount, collateralOffset, borrowOffset, collateralTokenParams, borrowTokenParams, user
        );
    }
}
