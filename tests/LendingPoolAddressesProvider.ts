import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Wallet, utils } from 'ethers';
import {
  deployProvider,
  deployLendingPool,
  deployConfigurator,
  deployCollateralManager,
} from './helpers/test-helpers.ts';

describe('LendingPoolAddressesProvider', function () {
  let owner;
  let addr1;
  const marketId = 'Granary Genesis Market';

  it('getMarketId', async function () {
    const provider = await deployProvider(marketId);
    expect(await provider.getMarketId()).to.equal(marketId);
  });

  it('setMarketId', async function () {
    const defaultMarketId = 'Granary Genesis Market';
    const newMarketId = 'Granary Halo Market';

    const provider = await deployProvider(defaultMarketId);
    expect(await provider.getMarketId()).to.equal(defaultMarketId);

    const tx = await provider.setMarketId(newMarketId);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('MarketIdSet');
    expect(receipt.events[0].args?.newMarketId).to.equal(newMarketId);
    expect(await provider.getMarketId()).to.equal(newMarketId);
  });

  it('setAddressAsProxy', async function () {
    const proxiedAddressId = utils.keccak256(utils.toUtf8Bytes('RANDOM_PROXIED'));

    const provider = await deployProvider(marketId);
    const lendingPool = await deployLendingPool();

    const tx = await provider.setAddressAsProxy(
      proxiedAddressId,
      lendingPool.address,
    );
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('ProxyCreated');
    expect(receipt.events[1].event).to.equal('AddressSet');
    expect(receipt.events[1].args?.id).to.equal(proxiedAddressId);
    expect(receipt.events[1].args?.newAddress).to.equal(lendingPool.address);
    expect(receipt.events[1].args?.hasProxy).to.equal(true);
  });

  it('setAddress', async function () {
    const nonProxiedAddressId = utils.keccak256(utils.toUtf8Bytes('RANDOM_NON_PROXIED'));
    const mockAddress = Wallet.createRandom().address;

    const provider = await deployProvider(marketId);

    const tx = await provider.setAddress(nonProxiedAddressId, mockAddress);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('AddressSet');
    expect(receipt.events[0].args?.id).to.equal(nonProxiedAddressId);
    expect(receipt.events[0].args?.newAddress).to.equal(mockAddress);
    expect(receipt.events[0].args?.hasProxy).to.equal(false);
    expect(mockAddress.toLowerCase()).to.equal(
      (await provider.getAddress(nonProxiedAddressId)).toLowerCase(),
    );
  });

  it('getAddress', async function () {
    const nonProxiedAddressId = utils.keccak256(utils.toUtf8Bytes('RANDOM_NON_PROXIED'));
    const mockAddress = Wallet.createRandom().address;

    const provider = await deployProvider(marketId);

    await provider.setAddress(nonProxiedAddressId, mockAddress);
    expect(
      await provider.getAddress(nonProxiedAddressId),
    ).to.equal(mockAddress);
  });

  it('getLendingPool', async function () {
    const provider = await deployProvider(marketId);
    const lendingPool = await deployLendingPool();

    const tx = await provider.setLendingPoolImpl(lendingPool.address);
    const receipt = await tx.wait();
    expect(
      await provider.getLendingPool(),
    ).to.equal(receipt.events[0].args?.newAddress);
  });

  it('setLendingPoolImpl', async function () {
    const provider = await deployProvider(marketId);
    const lendingPool = await deployLendingPool();

    const tx = await provider.setLendingPoolImpl(lendingPool.address);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('ProxyCreated');
    expect(receipt.events[1].event).to.equal('LendingPoolUpdated');
    expect(receipt.events[1].args?.newAddress).to.equal(lendingPool.address);
  });

  it('getLendingPoolConfigurator', async function () {
    const provider = await deployProvider(marketId);
    const configurator = await deployConfigurator();

    const tx = await provider.setLendingPoolConfiguratorImpl(
      configurator.address,
    );
    const receipt = await tx.wait();
    expect(
      await provider.getLendingPoolConfigurator(),
    ).to.equal(receipt.events[0].args?.newAddress);
  });

  it('setLendingPoolConfiguratorImpl', async function () {
    const provider = await deployProvider(marketId);
    const configurator = await deployConfigurator();

    const tx = await provider.setLendingPoolConfiguratorImpl(
      configurator.address,
    );
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('ProxyCreated');
    expect(receipt.events[1].event).to.equal('LendingPoolConfiguratorUpdated');
    expect(receipt.events[1].args?.newAddress).to.equal(configurator.address);
  });

  it('getLendingPoolCollateralManager', async function () {
    const provider = await deployProvider(marketId);
    const lendingPoolCollateralManager = await deployCollateralManager();

    const tx = await provider.setLendingPoolCollateralManager(
      lendingPoolCollateralManager.address,
    );
    const receipt = await tx.wait();
    expect(
      await provider.getLendingPoolCollateralManager(),
    ).to.equal(receipt.events[0].args?.newAddress);
  });

  it('setLendingPoolCollateralManager', async function () {
    const provider = await deployProvider(marketId);
    const lendingPoolCollateralManager = await deployCollateralManager();

    const tx = await provider.setLendingPoolCollateralManager(
      lendingPoolCollateralManager.address,
    );
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('LendingPoolCollateralManagerUpdated');
    expect(receipt.events[0].args?.newAddress).to.equal(lendingPoolCollateralManager.address);
  });

  it('getPoolAdmin', async function () {
    const mockAddress = Wallet.createRandom().address;

    const provider = await deployProvider(marketId);

    const tx = await provider.setPoolAdmin(mockAddress);
    const receipt = await tx.wait();
    expect(
      await provider.getPoolAdmin(),
    ).to.equal(receipt.events[0].args?.newAddress);
  });

  it('setPoolAdmin', async function () {
    const mockAddress = Wallet.createRandom().address;

    const provider = await deployProvider(marketId);

    const tx = await provider.setPoolAdmin(mockAddress);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('ConfigurationAdminUpdated');
    expect(receipt.events[0].args?.newAddress).to.equal(mockAddress);
  });

  it('getEmergencyAdmin', async function () {
    const mockAddress = Wallet.createRandom().address;

    const provider = await deployProvider(marketId);

    const tx = await provider.setEmergencyAdmin(mockAddress);
    const receipt = await tx.wait();
    expect(
      await provider.getEmergencyAdmin(),
    ).to.equal(receipt.events[0].args?.newAddress);
  });

  it('setEmergencyAdmin', async function () {
    const mockAddress = Wallet.createRandom().address;

    const provider = await deployProvider(marketId);

    const tx = await provider.setEmergencyAdmin(mockAddress);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('EmergencyAdminUpdated');
    expect(receipt.events[0].args?.newAddress).to.equal(mockAddress);
  });

  it('getPriceOracle', async function () {
    const mockPriceOracle = Wallet.createRandom().address;

    const provider = await deployProvider(marketId);

    const tx = await provider.setPriceOracle(mockPriceOracle);
    const receipt = await tx.wait();
    expect(
      await provider.getPriceOracle(),
    ).to.equal(receipt.events[0].args?.newAddress);
  });

  it('setPriceOracle', async function () {
    const mockPriceOracle = Wallet.createRandom().address;

    const provider = await deployProvider(marketId);

    const tx = await provider.setPriceOracle(mockPriceOracle);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('PriceOracleUpdated');
    expect(receipt.events[0].args?.newAddress).to.equal(mockPriceOracle);
  });
  it('onlyOwner modifier', async function () {
    [owner, addr1] = await ethers.getSigners();

    const mockAddress = Wallet.createRandom().address;

    const provider = await deployProvider(marketId);
    await provider.transferOwnership(addr1.address);

    for (const contractFunction of [
      provider.setMarketId,
      provider.setLendingPoolImpl,
      provider.setLendingPoolConfiguratorImpl,
      provider.setLendingPoolCollateralManager,
      provider.setPoolAdmin,
      provider.setPriceOracle
    ]) {
      await expect(
        contractFunction(mockAddress),
      ).to.be.revertedWith('Ownable: caller is not the owner');
    }

    await expect(
      provider.setAddress(
        utils.keccak256(utils.toUtf8Bytes('RANDOM_ID')),
        mockAddress,
      ),
    ).to.be.revertedWith('Ownable: caller is not the owner');

    await expect(
      provider.setAddressAsProxy(
        utils.keccak256(utils.toUtf8Bytes('RANDOM_ID')),
        mockAddress,
      ),
    ).to.be.revertedWith('Ownable: caller is not the owner');
  });
});
