import { expect } from "chai";
import hre from "hardhat";
import { Wallet, utils, BigNumber } from "ethers"; 
import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import {
  deployProtocol,
  prepareMockTokens,
  approve,
  deposit,
  borrow,
  prepareRehypothecation,
  rayDiv,
  percentMul,
  rayMul,
  getCurrentVariableRate,
  getExpectedVariableRate,
  deployMockAggregator,
  calcExpectedVariableDebtTokenBalance,
  setAssetSources,
  deployMockErc4626,
  withdraw,
} from "./helpers/test-helpers";

describe("Rehypothecation", function () {
  let owner, addr1, addr2, addr3;

  // ## AToken ##
  describe("AToken", function () {
    // check onlyLendingPool Modifier
    describe("Checks onlyLendingPool Modifier", function () {
      before(async function () {
        [owner, addr1] = await ethers.getSigners();
      });

      it("Tries to call mint not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.mint(owner.address, '1', '1')).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call burn not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.burn(owner.address, owner.address, '1', '1')).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call mintToTreasury not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.mintToTreasury('1', '1')).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call transferOnLiquidation not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.transferOnLiquidation(owner.address, addr1.address, '1')).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call transferUnderlyingTo not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.transferUnderlyingTo(owner.address, '1')).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call handleRepayment not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.handleRepayment(owner.address, '1')).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call setFarmingPct not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.setFarmingPct('2000')).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call setClaimingThreshold not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.setClaimingThreshold('1')).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call setFarmingPctDrift not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.setFarmingPctDrift('15')).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call setProfitHandler not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.setProfitHandler(owner.address)).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call setVault not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        const mockVault = Wallet.createRandom().address;
        await expect(grainUSDC.setVault(mockVault)).to.be.revertedWith(
          "29"
        );
      });

      it("Tries to call rebalance not being lendingPool", async function () {
        const { grainUSDC } = await loadFixture(deployProtocol);
        await expect(grainUSDC.rebalance()).to.be.revertedWith(
          "29"
        );
      });
    });

    // getTotalManagedAssets()
    it("getTotalManagedAssets", async function () {
      [owner, addr1] = await ethers.getSigners();
      const {
        lendingPoolProxy, lendingPoolConfiguratorProxy,
        usdc, wbtc, weth, grainUSDC, grainWBTC, grainETH
      } = await loadFixture(deployProtocol);
      const tokens = [usdc, wbtc, weth];
      const grainTokens = [grainUSDC, grainWBTC, grainETH];
      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("100", 6);

      await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
      await approve(lendingPoolProxy.address, usdc, addr1);
      await deposit(lendingPoolProxy, addr1, usdc.address, USDC_DEPOSIT_SIZE, addr1.address);
      
      await prepareRehypothecation(lendingPoolConfiguratorProxy, tokens, grainTokens, owner.address);

      // expects underlying in AToken contract to be equal to the initial deposit
      expect(await usdc.balanceOf(grainUSDC.address)).to.equal(USDC_DEPOSIT_SIZE);

      await lendingPoolConfiguratorProxy.rebalance(grainUSDC.address);

      // expects remaining underlying in AToken contract to be (initial deposit - farmedBalance)
      const remainingPct = BigNumber.from("10000").sub(await grainUSDC.farmingPct());
      expect(await usdc.balanceOf(grainUSDC.address)).to.equal(USDC_DEPOSIT_SIZE.mul(remainingPct).div(10000));

      // expects totalManagedAssets to account for the full initial deposit
      expect(await grainUSDC.getTotalManagedAssets()).to.equal(USDC_DEPOSIT_SIZE);
    });
  });

  // ## AaveProtocolDataProvider ##
  describe("AaveProtocolDataProvider", function () {
    // getReserveData(address asset)
    it("getReserveData", async function () {
      [owner, addr1] = await ethers.getSigners();
      const {
        aaveProtocolDataProvider, lendingPoolProxy, lendingPoolConfiguratorProxy,
        usdc, wbtc, weth, grainUSDC, grainWBTC, grainETH
      } = await loadFixture(deployProtocol);
      const tokens = [usdc, wbtc, weth];
      const grainTokens = [grainUSDC, grainWBTC, grainETH];
      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("100", 6);

      await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
      await approve(lendingPoolProxy.address, usdc, addr1);
      await deposit(lendingPoolProxy, addr1, usdc.address, USDC_DEPOSIT_SIZE, addr1.address);
      await prepareRehypothecation(lendingPoolConfiguratorProxy, tokens, grainTokens, owner.address);

      await lendingPoolConfiguratorProxy.rebalance(grainUSDC.address);

      let availableLiquidity = (await aaveProtocolDataProvider.getReserveData(usdc.address)).availableLiquidity;

      expect(availableLiquidity).to.equal(USDC_DEPOSIT_SIZE);
    });
  });

  // ## UiPoolDataProviderV2 ##
  describe("UiPoolDataProviderV2", function () {
    // getReservesData(ILendingPoolAddressesProvider provider)
    it("getReservesData", async function () {
      [owner, addr1] = await ethers.getSigners();
      const {
        uiPoolDataProviderV2, lendingPoolProxy, lendingPoolConfiguratorProxy,
        usdc, wbtc, weth, grainUSDC, grainWBTC, grainETH, lendingPoolAddressesProvider
      } = await loadFixture(deployProtocol);
      const tokens = [usdc, wbtc, weth];
      const grainTokens = [grainUSDC, grainWBTC, grainETH];
      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("100", 6);

      await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
      await approve(lendingPoolProxy.address, usdc, addr1);
      await deposit(lendingPoolProxy, addr1, usdc.address, USDC_DEPOSIT_SIZE, addr1.address);
      await prepareRehypothecation(lendingPoolConfiguratorProxy, tokens, grainTokens, owner.address);

      await lendingPoolConfiguratorProxy.rebalance(grainUSDC.address);

      let availableLiquidity = (await uiPoolDataProviderV2.getReservesData(lendingPoolAddressesProvider.address))[0][0].availableLiquidity;
      expect(availableLiquidity).to.equal(USDC_DEPOSIT_SIZE);
    });
  });

  // ## DefaultReserveInterestRateStrategy ##
  describe("DefaultReserveInterestRateStrategy", function () {
    // NOTE: getTotalManagedAssets impacts Utilization Rate, this test is ran under Optimal Utilization Ratio
    it("calculateInterestRates", async function () {
      [owner, addr1] = await ethers.getSigners();
      const {
        aaveProtocolDataProvider, lendingPoolProxy, lendingPoolConfiguratorProxy, stableStrategy, volatileStrategy,
        usdc, wbtc, weth, grainUSDC, grainWBTC, grainETH, lendingPoolAddressesProvider
      } = await loadFixture(deployProtocol);
      const tokens = [usdc, wbtc, weth];
      const grainTokens = [grainUSDC, grainWBTC, grainETH];
      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("100", 6);

      await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
      await approve(lendingPoolProxy.address, usdc, addr1);
      await deposit(lendingPoolProxy, addr1, usdc.address, USDC_DEPOSIT_SIZE, addr1.address);
      await borrow(lendingPoolProxy, addr1, usdc.address, ethers.utils.parseUnits("10", 6), addr1.address);
      
      // BEFORE REBALANCE
      let currentVariableBorrowRate = await getCurrentVariableRate(aaveProtocolDataProvider, usdc, grainUSDC, stableStrategy);
      let expectedVariableRate = await getExpectedVariableRate(aaveProtocolDataProvider, usdc, grainUSDC, stableStrategy);
      expect(currentVariableBorrowRate).to.equal(expectedVariableRate);

      await prepareRehypothecation(lendingPoolConfiguratorProxy, tokens, grainTokens, owner.address);
      await lendingPoolConfiguratorProxy.rebalance(grainUSDC.address);

      // AFTER REBALANCE
      currentVariableBorrowRate = await getCurrentVariableRate(aaveProtocolDataProvider, usdc, grainUSDC, stableStrategy);
      expectedVariableRate = await getExpectedVariableRate(aaveProtocolDataProvider, usdc, grainUSDC, stableStrategy);
      expect(currentVariableBorrowRate).to.equal(expectedVariableRate);
    });
  });

  // ## LendingPoolCollateralManager via LendingPool ##
  describe("LendingPoolCollateralManager", function () {
    // liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken) 
    it("liquidationCall", async function () {
      [owner, addr1, addr2] = await ethers.getSigners();
      const VARIABLE_RATE_MODE = "2";
      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);
      const WBTC_DEPOSIT_SIZE = ethers.utils.parseUnits("1", 8);
      const MIN_HEALTH_FACTOR = ethers.utils.parseEther("1");

      const {  aaveOracle, usdc, wbtc, weth, grainUSDC, grainWBTC, grainETH,variableDebtUSDC, variableDebtWBTC,
      variableDebtETH, lendingPoolProxy, usdcPriceFeed, wbtcPriceFeed, ethPriceFeed, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

      const usdcDepositValue = (USDC_DEPOSIT_SIZE).mul(await usdcPriceFeed.latestAnswer());

      const usdcLTV = (await aaveProtocolDataProvider.getReserveConfigurationData(usdc.address)).ltv;

      const usdcMaxBorrowNative = ( USDC_DEPOSIT_SIZE * (usdcLTV / 10000));

      const usdcMaxBorrowValue = usdcDepositValue.mul(usdcLTV).div(10000).div(ethers.utils.parseUnits("1", 6));

      const maxBitcoinBorrow = usdcMaxBorrowValue.div((await wbtcPriceFeed.latestAnswer()).div(ethers.utils.parseUnits("1", 8)));

      await prepareMockTokens(usdc, owner, USDC_DEPOSIT_SIZE);
      await prepareMockTokens(wbtc, addr1, WBTC_DEPOSIT_SIZE);

      await approve(lendingPoolProxy.address, usdc, owner);
      await approve(lendingPoolProxy.address, wbtc, addr1);

      await deposit(lendingPoolProxy, false, owner, usdc.address, USDC_DEPOSIT_SIZE, owner.address);
      await deposit(lendingPoolProxy, false, addr1, wbtc.address, WBTC_DEPOSIT_SIZE, addr1.address);

      await borrow(lendingPoolProxy, false, owner, wbtc.address, maxBitcoinBorrow, owner.address);

      const userAccountDataBefore = await lendingPoolProxy.getUserAccountData(owner.address);
      expect(userAccountDataBefore.healthFactor).to.be.gt(MIN_HEALTH_FACTOR);

      const newUsdcPriceFeed = await deployMockAggregator("94000000");
      await setAssetSources(aaveOracle, owner, [usdc.address], [newUsdcPriceFeed.address])

      // BEFORE
      const usdcReserveDataBefore = await aaveProtocolDataProvider.getReserveData(usdc.address);
      const wbtcReserveDataBefore = await aaveProtocolDataProvider.getReserveData(wbtc.address);
      const userReserveDataBefore = await aaveProtocolDataProvider.getUserReserveData(wbtc.address, owner.address);

      await prepareMockTokens(wbtc, addr2, WBTC_DEPOSIT_SIZE);
      await approve(lendingPoolProxy.address, wbtc, addr2);
      const amountToLiquidate = userReserveDataBefore.currentVariableDebt.div(2);
      const tx = await lendingPoolProxy.connect(addr2).liquidationCall(
        usdc.address,
        wbtc.address,
        owner.address,
        amountToLiquidate,
        false
      );

      // AFTER
      const usdcReserveDataAfter = await aaveProtocolDataProvider.getReserveData(usdc.address);
      const wbtcReserveDataAfter = await aaveProtocolDataProvider.getReserveData(wbtc.address);
      const userReserveDataAfter = await aaveProtocolDataProvider.getUserReserveData(wbtc.address, owner.address);
      const userAccountDataAfter = await lendingPoolProxy.getUserAccountData(owner.address);

      const collateralPrice = await newUsdcPriceFeed.latestAnswer();
      const debtPrice = await wbtcPriceFeed.latestAnswer();
      const collateralDecimals = await usdc.decimals();
      const debtDecimals = await wbtc.decimals();

      const reserveConfigurationData = await aaveProtocolDataProvider.getReserveConfigurationData(usdc.address);

      const expectedCollateralLiquidated = debtPrice
        .mul(amountToLiquidate.mul(reserveConfigurationData.liquidationBonus).div(10000))
        .mul(BigNumber.from("10").pow(collateralDecimals))
        .div(collateralPrice.mul(BigNumber.from(10).pow(debtDecimals)));

      const txTimestamp = await time.latest();

      const variableDebtBeforeTx = await calcExpectedVariableDebtTokenBalance(
        wbtcReserveDataBefore,
        userReserveDataBefore,
        txTimestamp
      );

      expect(userAccountDataAfter.healthFactor).to.be.gt(
        ethers.utils.parseEther("1"),
        'Invalid health factor'
      );

      expect(userReserveDataAfter.currentVariableDebt).to.be.closeTo(
        variableDebtBeforeTx.sub(amountToLiquidate),
        100, // accepted variance
        'Invalid user borrow balance after liquidation'
      );

      expect(wbtcReserveDataAfter.availableLiquidity).to.be.closeTo(
        wbtcReserveDataBefore.availableLiquidity,
        100, // accepted variance
        'Invalid principal available liquidity'
      );

      //the liquidity index of the principal reserve needs to be bigger than the index before
      expect(wbtcReserveDataAfter.liquidityIndex).to.be.gte(
        wbtcReserveDataBefore.liquidityIndex,
        'Invalid liquidity index'
      );

      //the principal APY after a liquidation needs to be lower than the APY before
      expect(wbtcReserveDataAfter.liquidityRate).to.be.lt(
        wbtcReserveDataBefore.liquidityRate,
        'Invalid liquidity APY'
      );

      expect(usdcReserveDataAfter.availableLiquidity).to.be.closeTo(
        usdcReserveDataBefore.availableLiquidity.sub(expectedCollateralLiquidated),
        100,
        'Invalid collateral available liquidity'
      );

      expect(
        (await aaveProtocolDataProvider.getUserReserveData(usdc.address, owner.address))
          .usageAsCollateralEnabled
      ).to.be.true;
    });
  });

  // ## LendingPool ##
  describe("LendingPool", function () {
    // check onlyLendingPoolConfigurator Modifier
    describe("Checks onlyLendingPoolConfigurator Modifier", function () {
      before(async function () {
        [owner, addr1] = await ethers.getSigners();
      });

      //setFarmingPct(address aTokenAddress, uint256 farmingPct)
      it("Tries to call setFarmingPct not being lendingPoolConfigurator", async function () {
        const { grainUSDC, lendingPoolProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolProxy.setFarmingPct(grainUSDC.address, "2000")).to.be.revertedWith(
          "27"
        );
      });

      //setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold)
      it("Tries to call setClaimingThreshold not being lendingPoolConfigurator", async function () {
        const { grainUSDC, lendingPoolProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolProxy.setClaimingThreshold(grainUSDC.address, ethers.utils.parseUnits("1", 6))).to.be.revertedWith(
          "27"
        );
      });

      //setFarmingPctDrift(address aTokenAddress, uint256 _farmingPctDrift)
      it("Tries to call setFarmingPctDrift not being lendingPoolConfigurator", async function () {
        const { grainUSDC, lendingPoolProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolProxy.setFarmingPctDrift(grainUSDC.address, "100")).to.be.revertedWith(
          "27"
        );
      });

      //setProfitHandler(address aTokenAddress, address _profitHandler)
      it("Tries to call setProfitHandler not being lendingPoolConfigurator", async function () {
        const { grainUSDC, lendingPoolProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolProxy.setProfitHandler(grainUSDC.address, owner.address)).to.be.revertedWith(
          "27"
        );
      });

      //setVault(address aTokenAddress, address _vault)
      it("Tries to call setVault not being lendingPoolConfigurator", async function () {
        const { grainUSDC, lendingPoolProxy } = await loadFixture(deployProtocol);
        const mockVault = Wallet.createRandom().address;
        await expect(lendingPoolProxy.setVault(grainUSDC.address, mockVault)).to.be.revertedWith(
          "27"
        );
      });

      //rebalance(address aTokenAddress)
      it("Tries to call rebalance not being lendingPoolConfigurator", async function () {
        const { grainUSDC, lendingPoolProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolProxy.rebalance(grainUSDC.address)).to.be.revertedWith(
          "27"
        );
      });

      //getTotalManagedAssets(address aTokenAddress)
      it("Tries to call getTotalManagedAssets not being lendingPoolConfigurator", async function () {
        const { grainUSDC, lendingPoolProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolProxy.getTotalManagedAssets(grainUSDC.address)).to.be.revertedWith(
          "27"
        );
      });
    });
  });

  // ## LendingPoolConfigurator ##
  describe("LendingPoolConfigurator", function () {
    // check onlyPoolAdmin modifier
    describe("Checks onlyPoolAdmin Modifier", function () {
      before(async function () {
        [owner, addr1] = await ethers.getSigners();
      });

      //setFarmingPct(address aTokenAddress, uint256 farmingPct)
      it("Tries to call setFarmingPct not being onlyPoolAdmin", async function () {
        const { grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolConfiguratorProxy.connect(addr1).setFarmingPct(grainUSDC.address, "2000")).to.be.revertedWith(
          "33"
        );
      });

      //setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold)
      it("Tries to call setClaimingThreshold not being onlyPoolAdmin", async function () {
        const { grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolConfiguratorProxy.connect(addr1).setClaimingThreshold(grainUSDC.address, ethers.utils.parseUnits("1", 6))).to.be.revertedWith(
          "33"
        );
      });

      //setFarmingPctDrift(address aTokenAddress, uint256 _farmingPctDrift)
      it("Tries to call setFarmingPctDrift not being onlyPoolAdmin", async function () {
        const { grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolConfiguratorProxy.connect(addr1).setFarmingPctDrift(grainUSDC.address, "100")).to.be.revertedWith(
          "33"
        );
      });

      //setProfitHandler(address aTokenAddress, address _profitHandler)
      it("Tries to call setProfitHandler not being onlyPoolAdmin", async function () {
        const { grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolConfiguratorProxy.connect(addr1).setProfitHandler(grainUSDC.address, owner.address)).to.be.revertedWith(
          "33"
        );
      });

      //setVault(address aTokenAddress, address _vault)
      it("Tries to call setVault not being onlyPoolAdmin", async function () {
        const { grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
        const mockVault = Wallet.createRandom().address;
        await expect(lendingPoolConfiguratorProxy.connect(addr1).setVault(grainUSDC.address, mockVault)).to.be.revertedWith(
          "33"
        );
      });

      //rebalance(address aTokenAddress)
      it("Tries to call rebalance not being onlyPoolAdmin", async function () {
        const { grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
        await expect(lendingPoolConfiguratorProxy.connect(addr1).rebalance(grainUSDC.address)).to.be.revertedWith(
          "76"
        );
      });
    });

    // setVault(address aTokenAddress, address _vault)
    it("setVault", async function () {
      const { usdc, grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
      let usdcMockErc4626 = await deployMockErc4626(usdc)

      expect(await grainUSDC.vault()).to.be.equal("0x0000000000000000000000000000000000000000");
      await lendingPoolConfiguratorProxy.setVault(grainUSDC.address, usdcMockErc4626.address);
      expect(await grainUSDC.vault()).to.be.equal(usdcMockErc4626.address);
    });

    // setFarmingPct(address aTokenAddress, uint256 farmingPct)
    it("setFarmingPct", async function () {
      const { usdc, grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
      let usdcMockErc4626 = await deployMockErc4626(usdc);
      await expect(lendingPoolConfiguratorProxy.setFarmingPct(grainUSDC.address, "2000")).to.be.revertedWith(
        "84"
      );
      await lendingPoolConfiguratorProxy.setVault(grainUSDC.address, usdcMockErc4626.address);
      
      await expect(lendingPoolConfiguratorProxy.setFarmingPct(grainUSDC.address, "10001")).to.be.revertedWith(
        "82"
      );
      await lendingPoolConfiguratorProxy.setFarmingPct(grainUSDC.address, "2000");
      
      expect(await grainUSDC.farmingPct()).to.be.equal("2000");
    });

    // setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold)
    it("setClaimingThreshold", async function () {
      const { usdc, grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
      let usdcMockErc4626 = await deployMockErc4626(usdc);
      await expect(lendingPoolConfiguratorProxy.setClaimingThreshold(grainUSDC.address, "2000")).to.be.revertedWith(
        "84"
      );
      await lendingPoolConfiguratorProxy.setVault(grainUSDC.address, usdcMockErc4626.address);
      
      await lendingPoolConfiguratorProxy.setClaimingThreshold(grainUSDC.address, ethers.utils.parseUnits("1", 6));
      
      expect(await grainUSDC.claimingThreshold()).to.be.equal(ethers.utils.parseUnits("1", 6));
    });

    // setFarmingPctDrift(address aTokenAddress, uint256 _farmingPctDrift)
    it("setFarmingPctDrift", async function () {
      const { usdc, grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
      let usdcMockErc4626 = await deployMockErc4626(usdc);
      await expect(lendingPoolConfiguratorProxy.setFarmingPctDrift(grainUSDC.address, "200")).to.be.revertedWith(
        "84"
      );
      await lendingPoolConfiguratorProxy.setVault(grainUSDC.address, usdcMockErc4626.address);
      
      await expect(lendingPoolConfiguratorProxy.setFarmingPctDrift(grainUSDC.address, "10001")).to.be.revertedWith(
        "82"
      );
      await lendingPoolConfiguratorProxy.setFarmingPctDrift(grainUSDC.address, "200");
      
      expect(await grainUSDC.farmingPctDrift()).to.be.equal("200");
    });

    // setProfitHandler(address aTokenAddress, address _profitHandler)
    it("setProfitHandler", async function () {
      const { usdc, grainUSDC, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);
      let usdcMockErc4626 = await deployMockErc4626(usdc);
      await expect(lendingPoolConfiguratorProxy.setProfitHandler(grainUSDC.address, owner.address)).to.be.revertedWith(
        "84"
      );
      await lendingPoolConfiguratorProxy.setVault(grainUSDC.address, usdcMockErc4626.address);
      
      await expect(lendingPoolConfiguratorProxy.setProfitHandler(grainUSDC.address, "0x0000000000000000000000000000000000000000")).to.be.revertedWith(
        "83"
      );
      await lendingPoolConfiguratorProxy.setProfitHandler(grainUSDC.address, owner.address);
      
      expect(await grainUSDC.profitHandler()).to.be.equal(owner.address);
    });

    // rebalance(address aTokenAddress)
    it("rebalance", async function () {
      const { usdc, grainUSDC, lendingPoolProxy, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("100", 6);
      await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
      await approve(lendingPoolProxy.address, usdc, addr1);
      await deposit(lendingPoolProxy, addr1, usdc.address, USDC_DEPOSIT_SIZE, addr1.address);

      let usdcMockErc4626 = await deployMockErc4626(usdc);
      await lendingPoolConfiguratorProxy.setVault(grainUSDC.address, usdcMockErc4626.address);
      await lendingPoolConfiguratorProxy.setFarmingPct(grainUSDC.address, "2000");
      await lendingPoolConfiguratorProxy.setClaimingThreshold(grainUSDC.address, ethers.utils.parseUnits("1", 6));
      await lendingPoolConfiguratorProxy.setFarmingPctDrift(grainUSDC.address, "200");
      await lendingPoolConfiguratorProxy.setProfitHandler(grainUSDC.address, owner.address);

      expect(await usdc.balanceOf(grainUSDC.address)).to.equal(USDC_DEPOSIT_SIZE);

      await lendingPoolConfiguratorProxy.rebalance(grainUSDC.address);

      const remainingPct = BigNumber.from("10000").sub(await grainUSDC.farmingPct());
      expect(await usdc.balanceOf(grainUSDC.address)).to.equal(USDC_DEPOSIT_SIZE.mul(remainingPct).div(10000));

      expect(await grainUSDC.getTotalManagedAssets()).to.equal(USDC_DEPOSIT_SIZE);
    });
  });
 
  // ## Scenarios ##
  describe("Scenarios", function () {
    // paused LendingPool - mint, burn, and transferUnderlyingTo will not be called, but we can still call rebalance()
    describe("paused LendingPool", function () {
      it("rebalance()", async function () {
        const { usdc, grainUSDC, lendingPoolProxy, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

        const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("100", 6);
        await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
        await approve(lendingPoolProxy.address, usdc, addr1);
        await deposit(lendingPoolProxy, addr1, usdc.address, USDC_DEPOSIT_SIZE, addr1.address);

        let usdcMockErc4626 = await deployMockErc4626(usdc);
        await lendingPoolConfiguratorProxy.setVault(grainUSDC.address, usdcMockErc4626.address);
        await lendingPoolConfiguratorProxy.setFarmingPct(grainUSDC.address, "2000");
        await lendingPoolConfiguratorProxy.setClaimingThreshold(grainUSDC.address, ethers.utils.parseUnits("1", 6));
        await lendingPoolConfiguratorProxy.setFarmingPctDrift(grainUSDC.address, "200");
        await lendingPoolConfiguratorProxy.setProfitHandler(grainUSDC.address, owner.address);

        expect(await usdc.balanceOf(grainUSDC.address)).to.equal(USDC_DEPOSIT_SIZE);

        await lendingPoolConfiguratorProxy.setPoolPause(true);
        await lendingPoolConfiguratorProxy.rebalance(grainUSDC.address);

        const remainingPct = BigNumber.from("10000").sub(await grainUSDC.farmingPct());
        expect(await usdc.balanceOf(grainUSDC.address)).to.equal(USDC_DEPOSIT_SIZE.mul(remainingPct).div(10000));

        expect(await grainUSDC.getTotalManagedAssets()).to.equal(USDC_DEPOSIT_SIZE);
      });
    });

    // not enough liquidity to withdraw, rebalance
    it("not enough liquidity to withdraw, rebalance", async function () {
      [owner, addr1] = await ethers.getSigners();
      const { usdc, grainUSDC, lendingPoolProxy, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("100", 6);
      await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
      await approve(lendingPoolProxy.address, usdc, addr1);
      await deposit(lendingPoolProxy, addr1, usdc.address, USDC_DEPOSIT_SIZE, addr1.address);

      let usdcMockErc4626 = await deployMockErc4626(usdc);
      await lendingPoolConfiguratorProxy.setVault(grainUSDC.address, usdcMockErc4626.address);
      await lendingPoolConfiguratorProxy.setFarmingPct(grainUSDC.address, "2000");
      await lendingPoolConfiguratorProxy.setClaimingThreshold(grainUSDC.address, ethers.utils.parseUnits("1", 6));
      await lendingPoolConfiguratorProxy.setFarmingPctDrift(grainUSDC.address, "200");
      await lendingPoolConfiguratorProxy.setProfitHandler(grainUSDC.address, owner.address);

      expect(await usdc.balanceOf(grainUSDC.address)).to.equal(USDC_DEPOSIT_SIZE);

      await lendingPoolConfiguratorProxy.rebalance(grainUSDC.address);

      const remainingPct = BigNumber.from("10000").sub(await grainUSDC.farmingPct());
      expect(await usdc.balanceOf(grainUSDC.address)).to.equal(USDC_DEPOSIT_SIZE.mul(remainingPct).div(10000));
      expect(await grainUSDC.getTotalManagedAssets()).to.equal(USDC_DEPOSIT_SIZE);
      
      await withdraw(lendingPoolProxy, addr1, usdc.address, ethers.utils.parseUnits("90", 6), addr1.address);
      expect(await usdc.balanceOf(addr1.address)).to.equal(ethers.utils.parseUnits("90", 6));
      expect(await grainUSDC.farmingBal()).to.equal(ethers.utils.parseUnits("2", 6));
      expect(await grainUSDC.getTotalManagedAssets()).to.equal(ethers.utils.parseUnits("10", 6));
    });

    // frozen reserve - no deposits/borrows - burn, transferUnderlyingTo would be called, but not mint
    // deactivated reserve 
    // disableBorrowing
    // disable reserve
    // make sure other configurator functions are unaffected
    // other scenarios?
  });
});