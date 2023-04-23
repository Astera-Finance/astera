import { expect } from "chai";
import hre from "hardhat";
import { Wallet, utils } from "ethers"; 
import {
  deployLendingPoolAddressesProvider,
  deployLendingPool,
  deployLendingPoolConfigurator,
  deployLendingPoolCollateralManager
} from "./helpers/test-helpers";

describe("LendingPoolAddressesProvider", function () {
  const marketId = "Granary Genesis Market";

  it("getMarketId", async function () {
    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);
    expect(await lendingPoolAddressesProvider.getMarketId()).to.equal(marketId);
  });

  it("setMarketId", async function () {
    const defaultMarketId = "Granary Genesis Market";
    const newMarketId = "Granary Halo Market";

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(defaultMarketId);
    expect(await lendingPoolAddressesProvider.getMarketId()).to.equal(defaultMarketId);

    const tx = await lendingPoolAddressesProvider.setMarketId(newMarketId);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("MarketIdSet");
    expect(receipt.events[0].args?.newMarketId).to.equal(newMarketId);
    expect(await lendingPoolAddressesProvider.getMarketId()).to.equal(newMarketId);
  });

  it("setAddressAsProxy", async function () {
    const proxiedAddressId = utils.keccak256(utils.toUtf8Bytes('RANDOM_PROXIED'));

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);
    const lendingPool = await deployLendingPool();

    const tx = await lendingPoolAddressesProvider.setAddressAsProxy(proxiedAddressId, lendingPool.address);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("ProxyCreated");
    expect(receipt.events[1].event).to.equal("AddressSet");
    expect(receipt.events[1].args?.id).to.equal(proxiedAddressId);
    expect(receipt.events[1].args?.newAddress).to.equal(lendingPool.address);
    expect(receipt.events[1].args?.hasProxy).to.equal(true);
  });

  it("setAddress", async function () {
    const nonProxiedAddressId = utils.keccak256(utils.toUtf8Bytes('RANDOM_NON_PROXIED'));;
    const mockAddress = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);

    const tx = await lendingPoolAddressesProvider.setAddress(nonProxiedAddressId, mockAddress);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("AddressSet");
    expect(receipt.events[0].args?.id).to.equal(nonProxiedAddressId);
    expect(receipt.events[0].args?.newAddress).to.equal(mockAddress);
    expect(receipt.events[0].args?.hasProxy).to.equal(false);
    expect(mockAddress.toLowerCase()).to.equal(
    	(await lendingPoolAddressesProvider.getAddress(nonProxiedAddressId)).toLowerCase()
	);
  });

  it("getAddress", async function () {
    const nonProxiedAddressId = utils.keccak256(utils.toUtf8Bytes('RANDOM_NON_PROXIED'));;
    const mockAddress = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);

    await lendingPoolAddressesProvider.setAddress(nonProxiedAddressId, mockAddress);
    expect(await lendingPoolAddressesProvider.getAddress(nonProxiedAddressId)).to.equal(mockAddress);
  });

  it("getLendingPool", async function () {
    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);
    const lendingPool = await deployLendingPool();

    const tx = await lendingPoolAddressesProvider.setLendingPoolImpl(lendingPool.address);
    const receipt = await tx.wait();
    expect(await lendingPoolAddressesProvider.getLendingPool()).to.equal(receipt.events[0].args?.newAddress);
  });

  it("setLendingPoolImpl", async function () {
    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);
    const lendingPool = await deployLendingPool();

    const tx = await lendingPoolAddressesProvider.setLendingPoolImpl(lendingPool.address);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("ProxyCreated");
    expect(receipt.events[1].event).to.equal("LendingPoolUpdated");
    expect(receipt.events[1].args?.newAddress).to.equal(lendingPool.address);
  });

  it("getLendingPoolConfigurator", async function () {
    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);
    const lendingPoolConfigurator = await deployLendingPoolConfigurator();

    const tx = await lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(lendingPoolConfigurator.address);
    const receipt = await tx.wait();
    expect(await lendingPoolAddressesProvider.getLendingPoolConfigurator()).to.equal(receipt.events[0].args?.newAddress);
  });

  it("setLendingPoolConfiguratorImpl", async function () {
    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);
    const lendingPoolConfigurator = await deployLendingPoolConfigurator();

    const tx = await lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(lendingPoolConfigurator.address);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("ProxyCreated");
    expect(receipt.events[1].event).to.equal("LendingPoolConfiguratorUpdated");
    expect(receipt.events[1].args?.newAddress).to.equal(lendingPoolConfigurator.address);
  });

  it("getLendingPoolCollateralManager", async function () {
    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);
    const lendingPoolCollateralManager = await deployLendingPoolCollateralManager();

    const tx = await lendingPoolAddressesProvider.setLendingPoolCollateralManager(lendingPoolCollateralManager.address);
    const receipt = await tx.wait();
    expect(await lendingPoolAddressesProvider.getLendingPoolCollateralManager()).to.equal(receipt.events[0].args?.newAddress);
  });

  it("setLendingPoolCollateralManager", async function () {
    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);
    const lendingPoolCollateralManager = await deployLendingPoolCollateralManager();

    const tx = await lendingPoolAddressesProvider.setLendingPoolCollateralManager(lendingPoolCollateralManager.address);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("LendingPoolCollateralManagerUpdated");
    expect(receipt.events[0].args?.newAddress).to.equal(lendingPoolCollateralManager.address);
  });

  it("getPoolAdmin", async function () {
    const mockAddress = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);

    const tx = await lendingPoolAddressesProvider.setPoolAdmin(mockAddress);
    const receipt = await tx.wait();
    expect(await lendingPoolAddressesProvider.getPoolAdmin()).to.equal(receipt.events[0].args?.newAddress);
  });

  it("setPoolAdmin", async function () {
    const mockAddress = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);

    const tx = await lendingPoolAddressesProvider.setPoolAdmin(mockAddress);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("ConfigurationAdminUpdated");
    expect(receipt.events[0].args?.newAddress).to.equal(mockAddress);
  });

  it("getEmergencyAdmin", async function () {
    const mockAddress = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);

    const tx = await lendingPoolAddressesProvider.setEmergencyAdmin(mockAddress);
    const receipt = await tx.wait();
    expect(await lendingPoolAddressesProvider.getEmergencyAdmin()).to.equal(receipt.events[0].args?.newAddress);
  });

  it("setEmergencyAdmin", async function () {
    const mockAddress = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);

    const tx = await lendingPoolAddressesProvider.setEmergencyAdmin(mockAddress);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("EmergencyAdminUpdated");
    expect(receipt.events[0].args?.newAddress).to.equal(mockAddress);
  });

  it("getPriceOracle", async function () {
    const mockPriceOracle = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);

    const tx = await lendingPoolAddressesProvider.setPriceOracle(mockPriceOracle);
    const receipt = await tx.wait();
    expect(await lendingPoolAddressesProvider.getPriceOracle()).to.equal(receipt.events[0].args?.newAddress);
  });

  it("setPriceOracle", async function () {
    const mockPriceOracle = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);

    const tx = await lendingPoolAddressesProvider.setPriceOracle(mockPriceOracle);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("PriceOracleUpdated");
    expect(receipt.events[0].args?.newAddress).to.equal(mockPriceOracle);
  });

  it("getLendingRateOracle", async function () {
    const mockLendingRateOracle = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);

    const tx = await lendingPoolAddressesProvider.setLendingRateOracle(mockLendingRateOracle);
    const receipt = await tx.wait();
    expect(await lendingPoolAddressesProvider.getLendingRateOracle()).to.equal(receipt.events[0].args?.newAddress);
  });

  it("setLendingRateOracle", async function () {
    const mockLendingRateOracle = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);

    const tx = await lendingPoolAddressesProvider.setLendingRateOracle(mockLendingRateOracle);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("LendingRateOracleUpdated");
    expect(receipt.events[0].args?.newAddress).to.equal(mockLendingRateOracle);
  });

  it("onlyOwner modifier", async function () {
    let owner, account0;
    [owner, account0] = await ethers.getSigners();

    const mockAddress = Wallet.createRandom().address;

    const lendingPoolAddressesProvider = await deployLendingPoolAddressesProvider(marketId);
    await lendingPoolAddressesProvider.transferOwnership(account0.address);

    for (const contractFunction of [
      lendingPoolAddressesProvider.setMarketId,
      lendingPoolAddressesProvider.setLendingPoolImpl,
      lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl,
      lendingPoolAddressesProvider.setLendingPoolCollateralManager,
      lendingPoolAddressesProvider.setPoolAdmin,
      lendingPoolAddressesProvider.setPriceOracle,
      lendingPoolAddressesProvider.setLendingRateOracle,
    ]) {
      await expect(contractFunction(mockAddress)).to.be.revertedWith("Ownable: caller is not the owner");
    }

    await expect(
      lendingPoolAddressesProvider.setAddress(utils.keccak256(utils.toUtf8Bytes('RANDOM_ID')), mockAddress)
    ).to.be.revertedWith("Ownable: caller is not the owner");

    await expect(
      lendingPoolAddressesProvider.setAddressAsProxy(
        utils.keccak256(utils.toUtf8Bytes('RANDOM_ID')),
        mockAddress
      )
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
});