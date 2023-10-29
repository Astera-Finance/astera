import { expect } from "chai";
import hre from "hardhat";
import { Wallet, utils, BigNumber } from "ethers"; 
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { 
  deployProtocol,
  prepareMockTokens,
  approve,
  deposit
} from "./helpers/test-helpers";

describe("LendingPoolConfigurator", function () {
  let owner, addr1, addr2, addr3;

  it("Reverts trying to set an invalid reserve factor", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    const invalidReserveFactor = 77777;

    await expect(
      lendingPoolConfiguratorProxy.setReserveFactor(weth.address, false, invalidReserveFactor)
    ).to.be.revertedWith("71");
  });

  it("Deactivates the ETH reserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.deactivateReserve(weth.address, false);
    const { isActive } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);
    expect(isActive).to.be.equal(false);
  });

  it("Rectivates the ETH reserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.deactivateReserve(weth.address, false);
    await lendingPoolConfiguratorProxy.activateReserve(weth.address, false);
    const { isActive } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);
    expect(isActive).to.be.equal(true);
  });

  it("Check the onlyAaveAdmin on deactivateReserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await expect(
      lendingPoolConfiguratorProxy.connect(addr1).deactivateReserve(weth.address, false)
    ).to.be.revertedWith("33");
  });

  it("Check the onlyAaveAdmin on activateReserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await expect(
      lendingPoolConfiguratorProxy.connect(addr1).activateReserve(weth.address, false)
    ).to.be.revertedWith("33");
  });

  it("Freezes the ETH reserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.freezeReserve(weth.address, false);
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(true);
    expect(decimals).to.be.equal(18);
    expect(ltv).to.be.equal("8000");
    expect(liquidationThreshold).to.be.equal("8500");
    expect(liquidationBonus).to.be.equal("10500");
    expect(stableBorrowRateEnabled).to.be.equal(false);
    expect(reserveFactor).to.be.equal("1500");
  });
  
  it("Unfreezes the ETH reserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.unfreezeReserve(weth.address, false);
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(18);
    expect(ltv).to.be.equal("8000");
    expect(liquidationThreshold).to.be.equal("8500");
    expect(liquidationBonus).to.be.equal("10500");
    expect(stableBorrowRateEnabled).to.be.equal(false);
    expect(reserveFactor).to.be.equal("1500");
  });

  it("Check the onlyAaveAdmin on freezeReserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await expect(
      lendingPoolConfiguratorProxy.connect(addr1).freezeReserve(weth.address, false)
    ).to.be.revertedWith("33");
  });


  it("Check the onlyAaveAdmin on unfreezeReserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await expect(
      lendingPoolConfiguratorProxy.connect(addr1).unfreezeReserve(weth.address, false)
    ).to.be.revertedWith("33");
  });

  it("Deactivates the ETH reserve for borrowing", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.disableBorrowingOnReserve(weth.address, false);
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);

    expect(borrowingEnabled).to.be.equal(false);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(18);
    expect(ltv).to.be.equal("8000");
    expect(liquidationThreshold).to.be.equal("8500");
    expect(liquidationBonus).to.be.equal("10500");
    expect(stableBorrowRateEnabled).to.be.equal(false);
    expect(reserveFactor).to.be.equal("1500");
  });

  it("Activates the ETH reserve for borrowing", async function () {
    [owner, addr1] = await ethers.getSigners();
    const RAY = ethers.utils.parseUnits("1", 27);

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.enableBorrowingOnReserve(weth.address, false, false);
    const { variableBorrowIndex } = await aaveProtocolDataProvider.getReserveData(weth.address, false);
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(18);
    expect(ltv).to.be.equal("8000");
    expect(liquidationThreshold).to.be.equal("8500");
    expect(liquidationBonus).to.be.equal("10500");
    expect(stableBorrowRateEnabled).to.be.equal(false);
    expect(reserveFactor).to.be.equal("1500");
    expect(variableBorrowIndex.toString()).to.be.equal(RAY);
  });

  it("Check the onlyAaveAdmin on disableBorrowingOnReserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await expect(
      lendingPoolConfiguratorProxy.connect(addr1).disableBorrowingOnReserve(weth.address, false)
    ).to.be.revertedWith("33");
  });

  it("Check the onlyAaveAdmin on enableBorrowingOnReserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await expect(
      lendingPoolConfiguratorProxy.connect(addr1).enableBorrowingOnReserve(weth.address, false, false)
    ).to.be.revertedWith("33");
  });

  it("Deactivates the ETH reserve as collateral", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.configureReserveAsCollateral(weth.address, false, 0, 0, 0);
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(18);
    expect(ltv).to.be.equal("0");
    expect(liquidationThreshold).to.be.equal("0");
    expect(liquidationBonus).to.be.equal("0");
    expect(stableBorrowRateEnabled).to.be.equal(false);
    expect(reserveFactor).to.be.equal("1500");
  });

  it("Activates the ETH reserve as collateral", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.configureReserveAsCollateral(weth.address, false, "8000", "8250", "10500");
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(18);
    expect(ltv).to.be.equal("8000");
    expect(liquidationThreshold).to.be.equal("8250");
    expect(liquidationBonus).to.be.equal("10500");
    expect(stableBorrowRateEnabled).to.be.equal(false);
    expect(reserveFactor).to.be.equal("1500");
  });

  it("Check the onlyAaveAdmin on configureReserveAsCollateral", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await expect(
      lendingPoolConfiguratorProxy.connect(addr1).configureReserveAsCollateral(weth.address, false,"8000", "8250", "10500")
    ).to.be.revertedWith("33");
  });

  it("Disable stable borrow rate on the ETH reserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.disableReserveStableRate(weth.address, false);
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(18);
    expect(ltv).to.be.equal("8000");
    expect(liquidationThreshold).to.be.equal("8500");
    expect(liquidationBonus).to.be.equal("10500");
    expect(stableBorrowRateEnabled).to.be.equal(false);
    expect(reserveFactor).to.be.equal("1500");
  });

  it("Enables stable borrow rate on the ETH reserve", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.enableReserveStableRate(weth.address, false);
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(18);
    expect(ltv).to.be.equal("8000");
    expect(liquidationThreshold).to.be.equal("8500");
    expect(liquidationBonus).to.be.equal("10500");
    expect(stableBorrowRateEnabled).to.be.equal(true);
    expect(reserveFactor).to.be.equal("1500");
  });

  it("Check the onlyAaveAdmin on disableReserveStableRate", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await expect(
      lendingPoolConfiguratorProxy.connect(addr1).disableReserveStableRate(weth.address, false)
    ).to.be.revertedWith("33");
  });

  //Check the onlyAaveAdmin on enableReserveStableRate
  it("Check the onlyAaveAdmin on enableReserveStableRate", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await expect(
      lendingPoolConfiguratorProxy.connect(addr1).enableReserveStableRate(weth.address, false)
    ).to.be.revertedWith("33");
  });

  it("Changes the reserve factor of WETH", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy, aaveProtocolDataProvider } = await loadFixture(deployProtocol);

    await lendingPoolConfiguratorProxy.setReserveFactor(weth.address, false, "1000");
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await aaveProtocolDataProvider.getReserveConfigurationData(weth.address, false);

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(18);
    expect(ltv).to.be.equal("8000");
    expect(liquidationThreshold).to.be.equal("8500");
    expect(liquidationBonus).to.be.equal("10500");
    expect(stableBorrowRateEnabled).to.be.equal(false);
    expect(reserveFactor).to.be.equal("1000");
  });

  it("Check the onlyLendingPoolManager on setReserveFactor", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { weth, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await expect(
      lendingPoolConfiguratorProxy.connect(addr1).setReserveFactor(weth.address, false, "2000")
    ).to.be.revertedWith("33");
  });

  it("Reverts when trying to disable the DAI reserve with liquidity on it", async function () {
    [owner, addr1] = await ethers.getSigners();
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1", 6);

    const { usdc, lendingPoolProxy, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);

    await approve(lendingPoolProxy.address, usdc, addr1);

    await deposit(lendingPoolProxy, addr1, usdc.address, false, USDC_DEPOSIT_SIZE, addr1.address);

    await expect(
      lendingPoolConfiguratorProxy.deactivateReserve(usdc.address, false)
    ).to.be.revertedWith("34");
  });

  // it("Accepts setting rehypothecation values on AToken", async function () {
  //   [owner, addr1] = await ethers.getSigners();
  //   const { lendingPoolConfiguratorProxy, grainUSDC, mockUsdcErc4626 } = await loadFixture(deployProtocol);
  //   await lendingPoolConfiguratorProxy.setVault(grainUSDC.address, mockUsdcErc4626.address);
  //   await lendingPoolConfiguratorProxy.setProfitHandler(grainUSDC.address, owner.address);
  //   await lendingPoolConfiguratorProxy.setFarmingPct(grainUSDC.address, 500);
  //   await lendingPoolConfiguratorProxy.setClaimingThreshold(grainUSDC.address, 1000000);
  //   await lendingPoolConfiguratorProxy.setFarmingPctDrift(grainUSDC.address, 100);
  //   await lendingPoolConfiguratorProxy.rebalance(grainUSDC.address);
  // });
});