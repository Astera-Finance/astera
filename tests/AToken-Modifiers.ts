import { expect } from "chai";
import hre from "hardhat";
import { Wallet, utils, BigNumber } from "ethers"; 
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployProtocol } from "./helpers/test-helpers";

describe("AToken-Modifiers", function () {
  let owner, addr1, addr2, addr3;

  it("Tries to invoke mint not being the LendingPool", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { grainUSDC } = await loadFixture(deployProtocol);

    await expect(grainUSDC.mint(owner.address, '1', '1')).to.be.revertedWith(
      "29"
    );
  });

  it("Tries to invoke burn not being the LendingPool", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { grainUSDC } = await loadFixture(deployProtocol);

    await expect(grainUSDC.burn(owner.address, owner.address, '1', '1')).to.be.revertedWith(
      "29"
    );
  });

  it("Tries to invoke transferOnLiquidation not being the LendingPool", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { grainUSDC } = await loadFixture(deployProtocol);

    await expect(grainUSDC.transferOnLiquidation(owner.address, addr1.address, '1')).to.be.revertedWith(
      "29"
    );
  });

  it("Tries to invoke transferUnderlyingTo not being the LendingPool", async function () {
    [owner, addr1] = await ethers.getSigners();

    const { grainUSDC } = await loadFixture(deployProtocol);

    await expect(grainUSDC.transferUnderlyingTo(owner.address, '1')).to.be.revertedWith(
      "29"
    );
  });

  // it("Tries to set a vault to the AToken not being the LendingPool", async function () {
  //   [owner, addr1] = await ethers.getSigners();
  //   const { grainUSDC, mockUsdcErc4626 } = await loadFixture(deployProtocol);
  //   await expect(grainUSDC.setVault(mockUsdcErc4626.address)).to.be.revertedWith(
  //     "29"
  //   );
  // });
});