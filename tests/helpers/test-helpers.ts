import { utils, BigNumber } from "ethers"; 

export async function deployLendingPoolAddressesProvider(marketId) {
  const LendingPoolAddressesProvider = await hre.ethers.getContractFactory("LendingPoolAddressesProvider");
  const lendingPoolAddressesProvider = await LendingPoolAddressesProvider.deploy(marketId);    
  return lendingPoolAddressesProvider;
}

export async function deployLendingPool() {
  const ReserveLogic = await hre.ethers.getContractFactory("ReserveLogic");
  const reserveLogic = await ReserveLogic.deploy();

  const GenericLogic = await hre.ethers.getContractFactory("GenericLogic");
  const genericLogic = await GenericLogic.deploy();

  const ValidationLogic = await hre.ethers.getContractFactory("ValidationLogic" , {
    libraries: {
      GenericLogic: genericLogic.address
    }
  });
  const validationLogic = await ValidationLogic.deploy();

  const LendingPool = await hre.ethers.getContractFactory("LendingPool", {
    libraries: {
      ReserveLogic: reserveLogic.address,
      ValidationLogic: validationLogic.address
    }
  });
  const lendingPool = await LendingPool.deploy();    
  return lendingPool;
}

export async function deployLendingPoolConfigurator() {
  const LendingPoolConfigurator = await hre.ethers.getContractFactory("LendingPoolConfigurator");
  const lendingPoolConfigurator = await LendingPoolConfigurator.deploy();    
  return lendingPoolConfigurator;
}

export async function deployLendingPoolCollateralManager() {
  const LendingPoolCollateralManager = await hre.ethers.getContractFactory("LendingPoolCollateralManager");
  const lendingPoolCollateralManager = await LendingPoolCollateralManager.deploy();    
  return lendingPoolCollateralManager;
}

export async function deployLendingPoolAddressesProviderRegistry() {
  const LendingPoolAddressesProviderRegistry = await hre.ethers.getContractFactory("LendingPoolAddressesProviderRegistry");
  const lendingPoolAddressesProviderRegistry = await LendingPoolAddressesProviderRegistry.deploy();    
  return lendingPoolAddressesProviderRegistry;
}

