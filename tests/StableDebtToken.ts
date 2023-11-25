import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  deployProtocol,
} from './helpers/test-helpers.ts';

describe('StableDebtToken', function () {
  let owner;

  it('Tries to invoke mint not being the LendingPool', async function () {
    [owner] = await ethers.getSigners();

    const {
      stableDebtUSDC,
    } = await loadFixture(deployProtocol);

    await expect(stableDebtUSDC.mint(owner.address, owner.address, '1', '1')).to.be.revertedWith(
      '29',
    );
  });

  it('Tries to invoke burn not being the LendingPool', async function () {
    [owner] = await ethers.getSigners();

    const {
      stableDebtUSDC,
    } = await loadFixture(deployProtocol);

    await expect(stableDebtUSDC.burn(owner.address, '1')).to.be.revertedWith(
      '29',
    );
  });
});
