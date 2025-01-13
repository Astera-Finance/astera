// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {IMiniPoolRewarder} from "contracts/interfaces/IMiniPoolRewarder.sol";

contract ATokenErc6909Test is Common {
    using WadRayMath for uint256;

    struct TestParams {
        uint256 id;
        uint256 nrOfIterations;
        address user;
    }

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    DeployedMiniPoolContracts miniPoolContracts;

    ConfigAddresses configAddresses;
    IAERC6909 aErc6909Token;
    address miniPool;

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
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
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        commonContracts.mockedVaults =
            fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
        (miniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
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

        configAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts, 0);
        vm.label(miniPool, "MiniPool");

        aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
    }

    function testAccessControl_NotLiquidityPool() public {
        address addr = makeAddr("RandomAddress");
        for (uint32 idx = 0; idx < commonContracts.aTokens.length; idx++) {
            vm.expectRevert(bytes(Errors.AT_CALLER_MUST_BE_LENDING_POOL));
            aErc6909Token.mint(address(this), address(this), 1, 1, 1);
            vm.expectRevert(bytes(Errors.AT_CALLER_MUST_BE_LENDING_POOL));
            aErc6909Token.mintToCod3xTreasury(1, 1, 1);
            vm.expectRevert(bytes(Errors.AT_CALLER_MUST_BE_LENDING_POOL));
            aErc6909Token.burn(admin, admin, 1, 1, false, 1);
            vm.expectRevert(bytes(Errors.AT_CALLER_MUST_BE_LENDING_POOL));
            aErc6909Token.transferOnLiquidation(admin, addr, 0, 1);
            vm.expectRevert(bytes(Errors.AT_CALLER_MUST_BE_LENDING_POOL));
            aErc6909Token.setIncentivesController(IMiniPoolRewarder(addr));
            vm.expectRevert(bytes(Errors.AT_CALLER_MUST_BE_LENDING_POOL));
            aErc6909Token.transferUnderlyingTo(addr, 11, 1, false);
            vm.expectRevert(bytes(Errors.AT_CALLER_MUST_BE_LENDING_POOL));
            aErc6909Token.mintToCod3xTreasury(1, 11, 1);
        }
    }

    function testErc6909Minting_AToken(uint256 maxValToMint, uint256 index, uint256 offset)
        public
    {
        uint8 nrOfIterations = 20;

        /* Fuzz vector creation */
        maxValToMint = bound(maxValToMint, nrOfIterations * 10, 20_000_000);
        //maxValToMint = 10000;
        offset = bound(offset, 0, tokens.length - 1);
        uint256 id = 1000 + offset;

        //index = 1e27;
        // Below index values generates issues !
        // index = 2 * 1e27;
        index = bound(index, 1e27, 10e27); // assume index increases in time as the interest accumulates
        vm.assume(maxValToMint.rayDiv(index) > 0);

        uint256 granuality = maxValToMint / nrOfIterations;
        vm.assume(granuality.rayDiv(index) > 0);
        vm.assume(maxValToMint % granuality == 0); // accept only multiplicity of {nrOfIterations}
        // maxValToMint = maxValToMint - (maxValToMint % granuality);
        vm.startPrank(miniPool);
        console.log("Balance before: ", aErc6909Token.balanceOf(address(this), id));

        /* Additiveness check */
        for (uint256 cnt = 0; cnt < maxValToMint; cnt += granuality) {
            console.log("granuality: ", granuality);
            aErc6909Token.mint(address(this), address(this), id, granuality, index);
        }
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), id),
            maxValToMint.rayDiv(index),
            nrOfIterations / 2
        );
        console.log("Minting: ", maxValToMint.rayDiv(index));
        aErc6909Token.mint(address(this), address(this), id, maxValToMint, index);
        console.log(
            "aErc6909Token.balanceOf(address(this): ", aErc6909Token.balanceOf(address(this), id)
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), id),
            2 * maxValToMint.rayDiv(index),
            nrOfIterations / 2
        );
        console.log("current id %s", id);
        console.log("Total supply: ", aErc6909Token.scaledTotalSupply(id));
        assertApproxEqAbs(
            aErc6909Token.scaledTotalSupply(id), 2 * maxValToMint.rayDiv(index), nrOfIterations / 2
        );

        vm.stopPrank();
    }

    function testErc6909Minting_Token(uint256 maxValToMint, uint256 index, uint256 offset) public {
        uint8 nrOfIterations = 20;

        /* Fuzz vector creation */
        maxValToMint = bound(maxValToMint, nrOfIterations * 10, 20_000_000);
        //maxValToMint = 10000;
        offset = bound(offset, 0, tokens.length - 1);
        uint256 id = 1128 + offset;

        //index = 1e27;
        // Below index values generates issues !
        // index = 2 * 1e27;
        index = bound(index, 1e27, 10e27); // assume index increases in time as the interest accumulates
        vm.assume(maxValToMint.rayDiv(index) > 0);

        uint256 granuality = maxValToMint / nrOfIterations;
        vm.assume(granuality.rayDiv(index) > 0);
        vm.assume(maxValToMint % granuality == 0); // accept only multiplicity of {nrOfIterations}
        // maxValToMint = maxValToMint - (maxValToMint % granuality);
        vm.startPrank(miniPool);
        console.log("Balance before: ", aErc6909Token.balanceOf(address(this), id));

        /* Additiveness check */
        for (uint256 cnt = 0; cnt < maxValToMint; cnt += granuality) {
            console.log("granuality: ", granuality);
            aErc6909Token.mint(address(this), address(this), id, granuality, index);
        }
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), id),
            maxValToMint.rayDiv(index),
            nrOfIterations / 2
        );
        console.log("Minting: ", maxValToMint.rayDiv(index));
        aErc6909Token.mint(address(this), address(this), id, maxValToMint, index);
        console.log(
            "aErc6909Token.balanceOf(address(this): ", aErc6909Token.balanceOf(address(this), id)
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), id),
            2 * maxValToMint.rayDiv(index),
            nrOfIterations / 2
        );
        console.log("current id %s", id);
        console.log("Total supply: ", aErc6909Token.totalSupply(id));
        assertApproxEqAbs(
            aErc6909Token.totalSupply(id), 2 * maxValToMint.rayDiv(index), nrOfIterations / 2
        );

        vm.stopPrank();
    }

    function testErc6909Minting_DebtToken(uint256 maxValToMint, uint256 index, uint256 offset)
        public
    {
        uint8 nrOfIterations = 20;

        /* Fuzz vector creation */
        maxValToMint = bound(maxValToMint, nrOfIterations * 10, 20_000_000);
        offset = bound(offset, 0, tokens.length - 1);
        uint256 id = 2000 + offset;

        //index = 1e27;
        // Below index values generates issues !
        // index = 2 * 1e27;
        index = bound(index, 1e27, 10e27); // assume index increases in time as the interest accumulates
        vm.assume(maxValToMint.rayDiv(index) > 0);

        uint256 granuality = maxValToMint / nrOfIterations;
        vm.assume(maxValToMint % granuality == 0); // accept only multiplicity of {nrOfIterations}
        // maxValToMint = maxValToMint - (maxValToMint % granuality);
        vm.startPrank(miniPool);
        console.log("Balance before: ", aErc6909Token.balanceOf(address(this), id));

        /* Additiveness check */
        for (uint256 cnt = 0; cnt < maxValToMint; cnt += granuality) {
            aErc6909Token.approveDelegation(address(this), id, granuality);
            aErc6909Token.mint(address(this), miniPool, id, granuality, index);
        }
        assertApproxEqAbs(
            aErc6909Token.balanceOf(miniPool, id), maxValToMint.rayDiv(index), nrOfIterations / 2
        );
        console.log("Minting: ", maxValToMint.rayDiv(index));
        aErc6909Token.approveDelegation(address(this), id, maxValToMint);
        aErc6909Token.mint(address(this), miniPool, id, maxValToMint, index);
        assertApproxEqAbs(
            aErc6909Token.balanceOf(miniPool, id),
            2 * maxValToMint.rayDiv(index),
            nrOfIterations / 2
        );
        // assertEq(aErc6909Token.borrowAllowances(miniPool, address(this), id), 0);
        console.log("Total supply: ", aErc6909Token.scaledTotalSupply(id));
        assertApproxEqAbs(
            aErc6909Token.scaledTotalSupply(id), 2 * maxValToMint.rayDiv(index), nrOfIterations / 2
        );

        vm.stopPrank();
    }

    /* mintToTreasury */
    function testErc6909MintingToTreasury_AToken(
        uint256 maxValToMint,
        uint256 index,
        uint256 offset
    ) public {
        /**
         * Preconditions:
         * 1. ATokens must be available for user (funds deposited)
         * Test Scenario:
         * 1. Perform mintToTreasury actions to check additivenes after some time elapsed
         * 2. Perform one big mintToTreasury after some time elapsed
         * Invariants:
         * 1. Balances of treasury must reflect minting
         */
        uint8 nrOfIterations = 20;

        /* Fuzz vector creation */
        maxValToMint = bound(maxValToMint, nrOfIterations * 10, 20_000_000);
        offset = bound(offset, 0, tokens.length - 1);
        //index = 1e27;
        uint256 id = 1000 + offset;
        address treasury = makeAddr("treasury");
        // Below index values generates issues !
        // index = 2 * 1e27;
        index = bound(index, 1e27, 10e27); // assume index increases in time as the interest accumulates
        vm.assume(maxValToMint.rayDiv(index) > 0);
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setCod3xTreasury(treasury);
        uint256 granuality = maxValToMint / nrOfIterations;
        vm.assume(maxValToMint % granuality == 0); // accept only multiplicity of {nrOfIterations}
        // maxValToMint = maxValToMint - (maxValToMint % granuality);
        vm.startPrank(miniPool);
        console.log("Balance before: ", aErc6909Token.balanceOf(treasury, id));
        console.log("Index: ", index);
        /* Additiveness check */
        uint8 counter = 0;
        for (uint256 cnt = 0; cnt < maxValToMint; cnt += granuality) {
            console.log("granuality: ", granuality);
            aErc6909Token.mintToCod3xTreasury(id, granuality, index);
            counter++;
        }
        assertApproxEqAbs(
            aErc6909Token.balanceOf(treasury, id), maxValToMint.rayDiv(index), nrOfIterations
        ); // We accept some calculation rounding violations from loop
        console.log("Minting: ", maxValToMint.rayDiv(index));
        console.log("Balance of treasury: ", aErc6909Token.balanceOf(treasury, id));
        aErc6909Token.mintToCod3xTreasury(id, maxValToMint, index);
        assertApproxEqAbs(
            aErc6909Token.balanceOf(treasury, id), 2 * maxValToMint.rayDiv(index), nrOfIterations
        );

        assertApproxEqAbs(
            aErc6909Token.scaledTotalSupply(id), 2 * maxValToMint.rayDiv(index), nrOfIterations
        );

        vm.stopPrank();
    }

    function testBurningErc6909_ATokens(uint256 maxValToBurn, uint256 timeDiff, uint256 offset)
        public
    {
        uint8 nrOfIterations = 20;
        /* Fuzz vector creation */
        offset = bound(offset, 0, tokens.length - 1);
        uint256 id = 1000 + offset;
        TokenParams memory tokenParams =
            TokenParams(erc20Tokens[offset], commonContracts.aTokensWrapper[offset], 0);
        maxValToBurn = bound(
            maxValToBurn,
            nrOfIterations * 10 ** (tokenParams.token.decimals() - 2),
            tokenParams.token.balanceOf(address(this)) / 4
        );
        timeDiff = bound(timeDiff, 0 days, 10000 days);
        timeDiff = 100 days;
        uint256 index = 1e27;
        vm.assume(maxValToBurn.rayMul(index) > 0);

        uint256 granuality = maxValToBurn / nrOfIterations;
        vm.assume(maxValToBurn % granuality == 0); // accept only multiplicity of {nrOfIterations}

        assertEq(aErc6909Token.getUnderlyingAsset(id), address(tokenParams.aToken));

        /* Deposit token to the lending pool */
        tokenParams.token.approve(address(deployedContracts.lendingPool), 3 * maxValToBurn);
        deployedContracts.lendingPool.deposit(
            address(tokenParams.token), true, 3 * maxValToBurn, address(this)
        );

        /* Deposit aToken into the mini pool */
        tokenParams.aToken.approve(miniPool, 3 * maxValToBurn);
        IMiniPool(miniPool).deposit(
            address(tokenParams.aToken), false, 3 * maxValToBurn, address(this)
        );

        /* Borrow aToken from mini pool */
        console.log(
            "1. aErc6909Token after deposit %s ", aErc6909Token.balanceOf(address(this), id)
        );

        console.log(
            "1. aToken after deposit %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token))
        );
        console.log(
            "1. underlyingToken after deposit %s ",
            tokenParams.token.balanceOf(address(tokenParams.aToken))
        );
        console.log(
            "SourceOfAsset %s: >>>>>>>>>>>>>> %s",
            address(tokenParams.token),
            commonContracts.oracle.getSourceOfAsset(address(tokenParams.token))
        );
        IMiniPool(miniPool).borrow(address(tokenParams.aToken), false, maxValToBurn, address(this));
        skip(timeDiff);
        index = IMiniPool(miniPool).getReserveNormalizedIncome(address(tokenParams.aToken));
        console.log(">>>Index: ", index);
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), id),
            3 * maxValToBurn.rayMul(index),
            nrOfIterations / 2
        );
        console.log(
            "2. aErc6909Token after deposit %s ", aErc6909Token.balanceOf(address(this), id)
        );

        console.log(
            "2. aToken after deposit %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token))
        );
        console.log(
            "2. underlyingToken after deposit %s ",
            tokenParams.token.balanceOf(address(tokenParams.aToken))
        );

        vm.startPrank(miniPool);
        uint256 initialAmountOfUnderlying =
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(this));
        /* Additiveness check */
        console.log(
            "1. Token balance %s and ABalance %s - burn 1 time",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token)),
            aErc6909Token.balanceOf(address(this), id)
        );
        for (uint256 cnt = 0; cnt < maxValToBurn; cnt += granuality) {
            console.log(
                "Granual: %s vs %s",
                aErc6909Token.balanceOf(address(this), id),
                (3 * maxValToBurn).rayMul(index) - cnt
            );
            console.log("Granuality: ", granuality);
            console.log("Granuality cumulated: ", cnt.rayDiv(index));
            aErc6909Token.burn(address(this), address(this), id, granuality, false, index);
        }

        console.log(
            "%s vs %s",
            aErc6909Token.balanceOf(address(this), id),
            (3 * maxValToBurn).rayMul(index) - maxValToBurn
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), id),
            (3 * maxValToBurn).rayMul(index) - maxValToBurn,
            nrOfIterations
        );
        console.log(
            "3. aErc6909Token after 1 burning %s ", aErc6909Token.balanceOf(address(this), id)
        );

        console.log(
            "3. aToken after 1 burning %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token))
        );
        console.log(
            "3. underlyingToken after 1 burning %s ",
            tokenParams.token.balanceOf(address(tokenParams.aToken))
        );

        console.log(
            "UnderlyingAsset partial burns ballance shall be {maxValToBurn} adjusted with {index}"
        );
        console.log(
            "%s vs %s",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(this)),
            initialAmountOfUnderlying + maxValToBurn
        );
        assertEq(
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(this)),
            initialAmountOfUnderlying + maxValToBurn
        );

        initialAmountOfUnderlying =
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(this));
        console.log(
            "2. Token balance %s and ABalance %s - burn 2 time",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token)),
            aErc6909Token.balanceOf(address(this), id)
        );
        aErc6909Token.burn(address(this), address(this), id, maxValToBurn, false, index);
        console.log("After single burn balance shall be {maxValToBurn} adjusted with {index}");
        console.log(
            "4. aErc6909Token after 2 burning %s ", aErc6909Token.balanceOf(address(this), id)
        );

        console.log(
            "4. aToken after 2 burning %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token))
        );
        console.log(
            "4. underlyingToken after 2 burning %s ",
            tokenParams.token.balanceOf(address(tokenParams.aToken))
        );
        assertApproxEqAbs(
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(this)),
            initialAmountOfUnderlying + maxValToBurn,
            nrOfIterations,
            "Balance of underlying is not lower by maxValToBurn"
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), id),
            (3 * maxValToBurn).rayMul(index) - 2 * maxValToBurn,
            nrOfIterations,
            "Balance of miniPool aTokens is not lower by maxValToBurn"
        );

        assertApproxEqAbs(
            aErc6909Token.totalSupply(id),
            (3 * maxValToBurn).rayMul(index) - 2 * maxValToBurn,
            nrOfIterations,
            "Total supply of miniPool aTokens is not lower by maxValToBurn"
        );

        console.log("Cannot burn 3th time because it is not available (assets are borrowed)");
        vm.expectRevert();
        aErc6909Token.burn(address(this), address(this), id, maxValToBurn, false, index);
        vm.stopPrank();
    }

    function testErc6909TransferFrom_AToken(uint256 valToTransfer, uint256 offset, uint256 timeDiff)
        public
    {
        /**
         * Preconditions:
         * 1. ATokens must be available for user (funds deposited)
         * Test Scenario:
         * 1. Perform transferFrom actions to check additivenes after some time elapsed
         * 2. Perform one big transferFrom after some time elapsed
         * Invariants:
         * 1. Balances of accounts 'from' and 'to' must reflects token transfers
         */
        /* Fuzz vector creation */
        timeDiff = bound(timeDiff, 0 days, 10000 days); // Fuzzing time to skip
        offset = bound(offset, 0, tokens.length - 3);
        TestParams memory testParams = TestParams(1000 + offset, 20, makeAddr("User"));
        valToTransfer = bound(valToTransfer, testParams.nrOfIterations * 10, 10_000_000);
        uint256 index = 1e27;
        TokenParams memory tokenParams =
            TokenParams(erc20Tokens[offset], commonContracts.aTokensWrapper[offset], 0);

        uint256 granuality = valToTransfer / testParams.nrOfIterations;
        vm.assume(valToTransfer % granuality == 0); // accept only multiplicity of {nrOfIterations} -> avoid issues with rounding

        tokenParams.token.approve(address(deployedContracts.lendingPool), 4 * valToTransfer);
        deployedContracts.lendingPool.deposit(
            address(tokenParams.token), true, 4 * valToTransfer, address(this)
        );

        console.log(
            "1. aErc6909Token before deposit to the mini pool %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(testParams.id)).balanceOf(
                address(aErc6909Token)
            )
        );
        console.log(
            "1. underlyingToken before deposit to the mini pool %s ",
            tokenParams.token.balanceOf(address(tokenParams.aToken))
        );

        tokenParams.aToken.approve(miniPool, 4 * valToTransfer);
        IMiniPool(miniPool).deposit(
            address(tokenParams.aToken), false, 4 * valToTransfer, address(this)
        );
        console.log(
            "2. aErc6909Token after deposit %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(testParams.id)).balanceOf(
                address(aErc6909Token)
            )
        );
        console.log(
            "2. underlyingToken after deposit %s ",
            tokenParams.token.balanceOf(address(tokenParams.aToken))
        );

        IMiniPool(miniPool).borrow(address(tokenParams.aToken), false, valToTransfer, address(this));
        vm.startPrank(miniPool);
        console.log("Balance before: ", aErc6909Token.balanceOf(address(this), testParams.id));

        // console.log("aErc6909Token.balanceOf(address(this): ", aErc6909Token.balanceOf(address(this), id));
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), testParams.id),
            4 * valToTransfer,
            testParams.nrOfIterations / 2
        );
        uint256 initialTotalSupply = aErc6909Token.scaledTotalSupply(testParams.id);
        assertEq(initialTotalSupply, 4 * valToTransfer);
        vm.stopPrank();

        skip(timeDiff);
        index = IMiniPool(miniPool).getReserveNormalizedIncome(address(tokenParams.aToken));
        console.log("1. Choosen index: ", index);

        /* Additiveness check */
        uint256 initialUserBalance = aErc6909Token.balanceOf(testParams.user, testParams.id);
        uint256 initialThisBalance = aErc6909Token.balanceOf(address(this), testParams.id);

        aErc6909Token.approve(testParams.user, testParams.id, type(uint256).max);
        for (uint256 cnt = 0; cnt < valToTransfer; cnt += granuality) {
            // console.log("from", address(this));
            // console.log("to", testParams.user);
            // console.log("id", testParams.id);
            // console.log("cnt", cnt);
            console.log(
                "1. Balance aErc6909Token: ",
                aErc6909Token.balanceOf(address(testParams.user), testParams.id)
            );
            console.log(
                "1. Balance aErc6909Token: ", aErc6909Token.balanceOf(address(this), testParams.id)
            );

            vm.prank(testParams.user);
            aErc6909Token.transferFrom(address(this), testParams.user, testParams.id, granuality);
        }
        console.log("Granuality: ", granuality);
        console.log("Granuality scaled: ", granuality.rayDiv(index));
        index = IMiniPool(miniPool).getReserveNormalizedIncome(address(tokenParams.aToken));
        console.log("2. Choosen index: ", index);
        console.log(
            "Check balance of user.. %s vs %s",
            aErc6909Token.balanceOf(testParams.user, testParams.id),
            initialUserBalance + valToTransfer
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(testParams.user, testParams.id),
            initialUserBalance + valToTransfer,
            testParams.nrOfIterations
        );
        console.log(
            "Check balance of this.. %s vs %s",
            aErc6909Token.balanceOf(address(this), testParams.id),
            initialThisBalance - valToTransfer
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), testParams.id),
            initialThisBalance - valToTransfer,
            testParams.nrOfIterations
        );
        console.log(
            "2. Balance aErc6909Token: ",
            aErc6909Token.balanceOf(address(testParams.user), testParams.id)
        );
        console.log(
            "2. Balance aErc6909Token: ", aErc6909Token.balanceOf(address(this), testParams.id)
        );

        initialUserBalance = aErc6909Token.balanceOf(testParams.user, testParams.id);
        initialThisBalance = aErc6909Token.balanceOf(address(this), testParams.id);
        vm.prank(testParams.user);
        console.log("3. val transfer: ", valToTransfer);
        console.log("3. val transfer scaled: ", valToTransfer.rayDiv(index));
        aErc6909Token.transferFrom(address(this), testParams.user, testParams.id, valToTransfer);
        console.log(
            "3. Balance aErc6909Token: ",
            aErc6909Token.balanceOf(address(testParams.user), testParams.id)
        );
        console.log(
            "3. Balance aErc6909Token: ", aErc6909Token.balanceOf(address(this), testParams.id)
        );
        console.log(
            "Check balance of user.. %s vs %s",
            aErc6909Token.balanceOf(testParams.user, testParams.id),
            initialUserBalance + valToTransfer
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(testParams.user, testParams.id),
            initialUserBalance + valToTransfer,
            testParams.nrOfIterations
        );
        console.log(
            "Check balance of this.. %s vs %s",
            aErc6909Token.balanceOf(address(this), testParams.id),
            initialThisBalance - valToTransfer
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), testParams.id),
            initialThisBalance - valToTransfer,
            1 //testParams.nrOfIterations
        );

        assertEq(
            initialTotalSupply,
            aErc6909Token.scaledTotalSupply(testParams.id),
            "ScaledTotalSupply wrong"
        );
    }

    function testErc6909Transfer_AToken(uint256 valToTransfer, uint256 offset, uint256 index)
        public
    {
        uint8 nrOfIterations = 20;
        address user = makeAddr("User");
        /* Fuzz vector creation */
        offset = bound(offset, 0, tokens.length - 1);
        uint256 id = 1000 + offset;
        valToTransfer = bound(valToTransfer, nrOfIterations * 10, 20_000_000);
        index = 1e27;
        // index = bound(index, 1e27, UINT256_MAX); // assume index increases in time as the interest accumulates

        vm.assume(valToTransfer.rayDiv(index) > 0);

        uint256 granuality = valToTransfer / nrOfIterations;
        vm.assume(valToTransfer % granuality == 0); // accept only multiplicity of {nrOfIterations}
        // maxValToMint = maxValToMint - (maxValToMint % granuality);
        vm.startPrank(miniPool);
        console.log("Balance before: ", aErc6909Token.balanceOf(address(this), id));

        console.log("Minting: ", valToTransfer.rayDiv(index));
        aErc6909Token.mint(address(this), address(this), id, 2 * valToTransfer, index);
        console.log(
            "aErc6909Token.balanceOf(address(this): ", aErc6909Token.balanceOf(address(this), id)
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(address(this), id),
            2 * valToTransfer.rayDiv(index),
            nrOfIterations / 2
        );

        uint256 initialTotalSupply = aErc6909Token.scaledTotalSupply(id);
        assertApproxEqAbs(initialTotalSupply, 2 * valToTransfer.rayDiv(index), nrOfIterations / 2);
        vm.stopPrank();

        /* Additiveness check */
        uint256 initialUserBalance = aErc6909Token.balanceOf(user, id);
        uint256 initialThisBalance = aErc6909Token.balanceOf(address(this), id);
        for (uint256 cnt = 0; cnt < valToTransfer; cnt += granuality) {
            aErc6909Token.transfer(user, id, granuality);
        }
        assertEq(aErc6909Token.balanceOf(user, id), initialUserBalance + valToTransfer);
        assertEq(aErc6909Token.balanceOf(address(this), id), initialThisBalance - valToTransfer);

        aErc6909Token.transfer(user, id, valToTransfer);
        assertEq(aErc6909Token.balanceOf(user, id), initialUserBalance + (2 * valToTransfer));
        assertEq(
            aErc6909Token.balanceOf(address(this), id), initialThisBalance - (2 * valToTransfer)
        );

        assertEq(initialTotalSupply, aErc6909Token.scaledTotalSupply(id));
    }

    /* transferUnderlyingTo */
    function testErc6909TransferUnderlyingTo_AToken(
        uint256 valToTransfer,
        uint256 offset,
        uint256 index
    ) public {
        uint8 nrOfIterations = 20;
        address user = makeAddr("User");

        /* Fuzz vector creation */
        offset = bound(offset, 0, tokens.length - 1);
        uint256 id = 1000 + offset;
        ERC20 underlyingToken = erc20Tokens[offset];
        IERC20 grainUnderlyingToken = IERC20(commonContracts.aTokensWrapper[offset]);
        valToTransfer = bound(valToTransfer, nrOfIterations * 10, 20_000_000);
        // index = 1e27;
        index = bound(index, 1e27, 10e27); // assume index increases in time as the interest accumulates

        vm.assume(valToTransfer.rayDiv(index) > 0);

        uint256 granuality = valToTransfer / nrOfIterations;
        vm.assume(valToTransfer % granuality == 0); // accept only multiplicity of {nrOfIterations}
        // maxValToMint = maxValToMint - (maxValToMint % granuality);

        console.log(
            "1. aErc6909Token before deposit to the lending pool %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token))
        );
        console.log(
            "1. underlyingToken before deposit to the lending pool %s ",
            underlyingToken.balanceOf(address(grainUnderlyingToken))
        );

        underlyingToken.approve(address(deployedContracts.lendingPool), 3 * valToTransfer);
        deployedContracts.lendingPool.deposit(
            address(underlyingToken), true, 3 * valToTransfer, address(this)
        );

        console.log(
            "2. aErc6909Token before deposit to the mini pool %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token))
        );
        console.log(
            "2. underlyingToken before deposit to the mini pool %s ",
            underlyingToken.balanceOf(address(grainUnderlyingToken))
        );

        grainUnderlyingToken.approve(miniPool, 3 * valToTransfer);
        IMiniPool(miniPool).deposit(
            address(grainUnderlyingToken), false, 3 * valToTransfer, address(this)
        );
        console.log(
            "3. aErc6909Token after deposit %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token))
        );
        console.log(
            "3. underlyingToken after deposit %s ",
            underlyingToken.balanceOf(address(grainUnderlyingToken))
        );

        vm.startPrank(miniPool);
        /* Additiveness check */
        uint256 initialUserBalance = IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(user);
        uint256 initialThisBalance =
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token));
        console.log("Initial token balance: ", initialThisBalance);

        uint256 initialTotalSupply = aErc6909Token.scaledTotalSupply(id);
        // assertEq(initialTotalSupply, 3 * valToTransfer.rayDiv(index)); // TODO ??

        for (uint256 cnt = 0; cnt < valToTransfer; cnt += granuality) {
            aErc6909Token.transferUnderlyingTo(user, id, granuality, false);
        }
        assertEq(
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(user),
            initialUserBalance + valToTransfer
        );
        assertEq(
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token)),
            initialThisBalance - valToTransfer
        );
        console.log("Single mint");
        aErc6909Token.transferUnderlyingTo(user, id, valToTransfer, false);
        console.log("Assertions");
        assertEq(
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(user),
            initialUserBalance + (2 * valToTransfer)
        );
        assertEq(
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token)),
            initialThisBalance - (2 * valToTransfer)
        );
        assertEq(initialTotalSupply, aErc6909Token.scaledTotalSupply(id));
        vm.stopPrank();
    }

    // Note: isAToken and _determineIfAToken -> the same output

    /* transferOnLiquidation */
    function testErc6909TransferOnLiquidation_AToken(
        uint256 valToTransfer,
        uint256 offset,
        uint256 index
    ) public {
        uint8 nrOfIterations = 20;
        address user = makeAddr("User");
        /* Fuzz vector creation */
        //offset = bound(offset, 0, (2 * tokens.length) - 1);
        offset = bound(offset, 0, tokens.length - 3);
        // offset = 1;
        TokenParams memory tokenParams =
            TokenParams(erc20Tokens[offset], commonContracts.aTokensWrapper[offset], 0);
        uint256 id = 1000 + offset;
        valToTransfer = bound(valToTransfer, nrOfIterations, 20_000_000);
        index = 1e27;
        // index = bound(index, 1e27, UINT256_MAX); // assume index increases in time as the interest accumulates

        vm.assume(valToTransfer.rayDiv(index) > 0);

        uint256 granuality = valToTransfer / nrOfIterations;
        vm.assume(valToTransfer % granuality == 0); // accept only multiplicity of {nrOfIterations}
        // maxValToMint = maxValToMint - (maxValToMint % granuality);

        console.log(
            "1. aErc6909Token before deposit to the lending pool %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token))
        );
        console.log(
            "1. underlyingToken before deposit to the lending pool %s ",
            tokenParams.token.balanceOf(address(tokenParams.aToken))
        );

        tokenParams.token.approve(address(deployedContracts.lendingPool), 3 * valToTransfer);
        deployedContracts.lendingPool.deposit(
            address(tokenParams.token), true, 3 * valToTransfer, address(this)
        );

        console.log(
            "2. aErc6909Token before deposit to the mini pool %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token))
        );
        console.log(
            "2. underlyingToken before deposit to the mini pool %s ",
            tokenParams.token.balanceOf(address(tokenParams.aToken))
        );

        tokenParams.aToken.approve(miniPool, 3 * valToTransfer);
        IMiniPool(miniPool).deposit(
            address(tokenParams.aToken), false, 3 * valToTransfer, address(this)
        );
        console.log(
            "3. aErc6909Token after deposit %s ",
            IERC20(aErc6909Token.getUnderlyingAsset(id)).balanceOf(address(aErc6909Token))
        );
        console.log(
            "3. underlyingToken after deposit %s ",
            tokenParams.token.balanceOf(address(tokenParams.aToken))
        );
        index = IMiniPool(miniPool).getReserveNormalizedIncome(address(tokenParams.aToken));
        console.log("_____ index: ", index);
        IMiniPool(miniPool).borrow(address(tokenParams.aToken), false, valToTransfer, address(this));

        index = IMiniPool(miniPool).getReserveNormalizedIncome(address(tokenParams.aToken));
        console.log("______ index: ", index);
        //skip(timeDiff); // @issue2 when there is a different index due to value appreciation during time, the burning is not proper
        //index = IMiniPool(miniPool).getReserveNormalizedIncome(address(grainUnderlyingToken), false);

        vm.startPrank(miniPool);

        /* Additiveness check */
        uint256 initialUserBalance = aErc6909Token.balanceOf(user, id);
        uint256 initialThisBalance = aErc6909Token.balanceOf(address(this), id);
        uint256 initialTotalSupply = aErc6909Token.scaledTotalSupply(id);
        assertEq(initialTotalSupply, 3 * valToTransfer.rayDiv(index));

        for (uint256 cnt = 0; cnt < valToTransfer; cnt += granuality) {
            console.log("Transfer on liquidation: %s", cnt);
            aErc6909Token.transferOnLiquidation(address(this), user, id, granuality);
        }
        assertEq(aErc6909Token.balanceOf(user, id), initialUserBalance + valToTransfer);
        assertEq(aErc6909Token.balanceOf(address(this), id), initialThisBalance - valToTransfer);
        console.log("Single transfer on liquidation: %s");
        aErc6909Token.transferOnLiquidation(address(this), user, id, valToTransfer);
        assertEq(aErc6909Token.balanceOf(user, id), initialUserBalance + (2 * valToTransfer));
        assertEq(
            aErc6909Token.balanceOf(address(this), id), initialThisBalance - (2 * valToTransfer)
        );
        vm.stopPrank();
        assertEq(initialTotalSupply, aErc6909Token.scaledTotalSupply(id));
    }

    function testErc6909Initialize() public {
        uint256 miniPoolId = miniPoolContracts.miniPoolAddressesProvider.deployMiniPool(
            address(miniPoolContracts.miniPoolImpl),
            address(miniPoolContracts.aToken6909Impl),
            admin
        );
        address[] memory reserves = new address[](1);
        reserves[0] = tokens[0];

        miniPool = fixture_configureMiniPoolReserves(
            reserves, configAddresses, miniPoolContracts, miniPoolId
        );
        vm.label(miniPool, "MiniPool");

        IAERC6909 internalAErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        vm.expectRevert(bytes("Contract instance has already been initialized"));
        internalAErc6909Token.initialize(
            address(miniPoolContracts.miniPoolAddressesProvider), miniPoolId
        );
    }
}