export async function deployProtocol() {
  const marketId = "Granary Genesis Market";
  const providerId = "1";
  let owner;
  [owner] = await ethers.getSigners();
  const adminAddress = owner.address;

  const rates = [
    ethers.utils.parseUnits("0.039", 27), // usdc
    ethers.utils.parseUnits("0.03", 27), // wbtc
    ethers.utils.parseUnits("0.03", 27) // eth
  ];

  const volStrat = [
    ethers.utils.parseUnits("0.45", 27), // optimalUtilizationRate
    ethers.utils.parseUnits("0", 27), // baseVariableBorrowRate
    ethers.utils.parseUnits("0.07", 27), // variableRateSlope1
    ethers.utils.parseUnits("3", 27), // variableRateSlope2
    '0', // stableRateSlope1
    '0' // stableRateSlope2
  ];

  const sStrat = [
    ethers.utils.parseUnits("0.8", 27), // optimalUtilizationRate
    ethers.utils.parseUnits("0", 27), // baseVariableBorrowRate
    ethers.utils.parseUnits("0.04", 27), // variableRateSlope1
    ethers.utils.parseUnits("0.75", 27), // variableRateSlope2
    '0', // stableRateSlope1
    '0' // stableRateSlope2
  ];

  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
  const BASE_CURRENCY = ZERO_ADDRESS;
  const BASE_CURRENCY_UNIT = "100000000";
  const FALLBACK_ORACLE = ZERO_ADDRESS;

  const Usdc = await hre.ethers.getContractFactory("MintableERC20");
  const usdc = await Usdc.deploy("Test USDC", "USDC", 6);

  const Wbtc = await hre.ethers.getContractFactory("MintableERC20");
  const wbtc = await Wbtc.deploy("Test WBTC", "WBTC", 8);

  const Weth = await hre.ethers.getContractFactory("WETH9Mocked");
  const weth = await Weth.deploy();

  const tokens = [
    usdc.address,
    wbtc.address,
    weth.address
  ];

  const reserveTypes = [
    false,
    false,
    false
  ]

  const UsdcPriceFeed = await hre.ethers.getContractFactory("MockAggregator");
  const usdcPriceFeed = await UsdcPriceFeed.deploy("100000000", await usdc.decimals());

  const WbtcPriceFeed = await hre.ethers.getContractFactory("MockAggregator");
  const wbtcPriceFeed = await WbtcPriceFeed.deploy("1600000000000", await wbtc.decimals());

  const EthPriceFeed = await hre.ethers.getContractFactory("MockAggregator");
  const ethPriceFeed = await EthPriceFeed.deploy("120000000000", await weth.decimals());

  const aggregators = [
    usdcPriceFeed.address,
    wbtcPriceFeed.address,
    ethPriceFeed.address
  ];

  const Rewarder = await hre.ethers.getContractFactory("Rewarder");
  const rewarder = await Rewarder.deploy();

  const LendingPoolAddressesProviderRegistry = await hre.ethers.getContractFactory("LendingPoolAddressesProviderRegistry");
  const lendingPoolAddressesProviderRegistry = await LendingPoolAddressesProviderRegistry.deploy();

  const LendingPoolAddressesProvider = await hre.ethers.getContractFactory("LendingPoolAddressesProvider");
  const lendingPoolAddressesProvider = await LendingPoolAddressesProvider.deploy(marketId);
  
  await lendingPoolAddressesProviderRegistry.registerAddressesProvider(lendingPoolAddressesProvider.address, providerId)
  
  await lendingPoolAddressesProvider.setPoolAdmin(adminAddress);
  await lendingPoolAddressesProvider.setEmergencyAdmin(adminAddress);

  const ReserveLogic = await hre.ethers.getContractFactory("ReserveLogic");
  const reserveLogic = await ReserveLogic.deploy();

  const GenericLogic = await hre.ethers.getContractFactory("GenericLogic");
  const genericLogic = await GenericLogic.deploy();

  const ValidationLogic = await hre.ethers.getContractFactory("ValidationLogic" , {
    libraries: {
      GenericLogic: genericLogic.address
    }
  });
  const validationLogic = await ValidationLogic.deploy();

  const LendingPool = await hre.ethers.getContractFactory("LendingPool", {
    libraries: {
      ReserveLogic: reserveLogic.address,
      ValidationLogic: validationLogic.address
    }
  });
  const lendingPool = await LendingPool.deploy();

  await lendingPool.initialize(lendingPoolAddressesProvider.address);

  await lendingPoolAddressesProvider.setLendingPoolImpl(lendingPool.address);

  const lendingPoolProxyAddress = await lendingPoolAddressesProvider.getLendingPool();

  const LendingPoolProxy = await hre.ethers.getContractFactory("LendingPool", {
    libraries: {
      ReserveLogic: reserveLogic.address,
      ValidationLogic: validationLogic.address
    }
  });
  const lendingPoolProxy = await LendingPoolProxy.attach(lendingPoolProxyAddress);

  const Treasury = await hre.ethers.getContractFactory("Treasury");
  const treasury = await Treasury.deploy(lendingPoolAddressesProvider.address);

  const LendingPoolConfigurator = await hre.ethers.getContractFactory("LendingPoolConfigurator");
  const lendingPoolConfigurator = await LendingPoolConfigurator.deploy();

  await lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(lendingPoolConfigurator.address);

  const lendingPoolConfiguratorProxyAddress = await lendingPoolAddressesProvider.getLendingPoolConfigurator();

  const LendingPoolConfiguratorProxy = await hre.ethers.getContractFactory("LendingPoolConfigurator");
  const lendingPoolConfiguratorProxy = await LendingPoolConfiguratorProxy.attach(lendingPoolConfiguratorProxyAddress);

  await lendingPoolConfiguratorProxy.setPoolPause(true);

  const StableAndVariableTokensHelper = await hre.ethers.getContractFactory("StableAndVariableTokensHelper");
  const stableAndVariableTokensHelper = await StableAndVariableTokensHelper.deploy(lendingPoolProxyAddress, lendingPoolAddressesProvider.address);

  const ATokensAndRatesHelper = await hre.ethers.getContractFactory("ATokensAndRatesHelper");
  const aTokensAndRatesHelper = await ATokensAndRatesHelper.deploy(lendingPoolProxyAddress, lendingPoolAddressesProvider.address, lendingPoolConfiguratorProxyAddress);


  const AToken = await hre.ethers.getContractFactory("AToken");
  const aToken = await AToken.deploy();

  const VariableDebtToken = await hre.ethers.getContractFactory("VariableDebtToken");
  const variableDebtToken = await VariableDebtToken.deploy();

  const StableDebtToken = await hre.ethers.getContractFactory("StableDebtToken");
  const stableDebtToken = await StableDebtToken.deploy();

  const Oracle = await hre.ethers.getContractFactory("Oracle");
  const oracle = await Oracle.deploy(tokens, aggregators, FALLBACK_ORACLE,  BASE_CURRENCY, BASE_CURRENCY_UNIT);

  await lendingPoolAddressesProvider.setPriceOracle(oracle.address);

  const LendingRateOracle = await hre.ethers.getContractFactory("LendingRateOracle");
  const lendingRateOracle = await LendingRateOracle.deploy();

  await lendingPoolAddressesProvider.setLendingRateOracle(lendingRateOracle.address);

  await lendingRateOracle.transferOwnership(stableAndVariableTokensHelper.address);

  await stableAndVariableTokensHelper.setOracleBorrowRates(tokens, rates, lendingRateOracle.address);

  await stableAndVariableTokensHelper.setOracleOwnership(lendingRateOracle.address, adminAddress);

  const ProtocolDataProvider = await hre.ethers.getContractFactory("ProtocolDataProvider");
  const protocolDataProvider = await ProtocolDataProvider.deploy(lendingPoolAddressesProvider.address);

  const UiPoolDataProvider = await hre.ethers.getContractFactory("UiPoolDataProvider");
  const uiPoolDataProvider = await UiPoolDataProvider.deploy(rewarder.address, oracle.address);
  const UiPoolDataProviderV2 = await hre.ethers.getContractFactory("UiPoolDataProviderV2");
  const uiPoolDataProviderV2 = await UiPoolDataProviderV2.deploy(ethPriceFeed.address, ethPriceFeed.address);

  const WETHGateway = await hre.ethers.getContractFactory("WETHGateway");
  const wETHGateway = await WETHGateway.deploy(weth.address);

  const StableStrategy = await hre.ethers.getContractFactory("DefaultReserveInterestRateStrategy");
  const stableStrategy = await StableStrategy.deploy(lendingPoolAddressesProvider.address, sStrat[0], sStrat[1], sStrat[2], sStrat[3], sStrat[4], sStrat[5]);

  const VolatileStrategy = await hre.ethers.getContractFactory("DefaultReserveInterestRateStrategy");
  const volatileStrategy = await VolatileStrategy.deploy(lendingPoolAddressesProvider.address, volStrat[0], volStrat[1], volStrat[2], volStrat[3], volStrat[4], volStrat[5]);

  let initInputParams: {
    aTokenImpl: string;
    stableDebtTokenImpl: string;
    variableDebtTokenImpl: string;
    underlyingAssetDecimals: BigNumberish;
    interestRateStrategyAddress: string;
    underlyingAsset: string;
    reserveType: boolean;
    treasury: string;
    incentivesController: string;
    underlyingAssetName: string;
    aTokenName: string;
    aTokenSymbol: string;
    variableDebtTokenName: string;
    variableDebtTokenSymbol: string;
    stableDebtTokenName: string;
    stableDebtTokenSymbol: string;
    params: string;
  }[] = [];

  initInputParams.push({
    aTokenImpl: aToken.address,
    stableDebtTokenImpl: stableDebtToken.address,
    variableDebtTokenImpl: variableDebtToken.address,
    underlyingAssetDecimals: 6, 
    interestRateStrategyAddress: stableStrategy.address,
    underlyingAsset: tokens[0],
    reserveType: reserveTypes[0],
    treasury: treasury.address,
    incentivesController: rewarder.address,
    underlyingAssetName: "USDC",
    aTokenName: "Granary USDC",
    aTokenSymbol: "grainUSDC",
    variableDebtTokenName: "Granary variable debt bearing USDC",
    variableDebtTokenSymbol: "variableDebtUSDC",
    stableDebtTokenName: "Granary stable debt bearing USDC",
    stableDebtTokenSymbol: "stableDebtUSDC",
    params: '0x10'
  });


  initInputParams.push({
    aTokenImpl: aToken.address,
    stableDebtTokenImpl: stableDebtToken.address,
    variableDebtTokenImpl: variableDebtToken.address,
    underlyingAssetDecimals: 8, 
    interestRateStrategyAddress: volatileStrategy.address,
    underlyingAsset: tokens[1],
    reserveType: reserveTypes[1],
    treasury: treasury.address,
    incentivesController: rewarder.address,
    underlyingAssetName: "WBTC",
    aTokenName: "Granary WBTC",
    aTokenSymbol: "grainWBTC",
    variableDebtTokenName: "Granary variable debt bearing WBTC",
    variableDebtTokenSymbol: "variableDebtWBTC",
    stableDebtTokenName: "Granary stable debt bearing WBTC",
    stableDebtTokenSymbol: "stableDebtWBTC",
    params: '0x10'
  });

  initInputParams.push({
    aTokenImpl: aToken.address,
    stableDebtTokenImpl: stableDebtToken.address,
    variableDebtTokenImpl: variableDebtToken.address,
    underlyingAssetDecimals: 18, 
    interestRateStrategyAddress: volatileStrategy.address,
    underlyingAsset: tokens[2],
    reserveType: reserveTypes[2],
    treasury: treasury.address,
    incentivesController: rewarder.address,
    underlyingAssetName: "ETH",
    aTokenName: "Granary ETH",
    aTokenSymbol: "grainETH",
    variableDebtTokenName: "Granary variable debt bearing ETH",
    variableDebtTokenSymbol: "variableDebtETH",
    stableDebtTokenName: "Granary stable debt bearing ETH",
    stableDebtTokenSymbol: "stableDebtETH",
    params: '0x10'
  });

  await lendingPoolConfiguratorProxy.batchInitReserve(initInputParams);

  const inputConfigParams: {
    asset: string;
    baseLTV: BigNumberish;
    liquidationThreshold: BigNumberish;
    liquidationBonus: BigNumberish;
    reserveFactor: BigNumberish;
    stableBorrowingEnabled: boolean;
    borrowingEnabled: boolean;
  }[] = [];

  // USDC
  inputConfigParams.push({
    asset: tokens[0],
    baseLTV: 8000,
    liquidationThreshold: 8500,
    liquidationBonus: 10500,
    reserveFactor: 1500,
    stableBorrowingEnabled: false,
    borrowingEnabled: true,
  });

  // WBTC
  inputConfigParams.push({
    asset: tokens[1],
    baseLTV: 8000,
    liquidationThreshold: 8500,
    liquidationBonus: 10500,
    reserveFactor: 1500,
    stableBorrowingEnabled: false,
    borrowingEnabled: true,
  });

  // ETH
  inputConfigParams.push({ 
    asset: tokens[2],
    baseLTV: 8000,
    liquidationThreshold: 8500,
    liquidationBonus: 10500,
    reserveFactor: 1500,
    stableBorrowingEnabled: false,
    borrowingEnabled: true,
  });

  await lendingPoolAddressesProvider.setPoolAdmin(aTokensAndRatesHelper.address);

  await aTokensAndRatesHelper.configureReserves(inputConfigParams);

  await lendingPoolAddressesProvider.setPoolAdmin(adminAddress);

  const LendingPoolCollateralManager = await hre.ethers.getContractFactory("LendingPoolCollateralManager");
  const lendingPoolCollateralManager = await LendingPoolCollateralManager.deploy();

  await lendingPoolAddressesProvider.setLendingPoolCollateralManager(lendingPoolCollateralManager.address);

  await wETHGateway.authorizeLendingPool(lendingPoolProxyAddress);

  let usdcReserveTokens = await protocolDataProvider.getReserveTokensAddresses(usdc.address, false);
  let GrainUSDC = await hre.ethers.getContractFactory("AToken");
  let grainUSDC = await GrainUSDC.attach(usdcReserveTokens.aTokenAddress);
  let StableDebtUSDC = await hre.ethers.getContractFactory("StableDebtToken");
  let stableDebtUSDC = await StableDebtUSDC.attach(usdcReserveTokens.stableDebtTokenAddress);
  let VariableDebtUSDC = await hre.ethers.getContractFactory("VariableDebtToken");
  let variableDebtUSDC = await VariableDebtUSDC.attach(usdcReserveTokens.variableDebtTokenAddress);

  let wbtcReserveTokens = await protocolDataProvider.getReserveTokensAddresses(wbtc.address, false);
  let GrainWBTC = await hre.ethers.getContractFactory("AToken");
  let grainWBTC = await GrainWBTC.attach(wbtcReserveTokens.aTokenAddress);
  let StableDebtWBTC = await hre.ethers.getContractFactory("StableDebtToken");
  let stableDebtWBTC = await StableDebtWBTC.attach(wbtcReserveTokens.stableDebtTokenAddress);
  let VariableDebtWBTC = await hre.ethers.getContractFactory("VariableDebtToken");
  let variableDebtWBTC = await VariableDebtWBTC.attach(wbtcReserveTokens.variableDebtTokenAddress);

  let ethReserveTokens = await protocolDataProvider.getReserveTokensAddresses(weth.address, false);
  let GrainETH = await hre.ethers.getContractFactory("AToken");
  let grainETH = await GrainETH.attach(ethReserveTokens.aTokenAddress);
  let StableDebtETH = await hre.ethers.getContractFactory("StableDebtToken");
  let stableDebtETH = await StableDebtETH.attach(ethReserveTokens.stableDebtTokenAddress);
  let VariableDebtETH = await hre.ethers.getContractFactory("VariableDebtToken");
  let variableDebtETH = await VariableDebtETH.attach(ethReserveTokens.variableDebtTokenAddress);

  await lendingPoolConfiguratorProxy.setPoolPause(false);



  return { usdc, wbtc, weth, usdcPriceFeed, wbtcPriceFeed, ethPriceFeed, rewarder, lendingPoolAddressesProviderRegistry,
  lendingPoolAddressesProvider, lendingPool, lendingPoolProxy, treasury, lendingPoolConfigurator, lendingPoolConfiguratorProxy,
  aToken, variableDebtToken, stableDebtToken, oracle, lendingRateOracle, protocolDataProvider, wETHGateway,
  stableStrategy, volatileStrategy, lendingPoolCollateralManager, grainUSDC, stableDebtUSDC, variableDebtUSDC,
  grainWBTC, stableDebtWBTC, variableDebtWBTC, grainETH, stableDebtETH, variableDebtETH, uiPoolDataProvider, uiPoolDataProviderV2 };
}

