// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./mock/MockLendingPool.sol";
import "./util/User.sol";
import "./util/PropertiesHelper.sol";
import "./MarketParams.sol";

import "./mock/tokens/MintableERC20.sol";
import "./mock/oracle/MockAggregator.sol";

import "contracts/protocol/libraries/types/DataTypes.sol";
import "contracts/protocol/libraries/configuration/UserConfiguration.sol";

import "contracts/interfaces/IAToken.sol";
import "contracts/interfaces/IChainlinkAggregator.sol";
import "contracts/interfaces/ICreditDelegationToken.sol";
import "contracts/interfaces/IDelegationToken.sol";
import "contracts/interfaces/IERC20WithPermit.sol";
import "contracts/interfaces/IERC4626.sol";
import "contracts/interfaces/IInitializableAToken.sol";
import "contracts/interfaces/IInitializableDebtToken.sol";
import "contracts/interfaces/ILendingPool.sol";
import "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import "contracts/interfaces/ILendingPoolAddressesProviderRegistry.sol";
import "contracts/interfaces/ILendingPoolCollateralManager.sol";
import "contracts/interfaces/ILendingPoolConfigurator.sol";
import "contracts/interfaces/IReserveInterestRateStrategy.sol";
import "contracts/interfaces/IRewarder.sol";
import "contracts/interfaces/IScaledBalanceToken.sol";
import "contracts/interfaces/IVariableDebtToken.sol";
import "contracts/interfaces/IPriceOracleGetter.sol";

import "contracts/misc/Treasury.sol";
import "contracts/misc/Oracle.sol";
import "contracts/misc/ProtocolDataProvider.sol";
import "contracts/misc/UiPoolDataProviderV2.sol";
import "contracts/misc/ChainlinkSourcesRegistry.sol";
import "contracts/misc/RewardsVault.sol";
import "contracts/misc/Timelock.sol";
import "contracts/misc/WalletBalanceProvider.sol";
import "contracts/misc/WETHGateway.sol";

import "contracts/deployments/ATokensAndRatesHelper.sol";

import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProviderRegistry.sol";

import "contracts/protocol/lendingpool/LendingPoolCollateralManager.sol";
import "contracts/protocol/lendingpool/DefaultReserveInterestRateStrategy.sol";
import "contracts/protocol/lendingpool/LendingPoolConfigurator.sol";
import "contracts/protocol/lendingpool/LendingPoolStorage.sol";

import "contracts/protocol/tokenization/AToken.sol";
import "contracts/protocol/tokenization/DelegationAwareAToken.sol";
import "contracts/protocol/tokenization/VariableDebtToken.sol";

import "contracts/protocol/libraries/logic/BorrowLogic.sol";
import "contracts/protocol/libraries/logic/GenericLogic.sol";
import "contracts/protocol/libraries/logic/ReserveLogic.sol";
import "contracts/protocol/libraries/logic/ValidationLogic.sol";

