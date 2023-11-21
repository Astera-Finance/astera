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
  setAssetSources,
  deployMockAggregator,
  calcExpectedVariableDebtTokenBalance,
} from "./helpers/test-helpers";

describe("Liquidations", function () {
  let owner, addr1, addr2, addr3;

  describe("Liquidates borrow for AToken", function () {
    it("Tries to liquidate healthy loan for AToken", async function () {
      [owner, addr1] = await ethers.getSigners();
      const VARIABLE_RATE_MODE = "2";
      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);
      const WBTC_DEPOSIT_SIZE = ethers.utils.parseUnits("1", 8);

      const { usdc, wbtc, weth, grainUSDC, grainWBTC, grainETH,variableDebtUSDC, variableDebtWBTC, 
      variableDebtETH, lendingPoolProxy, usdcPriceFeed, wbtcPriceFeed, ethPriceFeed, protocolDataProvider } = await loadFixture(deployProtocol);

      const usdcDepositValue = (USDC_DEPOSIT_SIZE).mul(await usdcPriceFeed.latestAnswer());

      const usdcLTV = (await protocolDataProvider.getReserveConfigurationData(usdc.address)).ltv;

      const usdcMaxBorrowNative = ( USDC_DEPOSIT_SIZE * (usdcLTV / 10000));

      const usdcMaxBorrowValue = usdcDepositValue.mul(usdcLTV).div(10000).div(ethers.utils.parseUnits("1", 6));

      const maxBitcoinBorrow = usdcMaxBorrowValue.div((await wbtcPriceFeed.latestAnswer()).div(ethers.utils.parseUnits("1", 8)));

      await prepareMockTokens(usdc, owner, USDC_DEPOSIT_SIZE);
      await prepareMockTokens(wbtc, addr1, WBTC_DEPOSIT_SIZE);

      await approve(lendingPoolProxy.address, usdc, owner);
      await approve(lendingPoolProxy.address, wbtc, addr1);

      await deposit(lendingPoolProxy, owner, usdc.address, USDC_DEPOSIT_SIZE, owner.address);
      await deposit(lendingPoolProxy, addr1, wbtc.address, WBTC_DEPOSIT_SIZE, addr1.address);

      await borrow(lendingPoolProxy, owner, wbtc.address, maxBitcoinBorrow, owner.address);
      const userReserveData = await protocolDataProvider.getUserReserveData(usdc.address, owner.address);
      const amountToLiquidate = userReserveData.currentVariableDebt.div(2);

      // address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken
      await expect(lendingPoolProxy.liquidationCall(usdc.address, wbtc.address, owner.address, amountToLiquidate, true)).to.be.revertedWith(
        "42" // LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD
      );
    });

    it("Liquidates unhealthy loan for AToken", async function () {
      [owner, addr1, addr2] = await ethers.getSigners();
      const VARIABLE_RATE_MODE = "2";
      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);
      const WBTC_DEPOSIT_SIZE = ethers.utils.parseUnits("1", 8);
      const MIN_HEALTH_FACTOR = ethers.utils.parseEther("1");

      const {  oracle, usdc, wbtc, weth, grainUSDC, grainWBTC, grainETH,variableDebtUSDC, variableDebtWBTC,
      variableDebtETH, lendingPoolProxy, usdcPriceFeed, wbtcPriceFeed, ethPriceFeed, protocolDataProvider } = await loadFixture(deployProtocol);

      const usdcDepositValue = (USDC_DEPOSIT_SIZE).mul(await usdcPriceFeed.latestAnswer());

      const usdcLTV = (await protocolDataProvider.getReserveConfigurationData(usdc.address)).ltv;

      const usdcMaxBorrowNative = ( USDC_DEPOSIT_SIZE * (usdcLTV / 10000));

      const usdcMaxBorrowValue = usdcDepositValue.mul(usdcLTV).div(10000).div(ethers.utils.parseUnits("1", 6));

      const maxBitcoinBorrow = usdcMaxBorrowValue.div((await wbtcPriceFeed.latestAnswer()).div(ethers.utils.parseUnits("1", 8)));

      await prepareMockTokens(usdc, owner, USDC_DEPOSIT_SIZE);
      await prepareMockTokens(wbtc, addr1, WBTC_DEPOSIT_SIZE);

      await approve(lendingPoolProxy.address, usdc, owner);
      await approve(lendingPoolProxy.address, wbtc, addr1);

      await deposit(lendingPoolProxy, owner, usdc.address, USDC_DEPOSIT_SIZE, owner.address);
      await deposit(lendingPoolProxy, addr1, wbtc.address, WBTC_DEPOSIT_SIZE, addr1.address);

      await borrow(lendingPoolProxy, owner, wbtc.address, maxBitcoinBorrow, owner.address);

      const userAccountDataBefore = await lendingPoolProxy.getUserAccountData(owner.address);
      expect(userAccountDataBefore.healthFactor).to.be.gt(MIN_HEALTH_FACTOR);

      const newUsdcPriceFeed = await deployMockAggregator("94000000", await usdc.decimals());
      await setAssetSources(oracle, owner, [usdc.address], [newUsdcPriceFeed.address])

      // BEFORE
      const usdcReserveDataBefore = await protocolDataProvider.getReserveData(usdc.address);
      const wbtcReserveDataBefore = await protocolDataProvider.getReserveData(wbtc.address);
      const userReserveDataBefore = await protocolDataProvider.getUserReserveData(wbtc.address, owner.address);

      await prepareMockTokens(wbtc, addr2, WBTC_DEPOSIT_SIZE);
      await approve(lendingPoolProxy.address, wbtc, addr2);
      const amountToLiquidate = userReserveDataBefore.currentVariableDebt.div(2);
      const tx = await lendingPoolProxy.connect(addr2).liquidationCall(
        usdc.address,
        wbtc.address,
        owner.address,
        amountToLiquidate,
        true
      );

      // AFTER
      const usdcReserveDataAfter = await protocolDataProvider.getReserveData(usdc.address);
      const wbtcReserveDataAfter = await protocolDataProvider.getReserveData(wbtc.address);
      const userReserveDataAfter = await protocolDataProvider.getUserReserveData(wbtc.address, owner.address);
      const userAccountDataAfter = await lendingPoolProxy.getUserAccountData(owner.address);

      const collateralPrice = await newUsdcPriceFeed.latestAnswer();
      const debtPrice = await wbtcPriceFeed.latestAnswer();
      const collateralDecimals = await usdc.decimals();
      const debtDecimals = await wbtc.decimals();

      const reserveConfigurationData = await protocolDataProvider.getReserveConfigurationData(usdc.address);

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
        wbtcReserveDataAfter.availableLiquidity,
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
        usdcReserveDataBefore.availableLiquidity,
        100,
        'Invalid collateral available liquidity'
      );

      expect(
        (await protocolDataProvider.getUserReserveData(usdc.address, owner.address))
          .usageAsCollateralEnabled
      ).to.be.true;
    });
  });

  describe("Liquidates borrow for Underlying", function () {
    it("Tries to liquidate healthy loan for underlying", async function () {
      [owner, addr1] = await ethers.getSigners();
      const VARIABLE_RATE_MODE = "2";
      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);
      const WBTC_DEPOSIT_SIZE = ethers.utils.parseUnits("1", 8);

      const { usdc, wbtc, weth, grainUSDC, grainWBTC, grainETH,variableDebtUSDC, variableDebtWBTC, 
      variableDebtETH, lendingPoolProxy, usdcPriceFeed, wbtcPriceFeed, ethPriceFeed, protocolDataProvider } = await loadFixture(deployProtocol);

      const usdcDepositValue = (USDC_DEPOSIT_SIZE).mul(await usdcPriceFeed.latestAnswer());

      const usdcLTV = (await protocolDataProvider.getReserveConfigurationData(usdc.address)).ltv;

      const usdcMaxBorrowNative = ( USDC_DEPOSIT_SIZE * (usdcLTV / 10000));

      const usdcMaxBorrowValue = usdcDepositValue.mul(usdcLTV).div(10000).div(ethers.utils.parseUnits("1", 6));

      const maxBitcoinBorrow = usdcMaxBorrowValue.div((await wbtcPriceFeed.latestAnswer()).div(ethers.utils.parseUnits("1", 8)));

      await prepareMockTokens(usdc, owner, USDC_DEPOSIT_SIZE);
      await prepareMockTokens(wbtc, addr1, WBTC_DEPOSIT_SIZE);

      await approve(lendingPoolProxy.address, usdc, owner);
      await approve(lendingPoolProxy.address, wbtc, addr1);

      await deposit(lendingPoolProxy, owner, usdc.address, USDC_DEPOSIT_SIZE, owner.address);
      await deposit(lendingPoolProxy, addr1, wbtc.address, WBTC_DEPOSIT_SIZE, addr1.address);

      await borrow(lendingPoolProxy, owner, wbtc.address, maxBitcoinBorrow, owner.address);
      const userReserveData = await protocolDataProvider.getUserReserveData(usdc.address, owner.address);
      const amountToLiquidate = userReserveData.currentVariableDebt.div(2);

      // address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken
      await expect(lendingPoolProxy.liquidationCall(usdc.address, wbtc.address, owner.address, amountToLiquidate, false)).to.be.revertedWith(
        "42" // LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD
      );
    });


    it("Liquidates unhealthy loan for underlying", async function () {
      [owner, addr1, addr2] = await ethers.getSigners();
      const VARIABLE_RATE_MODE = "2";
      const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);
      const WBTC_DEPOSIT_SIZE = ethers.utils.parseUnits("1", 8);
      const MIN_HEALTH_FACTOR = ethers.utils.parseEther("1");

      const {  oracle, usdc, wbtc, weth, grainUSDC, grainWBTC, grainETH,variableDebtUSDC, variableDebtWBTC,
      variableDebtETH, lendingPoolProxy, usdcPriceFeed, wbtcPriceFeed, ethPriceFeed, protocolDataProvider } = await loadFixture(deployProtocol);

      const usdcDepositValue = (USDC_DEPOSIT_SIZE).mul(await usdcPriceFeed.latestAnswer());

      const usdcLTV = (await protocolDataProvider.getReserveConfigurationData(usdc.address)).ltv;

      const usdcMaxBorrowNative = ( USDC_DEPOSIT_SIZE * (usdcLTV / 10000));

      const usdcMaxBorrowValue = usdcDepositValue.mul(usdcLTV).div(10000).div(ethers.utils.parseUnits("1", 6));

      const maxBitcoinBorrow = usdcMaxBorrowValue.div((await wbtcPriceFeed.latestAnswer()).div(ethers.utils.parseUnits("1", 8)));

      await prepareMockTokens(usdc, owner, USDC_DEPOSIT_SIZE);
      await prepareMockTokens(wbtc, addr1, WBTC_DEPOSIT_SIZE);

      await approve(lendingPoolProxy.address, usdc, owner);
      await approve(lendingPoolProxy.address, wbtc, addr1);

      await deposit(lendingPoolProxy, owner, usdc.address, USDC_DEPOSIT_SIZE, owner.address);
      await deposit(lendingPoolProxy, addr1, wbtc.address, WBTC_DEPOSIT_SIZE, addr1.address);

      await borrow(lendingPoolProxy, owner, wbtc.address, maxBitcoinBorrow, owner.address);

      const userAccountDataBefore = await lendingPoolProxy.getUserAccountData(owner.address);
      expect(userAccountDataBefore.healthFactor).to.be.gt(MIN_HEALTH_FACTOR);

      const newUsdcPriceFeed = await deployMockAggregator("94000000", await usdc.decimals());
      await setAssetSources(oracle, owner, [usdc.address], [newUsdcPriceFeed.address])

      // BEFORE
      const usdcReserveDataBefore = await protocolDataProvider.getReserveData(usdc.address);
      const wbtcReserveDataBefore = await protocolDataProvider.getReserveData(wbtc.address);
      const userReserveDataBefore = await protocolDataProvider.getUserReserveData(wbtc.address, owner.address);

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
      const usdcReserveDataAfter = await protocolDataProvider.getReserveData(usdc.address);
      const wbtcReserveDataAfter = await protocolDataProvider.getReserveData(wbtc.address);
      const userReserveDataAfter = await protocolDataProvider.getUserReserveData(wbtc.address, owner.address);
      const userAccountDataAfter = await lendingPoolProxy.getUserAccountData(owner.address);

      const collateralPrice = await newUsdcPriceFeed.latestAnswer();
      const debtPrice = await wbtcPriceFeed.latestAnswer();
      const collateralDecimals = await usdc.decimals();
      const debtDecimals = await wbtc.decimals();

      const reserveConfigurationData = await protocolDataProvider.getReserveConfigurationData(usdc.address);

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
        wbtcReserveDataBefore.availableLiquidity.add(amountToLiquidate),
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
        (await protocolDataProvider.getUserReserveData(usdc.address, owner.address))
          .usageAsCollateralEnabled
      ).to.be.true;
    });
  });
});