export async function prepareMockTokens(token, account, amount) {
  const tx = await token.connect(account).mint(amount);
  const receipt = await tx.wait();
  return receipt;
}

export async function approve(contractAddress, token, account) {
  const MAX_ALLOWANCE = "115792089237316195423570985008687907853269984665640564039457584007913129639935";
  const tx = await token.connect(account).approve(contractAddress, MAX_ALLOWANCE);
  const receipt = await tx.wait();
  const gasPrice = tx.gasPrice;
  return { receipt, gasPrice };
}

export async function deposit(lendingPoolProxy, account, tokenAddress, reserveType, amount, onBehalfOf) {
  const tx = await lendingPoolProxy.connect(account).deposit(tokenAddress, reserveType, amount, onBehalfOf, "0");
  const receipt = await tx.wait();
  return receipt;
}

export async function withdraw(lendingPoolProxy, account, tokenAddress, reserveType, amount, to) {
  const tx = await lendingPoolProxy.connect(account).withdraw(tokenAddress, reserveType, amount, to);
  const receipt = await tx.wait();
  return receipt;
}

export async function borrow(lendingPoolProxy, account, tokenAddress, reserveType, amount, onBehalfOf) {
  const tx = await lendingPoolProxy.connect(account).borrow(tokenAddress, reserveType, amount, "2", "0", onBehalfOf);
  const receipt = await tx.wait();
  return receipt;
}

