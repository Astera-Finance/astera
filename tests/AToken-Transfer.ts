import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  deployProtocol,
  deposit,
  borrow,
} from './helpers/test-helpers.ts';

describe('AToken-Transfer', function () {
  let owner;
  let addr1;

  it('User 0 deposits 1000 USDC, transfers to user 1', async function () {
    const DEPOSIT_AMOUNT = ethers.utils.parseUnits('100', 6);
    [owner, addr1] = await ethers.getSigners();

    const {
      usdc,
      grainUSDC,
      lendingPoolProxy,
    } = await loadFixture(deployProtocol);

    await usdc.mint(DEPOSIT_AMOUNT);
    await usdc.approve(lendingPoolProxy.address, DEPOSIT_AMOUNT);

    await deposit(
      lendingPoolProxy,
      owner,
      usdc.address,
      false,
      DEPOSIT_AMOUNT,
      owner.address,
    );

    await grainUSDC.transfer(addr1.address, DEPOSIT_AMOUNT);

    const fromBalance = await grainUSDC.balanceOf(owner.address);
    const toBalance = await grainUSDC.balanceOf(addr1.address);

    expect(fromBalance).to.be.equal('0', 'Invalid from balance after transfer');
    expect(toBalance).to.be.equal(DEPOSIT_AMOUNT, 'Invalid to balance after transfer');
  });

  it('User 0 deposits 1 WETH and user 1 tries to borrow the WETH with the received USDC as collateral', async function () {
    const USDC_DEPOSIT_AMOUNT = ethers.utils.parseUnits('10000', 6);
    const ETH_DEPOSIT_AMOUNT = ethers.utils.parseUnits('1', 18);

    [owner, addr1] = await ethers.getSigners();

    const {
      usdc,
      grainUSDC,
      weth,
      grainETH,
      lendingPoolProxy,
    } = await loadFixture(deployProtocol);

    await usdc.mint(USDC_DEPOSIT_AMOUNT);
    await usdc.approve(lendingPoolProxy.address, USDC_DEPOSIT_AMOUNT);

    await deposit(
      lendingPoolProxy,
      owner,
      usdc.address,
      false,
      USDC_DEPOSIT_AMOUNT,
      owner.address,
    );

    await grainUSDC.transfer(addr1.address, USDC_DEPOSIT_AMOUNT);

    await weth.connect(owner).mint(ETH_DEPOSIT_AMOUNT);
    await weth.connect(owner).approve(lendingPoolProxy.address, ETH_DEPOSIT_AMOUNT);

    await deposit(
      lendingPoolProxy,
      owner,
      weth.address,
      false,
      ETH_DEPOSIT_AMOUNT,
      owner.address,
    );

    await borrow(
      lendingPoolProxy,
      addr1,
      weth.address,
      false,
      ETH_DEPOSIT_AMOUNT,
      addr1.address,
    );

    const depositorBalance = await grainETH.balanceOf(owner.address);
    const borrowerBalance = await weth.balanceOf(addr1.address);
    expect(depositorBalance).to.be.equal(ETH_DEPOSIT_AMOUNT, 'Invalid depositor balance after transfer');
    expect(borrowerBalance).to.be.equal(ETH_DEPOSIT_AMOUNT, 'Invalid borrower balance after transfer');
  });

  it('User 1 tries to transfer all the USDC used as collateral back to user 0 (revert expected)', async function () {
    const USDC_DEPOSIT_AMOUNT = ethers.utils.parseUnits('10000', 6);
    const ETH_DEPOSIT_AMOUNT = ethers.utils.parseUnits('1', 18);

    [owner, addr1] = await ethers.getSigners();

    const {
      usdc,
      grainUSDC,
      weth,
      lendingPoolProxy,
    } = await loadFixture(deployProtocol);

    await usdc.mint(USDC_DEPOSIT_AMOUNT);
    await usdc.approve(lendingPoolProxy.address, USDC_DEPOSIT_AMOUNT);

    await deposit(
      lendingPoolProxy,
      owner,
      usdc.address,
      false,
      USDC_DEPOSIT_AMOUNT,
      owner.address,
    );

    await grainUSDC.transfer(addr1.address, USDC_DEPOSIT_AMOUNT);

    await weth.connect(owner).mint(ETH_DEPOSIT_AMOUNT);
    await weth.connect(owner).approve(lendingPoolProxy.address, ETH_DEPOSIT_AMOUNT);

    await deposit(
      lendingPoolProxy,
      owner,
      weth.address,
      false,
      ETH_DEPOSIT_AMOUNT,
      owner.address,
    );

    await borrow(
      lendingPoolProxy,
      addr1,
      weth.address,
      false,
      ETH_DEPOSIT_AMOUNT,
      addr1.address,
    );

    await expect(
      grainUSDC.connect(addr1).transfer(owner.address, USDC_DEPOSIT_AMOUNT),
    ).to.be.revertedWith(
      '6',
      'Invalid Transfer With Active Borrow',
    );
  });

  it('User 1 tries to transfer a small amount of USDC used as collateral back to user 0', async function () {
    const USDC_DEPOSIT_AMOUNT = ethers.utils.parseUnits('10000', 6);
    const ETH_DEPOSIT_AMOUNT = ethers.utils.parseUnits('1', 18);
    const SMALL_TRANSFER_AMOUNT = ethers.utils.parseUnits('1000', 6);

    [owner, addr1] = await ethers.getSigners();

    const {
      usdc,
      grainUSDC,
      weth,
      lendingPoolProxy,
    } = await loadFixture(deployProtocol);

    await usdc.mint(USDC_DEPOSIT_AMOUNT);
    await usdc.approve(lendingPoolProxy.address, USDC_DEPOSIT_AMOUNT);

    await deposit(
      lendingPoolProxy,
      owner,
      usdc.address,
      false,
      USDC_DEPOSIT_AMOUNT,
      owner.address,
    );

    await grainUSDC.transfer(addr1.address, USDC_DEPOSIT_AMOUNT);

    await weth.connect(owner).mint(ETH_DEPOSIT_AMOUNT);
    await weth.connect(owner).approve(lendingPoolProxy.address, ETH_DEPOSIT_AMOUNT);

    await deposit(
      lendingPoolProxy,
      owner,
      weth.address,
      false,
      ETH_DEPOSIT_AMOUNT,
      owner.address,
    );

    await borrow(
      lendingPoolProxy,
      addr1,
      weth.address,
      false,
      ETH_DEPOSIT_AMOUNT,
      addr1.address,
    );

    await grainUSDC.connect(addr1).transfer(owner.address, SMALL_TRANSFER_AMOUNT);

    const toBalance = await grainUSDC.balanceOf(owner.address);
    const expectedFromBalance = USDC_DEPOSIT_AMOUNT.sub(SMALL_TRANSFER_AMOUNT);
    const fromBalance = await grainUSDC.balanceOf(addr1.address);
    expect(toBalance).to.be.equal(SMALL_TRANSFER_AMOUNT, 'Invalid balance after transfer');
    expect(fromBalance).to.be.equal(expectedFromBalance, 'Invalid balance after transfer');
  });
});
