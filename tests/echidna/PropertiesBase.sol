// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {User} from "./util/User.sol";
import {PropertiesAsserts} from "./util/PropertiesAsserts.sol";
import {MarketParams} from "./MarketParams.sol";

import {BaseImmutableAdminUpgradeabilityProxy} from "contracts/protocol/libraries/upgradeability/BaseImmutableAdminUpgradeabilityProxy.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {ATokensAndRatesHelper} from "contracts/deployments/ATokensAndRatesHelper.sol";

import {MockLendingPool} from "./mock/MockLendingPool.sol";
import {MintableERC20} from "./mock/tokens/MintableERC20.sol";
import {MockAggregator} from "./mock/oracle/MockAggregator.sol";

import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {UserConfiguration} from "contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {ReserveConfiguration} from "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

import {IAERC6909} from "contracts/interfaces/IAERC6909.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "contracts/interfaces/IVariableDebtToken.sol";
import {ICod3xLendDataProvider} from "contracts/interfaces/ICod3xLendDataProvider.sol";
import {IFlashLoanReceiver} from "contracts/interfaces/IFlashLoanReceiver.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IMiniPoolConfigurator} from "contracts/interfaces/IMiniPoolConfigurator.sol";
import {IMiniPoolReserveInterestRateStrategy} from "contracts/interfaces/IMiniPoolReserveInterestRateStrategy.sol";
import {IMiniPoolRewarder} from "contracts/interfaces/IMiniPoolRewarder.sol";
import {IMiniPoolRewardsController} from "contracts/interfaces/IMiniPoolRewardsController.sol";
import {IMiniPoolRewardsDistributor} from "contracts/interfaces/IMiniPoolRewardsDistributor.sol";
import {IOracle} from "contracts/interfaces/IOracle.sol";
import {IReserveInterestRateStrategy} from "contracts/interfaces/IReserveInterestRateStrategy.sol";
import {IRewarder} from "contracts/interfaces/IRewarder.sol";
import {IRewardsController} from "contracts/interfaces/IRewardsController.sol";
import {IRewardsDistributor} from "contracts/interfaces/IRewardsDistributor.sol";

import {Cod3xLendDataProvider} from "contracts/misc/Cod3xLendDataProvider.sol";
import {RewardsVault} from "contracts/misc/RewardsVault.sol";
import {Treasury} from "contracts/misc/Treasury.sol";
import {WETHGateway} from "contracts/misc/WETHGateway.sol";

import {Oracle} from "contracts/protocol/core/Oracle.sol";


/// LendingPool
import {LendingPoolAddressesProvider} from "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";