export async function repay(lendingPoolProxy, account, tokenAddress, reserveType, amount, onBehalfOf) {
  const tx = await lendingPoolProxy.connect(account).repay(tokenAddress, reserveType, amount, "2", onBehalfOf);
  const receipt = await tx.wait();
  return receipt;
}

export async function setUserUseReserveAsCollateral(lendingPoolProxy, account, tokenAddress, reserveType, useAsCollateral) {
  const tx = await lendingPoolProxy.connect(account).setUserUseReserveAsCollateral(tokenAddress, reserveType, useAsCollateral);
  const receipt = await tx.wait();
  return receipt;
}

export async function depositETH(wETHGateway, account, lendingPoolProxyAddress, reserveType, amount, onBehalfOf) {
  const tx = await wETHGateway.connect(account).depositETH(lendingPoolProxyAddress, reserveType, onBehalfOf, "0", { value: amount });
  const receipt = await tx.wait();
  const gasPrice = tx.gasPrice;
  return { receipt, gasPrice };
}

export async function withdrawETH(wETHGateway, account, lendingPoolProxyAddress, reserveType, amount, to) {
  const tx = await wETHGateway.connect(account).withdrawETH(lendingPoolProxyAddress, reserveType, amount, to);
  const receipt = await tx.wait();
  const gasPrice = tx.gasPrice;
  return { receipt, gasPrice };
}

