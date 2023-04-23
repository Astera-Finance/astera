import { expect } from "chai";
import hre from "hardhat";
import { Wallet, utils } from "ethers"; 
import { deployLendingPoolAddressesProviderRegistry } from "./helpers/test-helpers";

describe("LendingPoolAddressesProviderRegistry", function () {
  let id = "1";
  let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

  it("getAddressesProvidersList", async function () {
    const lendingPoolAddressesProviderRegistry = await deployLendingPoolAddressesProviderRegistry();
    const mockLendingPoolAddressesProvider1 = Wallet.createRandom().address;
    const mockLendingPoolAddressesProvider2 = Wallet.createRandom().address;

    await lendingPoolAddressesProviderRegistry.registerAddressesProvider(mockLendingPoolAddressesProvider1, id);
    await lendingPoolAddressesProviderRegistry.registerAddressesProvider(mockLendingPoolAddressesProvider2, id);
    let providers = await lendingPoolAddressesProviderRegistry.getAddressesProvidersList();
    expect(providers[0]).to.equal(mockLendingPoolAddressesProvider1);
    expect(providers[1]).to.equal(mockLendingPoolAddressesProvider2);

    await lendingPoolAddressesProviderRegistry.unregisterAddressesProvider(mockLendingPoolAddressesProvider1);
    providers = await lendingPoolAddressesProviderRegistry.getAddressesProvidersList();
    expect(providers[0]).to.equal(ZERO_ADDRESS);
    expect(providers[1]).to.equal(mockLendingPoolAddressesProvider2);
  });

  it("registerAddressesProvider", async function () {
  	const newId = "2";
    const lendingPoolAddressesProviderRegistry = await deployLendingPoolAddressesProviderRegistry();
    const mockLendingPoolAddressesProvider = Wallet.createRandom().address;

    await expect(
      lendingPoolAddressesProviderRegistry.registerAddressesProvider(mockLendingPoolAddressesProvider, "0")
    ).to.be.revertedWith("72");

    const tx = await lendingPoolAddressesProviderRegistry.registerAddressesProvider(mockLendingPoolAddressesProvider, id);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("AddressesProviderRegistered");
    expect(receipt.events[0].args?.newAddress).to.equal(mockLendingPoolAddressesProvider);
    expect(
    	await lendingPoolAddressesProviderRegistry.getAddressesProviderIdByAddress(mockLendingPoolAddressesProvider)
	).to.equal(id);
    
    const providers = await lendingPoolAddressesProviderRegistry.getAddressesProvidersList();
    expect(providers.length).to.equal(1);
    expect(providers[0]).to.equal(mockLendingPoolAddressesProvider);

	await lendingPoolAddressesProviderRegistry.registerAddressesProvider(mockLendingPoolAddressesProvider, newId);
    expect(
    	await lendingPoolAddressesProviderRegistry.getAddressesProviderIdByAddress(mockLendingPoolAddressesProvider)
	).to.equal(newId);
  });

  it("unregisterAddressesProvider", async function () {
    const lendingPoolAddressesProviderRegistry = await deployLendingPoolAddressesProviderRegistry();
    const mockLendingPoolAddressesProvider = Wallet.createRandom().address;

    await expect(
      lendingPoolAddressesProviderRegistry.unregisterAddressesProvider(mockLendingPoolAddressesProvider)
    ).to.be.revertedWith("41");

    await lendingPoolAddressesProviderRegistry.registerAddressesProvider(mockLendingPoolAddressesProvider, id);

    const tx = await lendingPoolAddressesProviderRegistry.unregisterAddressesProvider(mockLendingPoolAddressesProvider);
    const receipt = await tx.wait();
    expect(receipt.events[0].event).to.equal("AddressesProviderUnregistered");
    expect(receipt.events[0].args?.newAddress).to.equal(mockLendingPoolAddressesProvider);
    expect(await lendingPoolAddressesProviderRegistry.getAddressesProviderIdByAddress(mockLendingPoolAddressesProvider)).to.equal("0");

    const providers = await lendingPoolAddressesProviderRegistry.getAddressesProvidersList();
    expect(providers.length).to.equal(1);
    expect(providers[0]).to.equal(ZERO_ADDRESS);
  });

  it("getAddressesProviderIdByAddress", async function () {
    const lendingPoolAddressesProviderRegistry = await deployLendingPoolAddressesProviderRegistry();
    const mockLendingPoolAddressesProvider = Wallet.createRandom().address;

    await lendingPoolAddressesProviderRegistry.registerAddressesProvider(mockLendingPoolAddressesProvider, id);
    expect(await lendingPoolAddressesProviderRegistry.getAddressesProviderIdByAddress(mockLendingPoolAddressesProvider)).to.equal(id);
  });

  it("onlyOwner modifier", async function () {
    let owner, account0;
    [owner, account0] = await ethers.getSigners();

    const mockLendingPoolAddressesProvider = Wallet.createRandom().address;

    const lendingPoolAddressesProviderRegistry = await deployLendingPoolAddressesProviderRegistry();
    await lendingPoolAddressesProviderRegistry.transferOwnership(account0.address);

    await expect(
      lendingPoolAddressesProviderRegistry.registerAddressesProvider(mockLendingPoolAddressesProvider, id)
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      lendingPoolAddressesProviderRegistry.unregisterAddressesProvider(mockLendingPoolAddressesProvider)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
});