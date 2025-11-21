// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./LendingPoolFixtures.t.sol";
import "../../contracts/protocol/libraries/helpers/Errors.sol";

contract LendingPoolLendingPoolFixRateStrategyTest is LendingPoolFixtures {
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    ERC20[] erc20Tokens;

    function setUp() public override {
        super.setUp();
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

        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
    }

    function testInflationProtectionWithHighRates(uint256 timeToSkip) public {
        timeToSkip = bound(timeToSkip, 1, 5 days);
        TokenTypes memory tokenT = TokenTypes(
            erc20Tokens[0], commonContracts.aTokens[0], commonContracts.variableDebtTokens[0]
        );
        DefaultReserveInterestRateStrategy highVolatileStrategy = new DefaultReserveInterestRateStrategy(
            ILendingPoolAddressesProvider(address(deployedContracts.lendingPoolAddressesProvider)),
            0.45e27,
            4e27,
            100e27,
            200e27
        );
        DataTypes.ReserveData memory reserveData =
            deployedContracts.lendingPool.getReserveData(address(tokenT.token), true);
        console2.log("2. AToken address RSRV: ", reserveData.aTokenAddress);
        console2.log("2. AToken comm: ", address(commonContracts.aTokens[0]));

        vm.label(address(highVolatileStrategy), "NewStrat Volatile");

        vm.prank(deployedContracts.lendingPoolAddressesProvider.getPoolAdmin());
        deployedContracts.lendingPoolConfigurator
            .setReserveInterestRateStrategyAddress(
                address(tokenT.token), true, address(highVolatileStrategy)
            );

        // test revert
        uint256 amountToBorrow = 10_000e6;
        uint256 borrowTokenDepositAmount = amountToBorrow * 15 / 10;

        require(
            tokenT.token.balanceOf(address(this)) > borrowTokenDepositAmount, "Too less borrowToken"
        );

        console2.log("borrowTokenDepositAmount: ", borrowTokenDepositAmount);
        /* Provider deposits wbtc thanks to that there is enough funds to borrow */
        fixture_deposit(
            tokenT.token, tokenT.aToken, address(this), address(this), borrowTokenDepositAmount
        );

        DynamicData memory dynamicData = deployedContracts.asteraDataProvider
        .getLpReserveDynamicData(address(tokenT.token), true);

        console2.log("1. AToken balance: ", tokenT.token.balanceOf(address(tokenT.aToken)));
        console2.log("1. DynamicData: ", dynamicData.liquidityIndex);
        /* Borrower borrows maxPossible amount of borrowToken */
        vm.startPrank(address(this));
        deployedContracts.lendingPool
            .borrow(address(tokenT.token), true, amountToBorrow, address(this));
        vm.stopPrank();
        dynamicData = deployedContracts.asteraDataProvider
            .getLpReserveDynamicData(address(tokenT.token), true);
        console2.log("2. AToken balance: ", tokenT.token.balanceOf(address(tokenT.aToken)));
        console2.log("2. DynamicData: ", dynamicData.liquidityIndex);

        console2.log("Time travel 1");
        vm.warp(block.timestamp + timeToSkip);
        vm.roll(block.number + 20);

        tokenT.token.approve(address(deployedContracts.lendingPool), borrowTokenDepositAmount);
        vm.expectRevert(bytes(Errors.RL_LIQUIDITY_INDEX_THRESHOLD_EXCEEDED));
        deployedContracts.lendingPool
            .deposit(address(tokenT.token), true, borrowTokenDepositAmount, address(this));

        dynamicData = deployedContracts.asteraDataProvider
            .getLpReserveDynamicData(address(tokenT.token), true);

        console2.log("3. DynamicData: ", dynamicData.liquidityIndex);

        DefaultReserveInterestRateStrategy newVolatileStrategy = new DefaultReserveInterestRateStrategy(
            ILendingPoolAddressesProvider(address(deployedContracts.lendingPoolAddressesProvider)),
            1e27,
            0.01e27,
            0e27,
            0e27
        );
        vm.startPrank(deployedContracts.lendingPoolAddressesProvider.getPoolAdmin());
        deployedContracts.lendingPoolConfigurator
            .setLiquidityIndexThreshold(address(tokenT.token), true, type(uint16).max);
        deployedContracts.lendingPoolConfigurator
                .setBorrowIndexThreshold(address(tokenT.token), true, type(uint16).max);
        deployedContracts.lendingPoolConfigurator
                .setReserveInterestRateStrategyAddress(
                address(tokenT.token), true, address(newVolatileStrategy)
            );
        console2.log("4. DynamicData: ", dynamicData.liquidityIndex);

        console2.log("Time travel 2");
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 20);

        console2.log("Setting thresholds");
        deployedContracts.lendingPoolConfigurator
            .setBorrowIndexThreshold(address(tokenT.token), true, 5000);
        deployedContracts.lendingPoolConfigurator
                .setReserveInterestRateStrategyAddress(
                address(tokenT.token), true, address(highVolatileStrategy)
            );
        vm.stopPrank();

        console2.log("Time travel 3");
        vm.warp(block.timestamp + timeToSkip);
        vm.roll(block.number + 20);

        console2.log("3.Depositing");
        vm.expectRevert(bytes(Errors.RL_BORROW_INDEX_THRESHOLD_EXCEEDED));
        deployedContracts.lendingPool
            .deposit(address(tokenT.token), true, borrowTokenDepositAmount, address(this));

        dynamicData = deployedContracts.asteraDataProvider
            .getLpReserveDynamicData(address(tokenT.token), true);

        console2.log("5. DynamicData: ", dynamicData.liquidityIndex);

        vm.startPrank(deployedContracts.lendingPoolAddressesProvider.getPoolAdmin());
        deployedContracts.lendingPoolConfigurator
            .setBorrowIndexThreshold(address(tokenT.token), true, type(uint16).max);
        deployedContracts.lendingPoolConfigurator
                .setReserveInterestRateStrategyAddress(
                address(tokenT.token), true, address(newVolatileStrategy)
            );
        deployedContracts.lendingPoolConfigurator
            .setLiquidityIndexThreshold(address(tokenT.token), true, 3000);
        deployedContracts.lendingPoolConfigurator
                .setBorrowIndexThreshold(address(tokenT.token), true, 6000);
        vm.stopPrank();

        console2.log("Time travel 5");
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 20);

        console2.log("4.Depositing");
        deployedContracts.lendingPool
            .deposit(address(tokenT.token), true, borrowTokenDepositAmount, address(this));

        dynamicData = deployedContracts.asteraDataProvider
            .getLpReserveDynamicData(address(tokenT.token), true);

        console2.log("6. DynamicData: ", dynamicData.liquidityIndex);
    }

    function testLastDayTimestampUpdates() public {
        // tokenOffset = bound(tokenOffset, 0, 4);
        TokenTypes memory tokenT = TokenTypes(
            erc20Tokens[2], commonContracts.aTokens[1], commonContracts.variableDebtTokens[0]
        );
        uint256 amount = 10 ** tokenT.token.decimals();
        tokenT.token.approve(address(deployedContracts.lendingPool), type(uint256).max);
        /* Provider deposits wbtc thanks to that there is enough funds to borrow */
        deployedContracts.lendingPool.deposit(address(tokenT.token), true, amount, address(this));

        DataTypes.ReserveData memory reserveData =
            deployedContracts.lendingPool.getReserveData(address(tokenT.token), true);

        /* Borrower borrows maxPossible amount of borrowToken */
        vm.startPrank(address(this));
        deployedContracts.lendingPool.borrow(address(tokenT.token), true, amount / 2, address(this));
        vm.stopPrank();
        reserveData = deployedContracts.lendingPool.getReserveData(address(tokenT.token), true);
        uint256 lastDayTimestamp = reserveData.lastDayTimestamp;
        console2.log("Time travel 1");
        vm.warp(block.timestamp + (1 days - 1));
        vm.roll(block.number + 20);
        deployedContracts.lendingPool.deposit(address(tokenT.token), true, amount, address(this));
        reserveData = deployedContracts.lendingPool.getReserveData(address(tokenT.token), true);
        assertEq(
            lastDayTimestamp,
            reserveData.lastDayTimestamp,
            "Timestamps are not equal after 1 day - 1"
        );
        uint256 expectedBlockNumber = block.timestamp + 1;
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        deployedContracts.lendingPool.deposit(address(tokenT.token), true, amount, address(this));
        reserveData = deployedContracts.lendingPool.getReserveData(address(tokenT.token), true);
        assertNotEq(
            lastDayTimestamp, reserveData.lastDayTimestamp, "Timestamps are equal after 1 day"
        );
        assertEq(
            reserveData.lastDayTimestamp, expectedBlockNumber, "Last timestamp has not proper value"
        );
    }

    function testChartVisualizationOfIndex() public {
        // Increase the index and log it in time together with threshold
    }
}