export async function borrowETH(wETHGateway, account, lendingPoolProxyAddress, reserveType, amount) {
  const tx = await wETHGateway.connect(account).borrowETH(lendingPoolProxyAddress, reserveType, amount, "2", "0");
  const receipt = await tx.wait();
  const gasPrice = tx.gasPrice;
  return { receipt, gasPrice };
}

export async function repayETH(wETHGateway, account, lendingPoolProxyAddress, reserveType, amount, onBehalfOf) {
  const tx = await wETHGateway.connect(account).repayETH(lendingPoolProxyAddress, reserveType, amount, "2", onBehalfOf, { value: amount });
  const receipt = await tx.wait();
  const gasPrice = tx.gasPrice;
  return { receipt, gasPrice };
}

export async function approveDelegation(variableDebtToken, account, delegatee, amount) {
  const tx = await variableDebtToken.connect(account).approveDelegation(delegatee, amount);
  const receipt = await tx.wait();
  const gasPrice = tx.gasPrice;
  return { receipt, gasPrice };
}

export async function transfer(token, account, to, amount) {
  const tx = await token.connect(account).transfer(to, amount);
  const receipt = await tx.wait();
  return receipt;

}

export async function emergencyTokenTransfer(wETHGateway, account, tokenAddress, to, amount) {
  const tx = await wETHGateway.connect(account).emergencyTokenTransfer(tokenAddress, to, amount);
  const receipt = await tx.wait();
  return receipt;
}