import {DefaultReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import {PiReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/lendingpool/PiReserveInterestRateStrategy.sol";

import {LendingPool} from "contracts/protocol/core/lendingpool/LendingPool.sol";
import {LendingPoolConfigurator} from "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import {LendingPoolStorage} from "contracts/protocol/core/lendingpool/LendingPoolStorage.sol";

import {BorrowLogic} from "contracts/protocol/core/lendingpool/logic/BorrowLogic.sol";
import {DepositLogic} from "contracts/protocol/core/lendingpool/logic/DepositLogic.sol";
import {FlashLoanLogic} from "contracts/protocol/core/lendingpool/logic/FlashLoanLogic.sol";
import {GenericLogic} from "contracts/protocol/core/lendingpool/logic/GenericLogic.sol";
import {LiquidationLogic} from "contracts/protocol/core/lendingpool/logic/LiquidationLogic.sol";
import {ReserveLogic} from "contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
import {ValidationLogic} from "contracts/protocol/core/lendingpool/logic/ValidationLogic.sol";
import {WithdrawLogic} from "contracts/protocol/core/lendingpool/logic/WithdrawLogic.sol";

import {AToken} from "contracts/protocol/tokenization/ERC20/AToken.sol";
import {VariableDebtToken} from "contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import {ATokenNonRebasing} from "contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";

import {Rewarder} from "contracts/protocol/rewarder/lendingpool/Rewarder.sol";
import {RewardForwarder} from "contracts/protocol/rewarder/lendingpool/RewardForwarder.sol";
import {RewardsController} from "contracts/protocol/rewarder/lendingpool/RewardsController.sol";
import {RewardsDistributor} from "contracts/protocol/rewarder/lendingpool/RewardsDistributor.sol";

import {MockReaperVault2} from "contracts/mocks/tokens/MockVault.sol";
import {MockStrategy} from "contracts/mocks/tokens/MockStrategy.sol";

/// MiniPool
import {FlowLimiter} from "contracts/protocol/core/minipool/FlowLimiter.sol";
import {MiniPool} from "contracts/protocol/core/minipool/MiniPool.sol";
import {MiniPoolConfigurator} from "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import {MiniPoolStorage} from "contracts/protocol/core/minipool/MiniPoolStorage.sol";

import {MiniPoolBorrowLogic} from "contracts/protocol/core/minipool/logic/MiniPoolBorrowLogic.sol";
import {MiniPoolDepositLogic} from "contracts/protocol/core/minipool/logic/MiniPoolDepositLogic.sol";
import {MiniPoolFlashLoanLogic} from "contracts/protocol/core/minipool/logic/MiniPoolFlashLoanLogic.sol";
import {MiniPoolGenericLogic} from "contracts/protocol/core/minipool/logic/MiniPoolGenericLogic.sol";
import {MiniPoolLiquidationLogic} from "contracts/protocol/core/minipool/logic/MiniPoolLiquidationLogic.sol";
import {MiniPoolReserveLogic} from "contracts/protocol/core/minipool/logic/MiniPoolReserveLogic.sol";
import {MiniPoolValidationLogic} from "contracts/protocol/core/minipool/logic/MiniPoolValidationLogic.sol";
import {MiniPoolWithdrawLogic} from "contracts/protocol/core/minipool/logic/MiniPoolWithdrawLogic.sol";

import {ATokenERC6909} from "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";

import {Rewarder6909} from "contracts/protocol/rewarder/minipool/Rewarder6909.sol";
import {RewardsController6909} from "contracts/protocol/rewarder/minipool/RewardsController6909.sol";
import {RewardsDistributor6909} from "contracts/protocol/rewarder/minipool/RewardsDistributor6909.sol";

// Users are defined in users
// Admin is address(this)
contract PropertiesBase is PropertiesAsserts, MarketParams {
    // config -----------
    uint256 internal totalNbUsers = 4; // max 255
    uint256 internal totalNbTokens = 8; // max 8
    uint256 internal initialMint = 100 ether;
    bool internal bootstrapLiquidity = true;
    uint256 internal volatility = 100; // 1%
    // ------------------

    User internal bootstraper;
    User[] internal users;
    DefaultReserveInterestRateStrategy /*[]*/ internal defaultRateStrategies;
    PiReserveInterestRateStrategy /*[]*/ internal piRateStrategies;

    mapping(address => uint256) internal lastLiquidityIndex;
    mapping(address => uint256) internal lastVariableBorrowIndex;

    // A given assets[i] is accosiated with the liquidity token aTokens[i]
    // and the debt token debtTokens[i].
    MintableERC20[] internal assets; // assets[0] is weth
    MockAggregator[] internal aggregators; // aggregators[0] is the reference (eth pricefeed)
    AToken[] internal aTokens;
    VariableDebtToken[] internal debtTokens;
    uint256[] internal timeouts;
    MockReaperVault2[] internal mockedVaults;

    // Cod3x Lend contracts
    LendingPoolAddressesProvider internal provider;
    MockLendingPool internal pool;
    address internal treasury;
    address internal profitHandler;
    LendingPoolConfigurator internal poolConfigurator;
    ATokensAndRatesHelper internal aHelper;
    AToken internal aToken;
    VariableDebtToken internal vToken;
    Oracle internal oracle;
    Cod3xLendDataProvider internal cod3xLendDataProvider;

    constructor() {
        /// mocks
        uint8 tokenDec = 18;
        for (uint256 i = 0; i < totalNbTokens; i++) {
            uint8 tokenDecTemp = (i % 2 == 0) ? uint8(tokenDec - i) : uint8(tokenDec + i); // various dec [18, 19, 17, 20, 16, 21, 15, 22, 14 ...]
            MintableERC20 t = new MintableERC20("", "", tokenDecTemp);
            assets.push(t);
            MockAggregator a = new MockAggregator(1e18, int256(uint256(tokenDecTemp)));
            aggregators.push(a);
            timeouts.push(0);
        }

        /// setup LendingPool
        provider = new LendingPoolAddressesProvider();
        provider.setPoolAdmin(address(this));
        provider.setEmergencyAdmin(address(this));
        treasury = address(0xAAAA);
        profitHandler = address(0xBBBB);

        pool = new MockLendingPool();
        pool.initialize(provider);
        provider.setLendingPoolImpl(address(pool));
        pool = MockLendingPool(provider.getLendingPool());

        poolConfigurator = new LendingPoolConfigurator();
        provider.setLendingPoolConfiguratorImpl(address(poolConfigurator));
        poolConfigurator = LendingPoolConfigurator(provider.getLendingPoolConfigurator());
        poolConfigurator.setPoolPause(true);

        aHelper = new ATokensAndRatesHelper(
            payable(address(pool)), address(provider), address(poolConfigurator)
        );
        aToken = new AToken();
        vToken = new VariableDebtToken();
        oracle = new Oracle(
            MintableERC20ToAddress(assets),
            MockAggregatorToAddress(aggregators),
            timeouts,
            FALLBACK_ORACLE,
            BASE_CURRENCY,
            BASE_CURRENCY_UNIT
        );

        provider.setPriceOracle(address(oracle));

        cod3xLendDataProvider = new Cod3xLendDataProvider();
        cod3xLendDataProvider.setLendingPoolAddressProvider(address(provider));
        
        defaultRateStrategies = new DefaultReserveInterestRateStrategy(
            provider,
            DEFAULT_OPTI_UTILIZATION_RATE,
            DEFAULT_BASE_VARIABLE_BORROW_RATE,
            DEFAULT_VARIABLE_RATE_SLOPE1,
            DEFAULT_VARIABLE_RATE_SLOPE2
        );
        
        // piRateStrategies = new PiReserveInterestRateStrategy(
        //     provider
        //     // asset,
        //     // assetReserveType,
        //     DEFAULT_MIN_CONTROLLER_ERROR,
        //     DEFAULT_MAX_I_TIME_AMP,
        //     DEFAULT_OPTI_UTILIZATION_RATE,
        //     DEFAULT_KP,
        //     DEFAULT_KI
        // ); // todo setup for some assets

        ILendingPoolConfigurator.InitReserveInput memory ri;
        ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
            new ILendingPoolConfigurator.InitReserveInput[](totalNbTokens);
        for (uint256 i = 0; i < totalNbTokens; i++) {
            ri = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: address(aToken),
                variableDebtTokenImpl: address(vToken),
                underlyingAssetDecimals: assets[i].decimals(),
                interestRateStrategyAddress: address(defaultRateStrategies),
                underlyingAsset: address(assets[i]),
                treasury: address(treasury),
                incentivesController: address(0),
                underlyingAssetName: "",
                reserveType: true, // By default, all assets are potentially rehypothecable but we don't necesserly activate it.
                aTokenName: "",
                aTokenSymbol: "",
                variableDebtTokenName: "",
                variableDebtTokenSymbol: "",
                params: new bytes(0x10)
            });
            initInputParams[i] = ri;
        }
        poolConfigurator.batchInitReserve(initInputParams);

        ATokensAndRatesHelper.ConfigureReserveInput memory cri;
        ATokensAndRatesHelper.ConfigureReserveInput[] memory configureReserveInput =
            new ATokensAndRatesHelper.ConfigureReserveInput[](totalNbTokens);
        for (uint256 i = 0; i < totalNbTokens; i++) {
            cri = ATokensAndRatesHelper.ConfigureReserveInput({
                asset: address(assets[i]),
                reserveType: true,
                baseLTV: DEFAULT_BASE_LTV,
                liquidationThreshold: DEFAULT_LIQUIDATION_THRESHOLD,
                liquidationBonus: DEFAULT_LIQUIDATION_BONUS,
                reserveFactor: DEFAULT_RESERVE_FACTOR,
                borrowingEnabled: true
            });
            configureReserveInput[i] = cri;
        }
        provider.setPoolAdmin(address(aHelper));
        aHelper.configureReserves(configureReserveInput);
        provider.setPoolAdmin(address(this));

        for (uint256 i = 0; i < totalNbTokens; i++) {
            (address aTokenAddress, address variableDebtTokenAddress) =
                cod3xLendDataProvider.getLpTokens(address(assets[i]), true);
            aTokens.push(AToken(aTokenAddress));
            debtTokens.push(VariableDebtToken(variableDebtTokenAddress));
        }

        poolConfigurator.setPoolPause(false);

        // Rehypothecation
        for (uint256 i = 0; i < totalNbTokens; i++) {
            mockedVaults.push(
                new MockReaperVault2(address(assets[i]), "Mock ERC4626", "mock", type(uint256).max, treasury)
            );
            if(i % 2 == 0){
                turnOnRehypothecation(address(aTokens[i]), address(mockedVaults[i]));
            }
        }

        // /// Setup Minipool
        // provider.setFlowLimiter(address(0));
        // provider.setMiniPoolAddressesProvider(address(0));
        // cod3xLendDataProvider.setMiniPoolAddressProvider(address(0));


        /// bootstrap liquidity
        if (bootstrapLiquidity) {
            bootstraper = new User(provider);
            for (uint256 j = 0; j < totalNbTokens; j++) {
                assets[j].mint(address(bootstraper), initialMint);
                bootstraper.approveERC20(assets[j], address(pool));
                (bool success,) = bootstraper.proxy(
                    address(pool),
                    abi.encodeWithSelector(
                        pool.deposit.selector,
                        address(assets[j]),
                        true,
                        initialMint,
                        address(bootstraper)
                    )
                );
                assert(success);
            }
        }

        /// update liquidity index
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = address(assets[i]);

            lastLiquidityIndex[asset] = pool.getReserveData(asset, true).liquidityIndex;
            lastVariableBorrowIndex[asset] = pool.getReserveData(asset, true).variableBorrowIndex;
        }

        /// setup users
        for (uint256 i = 0; i < totalNbUsers; i++) {
            User user = new User(provider);
            users.push(user);
            for (uint256 j = 0; j < totalNbTokens; j++) {
                assets[j].mint(address(user), initialMint);
                user.approveERC20(assets[j], address(pool));
            }
        }

        /// mint to address(this) for randForceFeed
        for (uint256 j = 0; j < totalNbTokens; j++) {
            assets[j].mint(address(this), type(uint160).max);
        }
    }

    /// ------- global state updates -------

    struct LocalVars_UPTL {
        uint8 seedAmtPrice1;
        uint8 seedAmtPrice2;
        uint8 seedAmtPrice3;
        uint8 seedAmtPrice4;
        uint8 seedAmtPrice5;
        uint8 seedAmtPrice6;
        uint8 seedAmtPrice7;
        uint8 seedAmtPrice8; // max 8 assets

        uint8 seedLiquidator;
        uint8 seedColl;
        uint8 seedDebtToken;
        uint128 seedAmtLiq;
        bool randReceiveAToken;
    }

    function randUpdatePriceAndTryLiquidate(LocalVars_UPTL memory v) public {
        uint8[] memory seedAmt = new uint8[](8);
        seedAmt[0] = v.seedAmtPrice1;
        seedAmt[1] = v.seedAmtPrice2;
        seedAmt[2] = v.seedAmtPrice3;
        seedAmt[3] = v.seedAmtPrice4;
        seedAmt[4] = v.seedAmtPrice5;
        seedAmt[5] = v.seedAmtPrice6;
        seedAmt[6] = v.seedAmtPrice7;
        seedAmt[7] = v.seedAmtPrice8;

        oraclePriceUpdate(seedAmt);
        tryLiquidate(
            v.seedLiquidator, v.seedColl, v.seedDebtToken, v.seedAmtLiq, v.randReceiveAToken
        );
    }

    struct LocalVars_TryLiquidate {
        uint256 randLiquidator;
        uint256 randTargetUser;
        uint256 randColl;
        uint256 randDebtToken;
        uint256 randAmt;
        User liquidator;
        User target;
        ERC20 collAsset;
        AToken aTokenColl;
        ERC20 debtAsset;
        VariableDebtToken vTokenDebt;
        uint256 targetATokenCollBalanceBefore;
        uint256 targetATokenCollBalanceAfter;
        uint256 targetVTokenDebtBalanceBefore;
        uint256 targetVTokenDebtBalanceAfter;
        uint256 targetHealthFactorBefore;
        uint256 targetHealthFactorAfter;
        uint256 liquidatorDebtAssetBefore;
        uint256 liquidatorDebtAssetAfter;
        uint256 liquidatorCollAssetBefore;
        uint256 liquidatorCollAssetAfter;
        uint256 liquidatorATokenCollBefore;
        uint256 liquidatorATokenCollAfter;
        AToken[] userAToken;
        ERC20[] userCollAssets;
        VariableDebtToken[] userDebtToken;
        ERC20[] userDebtAssets;
        uint256 lenATokenUser;
        uint256 lenDebtTokenUser;
    }

    /// @custom:invariant 100 - To be liquidated on a given collateral asset, the target user must own the associated `aTokenColl`.
    /// @custom:invariant 101 - To be liquidated on a given token, the target user must own the associated `vTokenDebt`.
    /// @custom:invariant 102 - `liquidationCall()` must only be callable when the target health factor is < 1.
    /// @custom:invariant 103 - `liquidationCall()` must decrease the target `vTokenDebt` balance by `amount`.
    /// @custom:invariant 104 - `liquidationCall()` must increase the liquidator `aTokenColl` (or `collAsset`) balance.
    /// @custom:invariant 105 - `liquidationCall()` must decrease the liquidator debt asset balance if `randReceiveAToken == true` or `collAsset != debtAsset`.
    function tryLiquidate(
        uint8 seedLiquidator,
        uint8 seedColl,
        uint8 seedDebtToken,
        uint128 seedAmt,
        bool randReceiveAToken
    ) internal {
        for (uint256 i = 0; i < users.length; i++) {
            LocalVars_TryLiquidate memory v;

            v.target = users[i];
            (,,,,, v.targetHealthFactorBefore) = pool.getUserAccountData(address(v.target));
            if (v.targetHealthFactorBefore < 1e18) {
                (v.userAToken, v.userCollAssets, v.lenATokenUser) = getAllATokens(v.target);
                (v.userDebtToken, v.userDebtAssets, v.lenDebtTokenUser) = getAllDebtTokens(v.target);

                v.randColl = clampBetween(seedColl, 0, v.lenATokenUser);
                v.randDebtToken = clampBetween(seedDebtToken, 0, v.lenDebtTokenUser);
                v.randLiquidator = clampBetween(seedLiquidator, 0, totalNbUsers);

                v.liquidator = users[v.randLiquidator];
                v.collAsset = v.userCollAssets[v.randColl];
                v.aTokenColl = v.userAToken[v.randColl];
                v.debtAsset = v.userDebtAssets[v.randDebtToken];
                v.vTokenDebt = v.userDebtToken[v.randDebtToken];

                v.targetATokenCollBalanceBefore = v.aTokenColl.balanceOf(address(v.target));
                v.targetVTokenDebtBalanceBefore = v.vTokenDebt.balanceOf(address(v.target));

                v.liquidatorCollAssetBefore = v.collAsset.balanceOf(address(v.liquidator));
                v.liquidatorATokenCollBefore = v.aTokenColl.balanceOf(address(v.liquidator));
                v.liquidatorDebtAssetBefore = v.debtAsset.balanceOf(address(v.liquidator));

                v.randAmt = clampBetween(seedAmt, 0, v.targetVTokenDebtBalanceBefore);

                (bool success,) = v.liquidator.proxy(
                    address(pool),
                    abi.encodeWithSelector(
                        pool.liquidationCall.selector,
                        address(v.collAsset),
                        true,
                        address(v.debtAsset),
                        true,
                        address(v.target),
                        v.randAmt,
                        randReceiveAToken
                    )
                );

                if (v.targetATokenCollBalanceBefore == 0) {
                    assertWithMsg(!success, "100");
                }

                if (v.targetVTokenDebtBalanceBefore == 0) {
                    assertWithMsg(!success, "101");
                }

                if (v.targetHealthFactorBefore >= 1e18) {
                    assertWithMsg(!success, "102");
                }

                require(success);

                v.targetVTokenDebtBalanceAfter = v.vTokenDebt.balanceOf(address(v.target));
                assertGt(v.targetVTokenDebtBalanceBefore, v.targetVTokenDebtBalanceAfter, "103");

                v.liquidatorCollAssetAfter = v.collAsset.balanceOf(address(v.liquidator));
                v.liquidatorATokenCollAfter = v.aTokenColl.balanceOf(address(v.liquidator));
                if (randReceiveAToken) {
                    assertGte(v.liquidatorATokenCollAfter, v.liquidatorATokenCollBefore, "104");
                } else {
                    assertGte(v.liquidatorCollAssetAfter, v.liquidatorCollAssetBefore, "104");
                }

                v.liquidatorDebtAssetAfter = v.debtAsset.balanceOf(address(v.liquidator));
                if (randReceiveAToken || address(v.collAsset) != address(v.debtAsset)) {
                    assertGt(v.liquidatorDebtAssetBefore, v.liquidatorDebtAssetAfter, "105");
                }
            }
        }
    }

    /// ------- Helpers -------

    function oraclePriceUpdate(uint8[] memory seedAmt) internal {
        for (uint256 i = 0; i < aggregators.length; i++) {
            uint256 latestAnswer = uint256(aggregators[i].latestAnswer());
            uint256 maxPriceChange = latestAnswer * volatility / BPS; // max VOLATILITY price change

            uint256 max = latestAnswer + maxPriceChange;
            uint256 min = latestAnswer < maxPriceChange ? 1 : latestAnswer - maxPriceChange;
            
            aggregators[i].setAssetPrice(clampBetweenProportional(seedAmt[i], min, max));
            emit LogUint256("=> ", latestAnswer);
        }
    }

    function MintableERC20ToAddress(MintableERC20[] memory _m)
        internal
        view
        returns (address[] memory ret)
    {
        ret = new address[](_m.length);
        for (uint256 i = 0; i < _m.length; i++) {
            ret[i] = address(_m[i]);
        }
    }

    function MockAggregatorToAddress(MockAggregator[] memory _m)
        internal
        view
        returns (address[] memory ret)
    {
        ret = new address[](_m.length);
        for (uint256 i = 0; i < _m.length; i++) {
            ret[i] = address(_m[i]);
        }
    }

    function hasATokens(User user) internal view returns (bool) {
        for (uint256 i = 0; i < aTokens.length; i++) {
            if (
                aTokens[i].balanceOf(address(user)) != 0
                    && UserConfiguration.isUsingAsCollateral(
                        pool.getUserConfiguration(address(user)), i
                    )
            ) {
                return true;
            }
        }
        return false;
    }

    function hasATokensPeriod(User user) internal view returns (bool) {
        for (uint256 i = 0; i < aTokens.length; i++) {
            if (aTokens[i].balanceOf(address(user)) != 0) {
                return true;
            }
        }
        return false;
    }

    function hasDebt(User user) internal view returns (bool) {
        for (uint256 i = 0; i < debtTokens.length; i++) {
            if (debtTokens[i].balanceOf(address(user)) != 0) {
                return true;
            }
        }
        return false;
    }

    function hasATokenTotal() internal view returns (bool) {
        for (uint256 i = 0; i < users.length; i++) {
            if (hasATokensPeriod(users[i])) {
                return true;
            }
        }
        return false;
    }

    function hasDebtTotal() internal view returns (bool) {
        for (uint256 i = 0; i < users.length; i++) {
            if (hasDebt(users[i])) {
                return true;
            }
        }
        return false;
    }

    function getAllATokens(User user)
        internal
        view
        returns (AToken[] memory userATokens, ERC20[] memory userCollAssets, uint256 lenATokenUser)
    {
        uint256 len = aTokens.length;
        userATokens = new AToken[](len);
        userCollAssets = new ERC20[](len);
        for (uint256 i = 0; i < len; i++) {
            if (
                aTokens[i].balanceOf(address(user)) != 0
                    && UserConfiguration.isUsingAsCollateral(
                        pool.getUserConfiguration(address(user)), i
                    )
            ) {
                userATokens[lenATokenUser] = aTokens[i];
                userCollAssets[lenATokenUser] = ERC20(address(assets[i]));
                lenATokenUser++;
            }
        }
    }

    function getAllDebtTokens(User user)
        internal
        view
        returns (
            VariableDebtToken[] memory userDebtTokens,
            ERC20[] memory userDebtAssets,
            uint256 lenDebtTokenUser
        )
    {
        uint256 len = debtTokens.length;
        userDebtTokens = new VariableDebtToken[](len);
        userDebtAssets = new ERC20[](len);
        for (uint256 i = 0; i < len; i++) {
            if (debtTokens[i].balanceOf(address(user)) != 0) {
                userDebtTokens[lenDebtTokenUser] = debtTokens[i];
                userDebtAssets[lenDebtTokenUser] = ERC20(address(assets[i]));
                lenDebtTokenUser++;
            }
        }
    }

    function turnOnRehypothecation(
        address _aToken,
        address _vaultAddr
    ) internal {
        poolConfigurator.setVault(_aToken, _vaultAddr);
        poolConfigurator.setFarmingPct(_aToken, DEFAULT_FARMING_PCT);
        poolConfigurator.setClaimingThreshold(_aToken, DEFAULT_CLAIMING_THRESHOLD);
        poolConfigurator.setFarmingPctDrift(_aToken, DEFAULT_FARMING_PCT_DRIFT);
        poolConfigurator.setProfitHandler(_aToken, profitHandler);
    }
}
