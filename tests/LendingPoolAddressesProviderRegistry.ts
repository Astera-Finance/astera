import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Wallet } from 'ethers';
import { deployRegistry } from './helpers/test-helpers.ts';

describe('LendingPoolAddressesProviderRegistry', function () {
  let owner;
  let addr1;

  const id = '1';
  const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

  it('getAddressesProvidersList', async function () {
    const registry = await deployRegistry();
    const mockProvider1 = Wallet.createRandom().address;
    const mockProvider2 = Wallet.createRandom().address;

    await registry.registerAddressesProvider(
      mockProvider1,
      id,
    );
    await registry.registerAddressesProvider(
      mockProvider2,
      id,
    );
    let providers = await registry.getAddressesProvidersList();
    expect(providers[0]).to.equal(mockProvider1);
    expect(providers[1]).to.equal(mockProvider2);

    await registry.unregisterAddressesProvider(
      mockProvider1,
    );
    providers = await registry.getAddressesProvidersList();
    expect(providers[0]).to.equal(ZERO_ADDRESS);
    expect(providers[1]).to.equal(mockProvider2);
  });

  it('registerAddressesProvider', async function () {
    const newId = '2';
    const registry = await deployRegistry();
    const mockProvider = Wallet.createRandom().address;

    await expect(
      registry.registerAddressesProvider(
        mockProvider,
        '0',
      ),
    ).to.be.revertedWith('72');

    const tx = await registry.registerAddressesProvider(
      mockProvider,
      id,
    );
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('AddressesProviderRegistered');
    expect(receipt.events[0].args?.newAddress).to.equal(mockProvider);
    expect(
      await registry.getAddressesProviderIdByAddress(
        mockProvider,
      ),
    ).to.equal(id);

    const providers = await registry.getAddressesProvidersList();
    expect(providers.length).to.equal(1);
    expect(providers[0]).to.equal(mockProvider);

    await registry.registerAddressesProvider(
      mockProvider,
      newId,
    );
    expect(
      await registry.getAddressesProviderIdByAddress(
        mockProvider,
      ),
    ).to.equal(newId);
  });

  it('unregisterAddressesProvider', async function () {
    const registry = await deployRegistry();
    const mockProvider = Wallet.createRandom().address;

    await expect(
      registry.unregisterAddressesProvider(
        mockProvider,
      ),
    ).to.be.revertedWith('41');

    await registry.registerAddressesProvider(
      mockProvider,
      id,
    );

    const tx = await registry.unregisterAddressesProvider(
      mockProvider,
    );
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal('AddressesProviderUnregistered');
    expect(receipt.events[0].args?.newAddress).to.equal(mockProvider);
    expect(await registry.getAddressesProviderIdByAddress(
      mockProvider,
    )).to.equal('0');

    const providers = await registry.getAddressesProvidersList();
    expect(providers.length).to.equal(1);
    expect(providers[0]).to.equal(ZERO_ADDRESS);
  });

  it('getAddressesProviderIdByAddress', async function () {
    const registry = await deployRegistry();
    const mockProvider = Wallet.createRandom().address;

    await registry.registerAddressesProvider(
      mockProvider,
      id,
    );
    expect(await registry.getAddressesProviderIdByAddress(
      mockProvider,
    )).to.equal(id);
  });

  it('onlyOwner modifier', async function () {
    [owner, addr1] = await ethers.getSigners();

    const mockProvider = Wallet.createRandom().address;

    const registry = await deployRegistry();
    await registry.transferOwnership(addr1.address);

    await expect(
      registry.registerAddressesProvider(
        mockProvider,
        id,
      ),
    ).to.be.revertedWith('Ownable: caller is not the owner');
    await expect(
      registry.unregisterAddressesProvider(
        mockProvider,
      ),
    ).to.be.revertedWith('Ownable: caller is not the owner');
  });
});