export async function emergencyEtherTransfer(wETHGateway, account, to, amount) {
  const tx = await wETHGateway.connect(account).emergencyEtherTransfer(to, amount);
  const receipt = await tx.wait();
  const gasPrice = tx.gasPrice;
  return { receipt, gasPrice };
}

export async function deploySelfdestructTransfer() {
  const SelfdestructTransfer = await hre.ethers.getContractFactory("SelfdestructTransfer");
  const selfdestructTransfer = await SelfdestructTransfer.deploy();    
  return selfdestructTransfer;
}

export async function destroyAndTransfer(selfdestructTransfer, account, to, amount) {
  const tx = await selfdestructTransfer.connect(account).destroyAndTransfer(to, { value: amount });
  const receipt = await tx.wait();
  const gasPrice = tx.gasPrice;
  return { receipt, gasPrice };
}

export async function deployMockFlashLoanReceiver(lendingPoolAddressesProviderAddress) {
  const MockFlashLoanReceiver = await hre.ethers.getContractFactory("MockFlashLoanReceiver");
  const mockFlashLoanReceiver = await MockFlashLoanReceiver.deploy(lendingPoolAddressesProviderAddress);    
  return mockFlashLoanReceiver;
}

export async function deployMockAggregator(initialAnswer, decimals) {
  const PriceFeed = await hre.ethers.getContractFactory("MockAggregator");
  const priceFeed = await PriceFeed.deploy(initialAnswer, decimals);
  return priceFeed;
}