// Users are defined in users
// Admin is address(this)
contract PropertiesBase is PropertiesAsserts, MarketParams {
    // config -----------
    uint internal totalNbUsers = 4;
    uint internal totalNbTokens = 4;
    uint internal initialMint = 100 ether;
    bool internal bootstrapLiquidity = true;
    uint internal volatility = 500; // 5%
    // ------------------

    User internal bootstraper;
    User[] internal users;
    DefaultReserveInterestRateStrategy/*[]*/ internal rateStrategies;

    mapping(address => uint) internal lastLiquidityIndex;
    mapping(address => uint) internal lastVariableBorrowIndex;

    // A given assets[i] is accosiated with the liquidity token aTokens[i]
    // and the debt token debtTokens[i].
    MintableERC20[] internal assets; // assets[0] is weth
    MockAggregator[] internal aggregators; // aggregators[0] is the reference (eth pricefeed)
    AToken[] internal aTokens;
    VariableDebtToken[] internal debtTokens;

    // AAVE contracts
    IRewarder internal rewarder;
    LendingPoolAddressesProviderRegistry internal registry;
    LendingPoolAddressesProvider internal provider;
    MockLendingPool internal pool;
    Treasury internal treasury;
    LendingPoolConfigurator internal poolConfigurator;
    ATokensAndRatesHelper internal aHelper;
    AToken internal aToken;
    VariableDebtToken internal vToken;
    Oracle internal oracle;
    ProtocolDataProvider internal protocolDataProvider;
    UiPoolDataProviderV2 internal uiPoolDataProviderV2;
    WETHGateway internal wethGateway;
    LendingPoolCollateralManager internal poolCollManager;

    constructor() {
        /// mocks
        uint8 tokenDec = 18;
        for (uint i = 0; i < totalNbTokens; i++) {
            uint8 tokenDecTemp = (i % 2 == 0) ? uint8(tokenDec - i) : uint8(tokenDec + i); // various dec [18, 19, 17, 20, 16, 21, 15, 22, 14 ...]
            MintableERC20 t = new MintableERC20("", "", tokenDecTemp);
            assets.push(t);
            MockAggregator a = new MockAggregator(
                1e18,
                int256(uint256(tokenDecTemp))
            );
            aggregators.push(a);
        }

        /// setup AAVE
        rewarder = IRewarder(address(0));
        registry = new LendingPoolAddressesProviderRegistry();
        provider = new LendingPoolAddressesProvider(MARKET_ID);
        registry.registerAddressesProvider(address(provider), PROVIDER_ID);
        provider.setPoolAdmin(address(this));
        provider.setEmergencyAdmin(address(this));
        treasury = new Treasury(provider);

        pool = new MockLendingPool();
        pool.initialize(provider);
        provider.setLendingPoolImpl(address(pool));
        pool = MockLendingPool(provider.getLendingPool());

        poolConfigurator = new LendingPoolConfigurator();
        provider.setLendingPoolConfiguratorImpl(address(poolConfigurator));
        poolConfigurator = LendingPoolConfigurator(provider.getLendingPoolConfigurator());
        poolConfigurator.setPoolPause(true);

        aHelper = new ATokensAndRatesHelper(
            payable(address(pool)),
            address(provider),
            address(poolConfigurator)
        );
        aToken = new AToken();
        vToken = new VariableDebtToken();
        oracle = new Oracle(
            MintableERC20ToAddress(assets),
            MockAggregatorToAddress(aggregators),
            FALLBACK_ORACLE,
            BASE_CURRENCY,
            BASE_CURRENCY_UNIT
        );
        provider.setPriceOracle(address(oracle));
        protocolDataProvider = new ProtocolDataProvider(provider);
        uiPoolDataProviderV2 = new UiPoolDataProviderV2(
            IChainlinkAggregator(address(aggregators[0])),
            IChainlinkAggregator(address(aggregators[0]))
        );
        wethGateway = new WETHGateway(address(assets[0]));
        rateStrategies = new DefaultReserveInterestRateStrategy(
                                provider, 
                                DEFAULT_OPTI_UTILIZATION_RATE, 
                                DEFAULT_BASE_VARIABLE_BORROW_RATE, 
                                DEFAULT_VARIABLE_RATE_SLOPE1, 
                                DEFAULT_VARIABLE_RATE_SLOPE2
                        ); // todoto random strats

        ILendingPoolConfigurator.InitReserveInput memory ri;
        ILendingPoolConfigurator.InitReserveInput[] memory initInputParams 
            = new ILendingPoolConfigurator.InitReserveInput[](totalNbTokens);
        for (uint256 i = 0; i < totalNbTokens; i++) {
                ri = ILendingPoolConfigurator.InitReserveInput({
                    aTokenImpl: address(aToken),
                    variableDebtTokenImpl: address(vToken),
                    underlyingAssetDecimals: assets[i].decimals(),
                    interestRateStrategyAddress: address(rateStrategies),
                    underlyingAsset: address(assets[i]),
                    treasury: address(treasury),
                    incentivesController: address(rewarder),
                    underlyingAssetName: "",
                    reserveType: false,
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
        ATokensAndRatesHelper.ConfigureReserveInput[] memory configureReserveInput 
            = new ATokensAndRatesHelper.ConfigureReserveInput[](totalNbTokens);
        for (uint256 i = 0; i < totalNbTokens; i++) {
            cri = ATokensAndRatesHelper.ConfigureReserveInput({
                    asset: address(assets[i]),
                    reserveType: false,
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
        
        poolCollManager = new LendingPoolCollateralManager();
        provider.setLendingPoolCollateralManager(address(poolCollManager));
        wethGateway.authorizeLendingPool(address(pool));

        for (uint256 i = 0; i < totalNbTokens; i++) {
            (address aTokenAddress, address variableDebtTokenAddress)
                = protocolDataProvider.getReserveTokensAddresses(address(assets[i]), false);
            aTokens.push(AToken(aTokenAddress));
            debtTokens.push(VariableDebtToken(variableDebtTokenAddress));
        }
        
        poolConfigurator.setPoolPause(false);

        /// bootstrap liquidity
        if (bootstrapLiquidity) {
            bootstraper = new User(provider);
            for (uint j = 0; j < totalNbTokens; j++) {
                assets[j].mint(address(bootstraper), initialMint);
                bootstraper.approveERC20(assets[j], address(pool));
                (bool success, ) = bootstraper.proxy(
                    address(pool),
                    abi.encodeWithSelector(
                        pool.deposit.selector,
                        address(assets[j]),
                        false,
                        initialMint,
                        address(bootstraper)
                    )
                );
                assert(success);
            }
        }

        /// update liquidity index
        for (uint i = 0; i < assets.length; i++) {
            address asset = address(assets[i]);

            lastLiquidityIndex[asset] = pool.getReserveData(asset, false).liquidityIndex;
            lastVariableBorrowIndex[asset] = pool.getReserveData(asset, false).variableBorrowIndex;
        }

        /// setup users
        for (uint i = 0; i < totalNbUsers; i++) {
            User user = new User(provider);
            users.push(user);
            for (uint j = 0; j < totalNbTokens; j++) {
                assets[j].mint(address(user), initialMint);
                user.approveERC20(assets[j], address(pool));
            }
        }

        /// mint to address(this) for randForceFeed
        for (uint j = 0; j < totalNbTokens; j++) {
            assets[j].mint(address(this), type(uint160).max);
        }
    }

    /// ------- global state updates -------

    struct LocalVars_UPTL {
        uint[] seedAmtPrice;
        uint seedLiquidator; 
        uint seedColl;
        uint seedDebtToken; 
        uint seedAmtLiq;
        bool randReceiveAToken;
    }
    
    function randUpdatePriceAndTryLiquidate(LocalVars_UPTL memory v) public {
        oraclePriceUpdate(v.seedAmtPrice);
        tryLiquidate(v.seedLiquidator, v.seedColl, v.seedDebtToken, v.seedAmtLiq, v.randReceiveAToken);
    }
     struct LocalVars_TryLiquidate {
        uint randLiquidator;
        uint randTargetUser;
        uint randColl;
        uint randDebtToken;
        uint randAmt;

        User liquidator;
        User target;

        ERC20 collAsset;
        AToken aTokenColl;
        ERC20 debtAsset;
        VariableDebtToken vTokenDebt;

        uint targetATokenCollBalanceBefore;
        uint targetATokenCollBalanceAfter;
        uint targetVTokenDebtBalanceBefore;
        uint targetVTokenDebtBalanceAfter;
        uint targetHealthFactorBefore;
        uint targetHealthFactorAfter;

        uint liquidatorDebtAssetBefore;
        uint liquidatorDebtAssetAfter;
        uint liquidatorCollAssetBefore;
        uint liquidatorCollAssetAfter;
        uint liquidatorATokenCollBefore;
        uint liquidatorATokenCollAfter;

        AToken[] userAToken;
        ERC20[] userCollAssets;
        VariableDebtToken[] userDebtToken;
        ERC20[] userDebtAssets;

        uint lenATokenUser;
        uint lenDebtTokenUser;
    }

    /// @custom:invariant 100 - To be liquidated on a given collateral asset, the target user must own the associated `aTokenColl`.
    /// @custom:invariant 101 - To be liquidated on a given token, the target user must own the associated `vTokenDebt`.
    /// @custom:invariant 102 - `liquidationCall()` must only be callable when the target health factor is < 1.
    /// @custom:invariant 103 - `liquidationCall()` must decrease the target `vTokenDebt` balance by `amount`.
    /// @custom:invariant 104 - `liquidationCall()` must increase the liquidator `aTokenColl` (or `collAsset`) balance.
    /// @custom:invariant 105 - `liquidationCall()` must decrease the liquidator debt asset balance if `randReceiveAToken == true` or `collAsset != debtAsset`.
    function tryLiquidate(uint seedLiquidator, uint seedColl, uint seedDebtToken, uint seedAmt, bool randReceiveAToken) internal {
        for (uint256 i = 0; i < users.length; i++) {
            LocalVars_TryLiquidate memory v;

            v.target  = users[i];
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

                (bool success, ) = v.liquidator.proxy(
                    address(pool),
                    abi.encodeWithSelector(
                        pool.liquidationCall.selector,
                        address(v.collAsset),
                        false,
                        address(v.debtAsset),
                        false,
                        address(v.target),
                        v.randAmt,
                        randReceiveAToken
                    )
                );

                if (v.targetATokenCollBalanceBefore == 0) 
                    assertWithMsg(!success, "100");        
                
                if (v.targetVTokenDebtBalanceBefore == 0) 
                    assertWithMsg(!success, "101");      
                
                if (v.targetHealthFactorBefore >= 1e18) 
                    assertWithMsg(!success, "102");
                
                require(success);
                
                v.targetVTokenDebtBalanceAfter = v.vTokenDebt.balanceOf(address(v.target));
                assertGt(v.targetVTokenDebtBalanceBefore, v.targetVTokenDebtBalanceAfter, "103");

                v.liquidatorCollAssetAfter = v.collAsset.balanceOf(address(v.liquidator));
                v.liquidatorATokenCollAfter = v.aTokenColl.balanceOf(address(v.liquidator));
                if (randReceiveAToken) assertGte(v.liquidatorATokenCollAfter, v.liquidatorATokenCollBefore, "104");
                else                   assertGte(v.liquidatorCollAssetAfter, v.liquidatorCollAssetBefore, "104");
                
                v.liquidatorDebtAssetAfter = v.debtAsset.balanceOf(address(v.liquidator));
                if (randReceiveAToken || address(v.collAsset) != address(v.debtAsset)) 
                    assertGt(v.liquidatorDebtAssetBefore, v.liquidatorDebtAssetAfter, "105");
            }
        }
    }

    /// ------- Helpers -------

    function oraclePriceUpdate(uint[] memory seedAmt) internal {
        for (uint256 i = 0; i < aggregators.length; i++) {
            uint latestAnswer = uint256(aggregators[i].latestAnswer());
            uint maxPriceChange = latestAnswer * volatility / BPS; // max VOLATILITY price change

            uint max = latestAnswer + maxPriceChange;
            uint min = latestAnswer < maxPriceChange ? 1 : latestAnswer - maxPriceChange;

            aggregators[i].setAssetPrice(clampBetween(seedAmt[i], min, max)); 
            emit LogUint256("=> ", latestAnswer);
        }
    }

    function MintableERC20ToAddress(
        MintableERC20[] memory _m
    ) internal view returns (address[] memory ret) {
        ret = new address[](_m.length);
        for (uint i = 0; i < _m.length; i++) {
            ret[i] = address(_m[i]);
        }
    }

    function MockAggregatorToAddress(
        MockAggregator[] memory _m
    ) internal view returns (address[] memory ret) {
        ret = new address[](_m.length);
        for (uint i = 0; i < _m.length; i++) {
            ret[i] = address(_m[i]);
        }
    }

    function hasATokens(User user) internal view returns(bool) {
        for (uint256 i = 0; i < aTokens.length; i++) {
            if(aTokens[i].balanceOf(address(user)) != 0 
                && UserConfiguration.isUsingAsCollateral(pool.getUserConfiguration(address(user)), i)) 
                return true;   
        }
        return false;
    }

    function hasATokensPeriod(User user) internal view returns(bool) {
        for (uint256 i = 0; i < aTokens.length; i++) {
            if(aTokens[i].balanceOf(address(user)) != 0) 
                return true;   
        }
        return false;
    }

    function hasDebt(User user) internal view returns(bool) {
        for (uint256 i = 0; i < debtTokens.length; i++) {
            if(debtTokens[i].balanceOf(address(user)) != 0) 
                return true;   
        }
        return false;
    }

    function hasATokenTotal() internal view returns(bool) {
        for (uint256 i = 0; i < users.length; i++) {
            if(hasATokensPeriod(users[i])) 
                return true;   
        }
        return false;
    }

    function hasDebtTotal() internal view returns(bool) {
        for (uint256 i = 0; i < users.length; i++) {
            if(hasDebt(users[i])) 
                return true;   
        }
        return false;
    }

    function getAllATokens(User user) internal view returns(AToken[] memory userATokens, ERC20[] memory userCollAssets, uint lenATokenUser) {
        uint len = aTokens.length;
        userATokens = new AToken[](len);
        userCollAssets = new ERC20[](len);
        for (uint256 i = 0; i < len; i++) {
            if(aTokens[i].balanceOf(address(user)) != 0 
                && UserConfiguration.isUsingAsCollateral(pool.getUserConfiguration(address(user)), i)) {
                userATokens[lenATokenUser] = aTokens[i];
                userCollAssets[lenATokenUser] = assets[i];
                lenATokenUser++;
            }
        }
    }

    function getAllDebtTokens(User user) internal view returns(VariableDebtToken[] memory userDebtTokens, ERC20[] memory userDebtAssets, uint lenDebtTokenUser) {
        uint len = debtTokens.length;
        userDebtTokens = new VariableDebtToken[](len);
        userDebtAssets = new ERC20[](len);
        for (uint256 i = 0; i < len; i++) {
            if(debtTokens[i].balanceOf(address(user)) != 0) {
                userDebtTokens[lenDebtTokenUser] = debtTokens[i];
                userDebtAssets[lenDebtTokenUser] = assets[i];
                lenDebtTokenUser++;
            }
        }
    }

    
}