export async function setAssetSources(oracle, account, assets, sources) {
  const tx = await oracle.connect(account).setAssetSources(assets, sources);
  const receipt = await tx.wait();
  return receipt;
}

export async function prepareRehypothecation(lendingPoolConfiguratorProxy, tokens, grainTokens, ownerAddress) {
  const farmingPct = "2000";     // 20%
  const farmingPctDrift = "100"; // 1%
  const usdcMockErc4626 = await deployMockErc4626(tokens[0]);
  const wbtcMockErc4626 = await deployMockErc4626(tokens[1]);
  const wethMockErc4626 = await deployMockErc4626(tokens[2]);
  //setVault(address aTokenAddress, address _vault)
  await lendingPoolConfiguratorProxy.setVault(grainTokens[0].address, usdcMockErc4626.address);
  await lendingPoolConfiguratorProxy.setVault(grainTokens[1].address, wbtcMockErc4626.address);
  await lendingPoolConfiguratorProxy.setVault(grainTokens[2].address, wethMockErc4626.address);
  // setFarmingPct(address aTokenAddress, uint256 farmingPct)
  await lendingPoolConfiguratorProxy.setFarmingPct(grainTokens[0].address, farmingPct);
  await lendingPoolConfiguratorProxy.setFarmingPct(grainTokens[1].address, farmingPct);
  await lendingPoolConfiguratorProxy.setFarmingPct(grainTokens[2].address, farmingPct);
  // setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold)
  await lendingPoolConfiguratorProxy.setClaimingThreshold(grainTokens[0].address, ethers.utils.parseUnits("1", 6));      // ~$1
  await lendingPoolConfiguratorProxy.setClaimingThreshold(grainTokens[1].address, ethers.utils.parseUnits("0.0001", 8)); // ~$1
  await lendingPoolConfiguratorProxy.setClaimingThreshold(grainTokens[2].address, ethers.utils.parseUnits("0.001", 18)); // ~$1
  // setFarmingPctDrift(address aTokenAddress, uint256 _farmingPctDrift)
  await lendingPoolConfiguratorProxy.setFarmingPctDrift(grainTokens[0].address, farmingPctDrift);
  await lendingPoolConfiguratorProxy.setFarmingPctDrift(grainTokens[1].address, farmingPctDrift);
  await lendingPoolConfiguratorProxy.setFarmingPctDrift(grainTokens[2].address, farmingPctDrift);
  // setProfitHandler(address aTokenAddress, address _profitHandler)
  await lendingPoolConfiguratorProxy.setProfitHandler(grainTokens[0].address, ownerAddress);
  await lendingPoolConfiguratorProxy.setProfitHandler(grainTokens[1].address, ownerAddress);
  await lendingPoolConfiguratorProxy.setProfitHandler(grainTokens[2].address, ownerAddress);
}
export async function deployMockErc4626(token) {
  const MockErc4626 = await hre.ethers.getContractFactory("MockERC4626");
  const mockErc4626 = await MockErc4626.deploy(token.address, "Mock ERC4626", "mock", await token.decimals());
  return mockErc4626;
}
export async function rayDiv(a, b) {
  const RAY = (BigNumber.from(10)).pow(27);
  const halfB = b.div(2);
  const quotient = halfB
    .add(a.mul(RAY))
    .div(b)
  return quotient;
}
export async function rayMul(a, b) {
  const RAY = (BigNumber.from(10)).pow(27);
  const HALF_RAY = ((BigNumber.from(10)).pow(27)).div(2);
  const product = ((a.mul(b)).add(HALF_RAY)).div(RAY);
  return product;
}
export async function percentMul(value, percentage) {
  return (value.mul(percentage).add("5000")).div("10000");
}
// ONLY USE IF UTILIZATION RATE IS BELOW OPTIMAL UTILIZATION RATE (WILL ADD OVER OUR SOON)
export async function getExpectedVariableRate(protocolDataProvider, underlying, grainToken, reserveStrategy) {
  const reserveData = await protocolDataProvider.getReserveData(underlying.address);
  const reserveConfigurationData = await protocolDataProvider.getReserveConfigurationData(underlying.address);
  // console.log("Farming Balance:    "+await grainToken.farmingBal());
  // console.log("Underlying Balance: "+await underlying.balanceOf(grainToken.address));
  const availableLiquidity = (await underlying.balanceOf(grainToken.address)).add(await grainToken.farmingBal());
  const utilizationRate = await rayDiv(reserveData.totalVariableDebt, (availableLiquidity).add(reserveData.totalVariableDebt))
  const optimalUtilizationRate = await reserveStrategy.OPTIMAL_UTILIZATION_RATE();
  const expectedVariableRate = await rayDiv((await rayMul(utilizationRate, await reserveStrategy.variableRateSlope1())), optimalUtilizationRate)
  return expectedVariableRate;
}
export async function getCurrentVariableRate(protocolDataProvider, underlying, grainToken, reserveStrategy) {
  const reserveData = await protocolDataProvider.getReserveData(underlying.address);
  const reserveConfigurationData = await protocolDataProvider.getReserveConfigurationData(underlying.address);
  const {
    0: currentLiquidityRate,
    1: currentStableBorrowRate,
    2: currentVariableBorrowRate,
  } = await reserveStrategy['calculateInterestRates(address,address,uint256,uint256,uint256,uint256,uint256,uint256)'](
    underlying.address, // address reserve
    grainToken.address, // address aToken
    "0", // uint256 liquidityAdded
    "0", // uint256 liquidityTaken
    "0", // uint256 totalStableDebt
    reserveData.totalVariableDebt, // uint256 totalVariableDebt
    "0", // uint256 averageStableBorrowRate
    reserveConfigurationData.reserveFactor // uint256 reserveFactor
  );
  return currentVariableBorrowRate;
}

export async function calcExpectedVariableDebtTokenBalance(
  reserveData,
  userData,
  currentTimestamp
) {
  const normalizedDebt = await calcExpectedReserveNormalizedDebt(
    reserveData.variableBorrowRate,
    reserveData.variableBorrowIndex,
    reserveData.lastUpdateTimestamp,
    currentTimestamp
  );

  const { scaledVariableDebt } = userData;

  return (await rayMul(scaledVariableDebt, normalizedDebt));
};

export async function calcExpectedReserveNormalizedDebt(
  variableBorrowRate,
  variableBorrowIndex,
  lastUpdateTimestamp,
  currentTimestamp
) {
  //if utilization rate is 0, nothing to compound
  if (variableBorrowRate.eq('0')) {
    return variableBorrowIndex;
  }

  const cumulatedInterest = await calcCompoundedInterest(
    variableBorrowRate,
    currentTimestamp,
    lastUpdateTimestamp
  );

  const debt = (await rayMul(cumulatedInterest, variableBorrowIndex));

  return debt;
};

export async function calcCompoundedInterest(
  rate,
  currentTimestamp,
  lastUpdateTimestamp
) {
  const RAY = (BigNumber.from(10)).pow(27);
  const ONE_YEAR = BigNumber.from("31536000");
  const timeDifference = BigNumber.from(currentTimestamp).sub(lastUpdateTimestamp);

  if (timeDifference.eq(0)) {
    return RAY;
  }

  const expMinusOne = timeDifference.sub(1);
  const expMinusTwo = timeDifference.gt(2) ? timeDifference.sub(2) : 0;

  const ratePerSecond = rate.div(ONE_YEAR);

  const basePowerTwo = await rayMul(ratePerSecond, ratePerSecond);
  const basePowerThree = await rayMul(basePowerTwo, ratePerSecond);

  const secondTerm = timeDifference.mul(expMinusOne).mul(basePowerTwo).div(2);
  const thirdTerm = timeDifference
    .mul(expMinusOne)
    .mul(expMinusTwo)
    .mul(basePowerThree)
    .div(6);

  return RAY
    .add(ratePerSecond.mul(timeDifference))
    .add(secondTerm)
    .add(thirdTerm);
};