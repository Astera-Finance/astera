import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  deployProtocol,
  prepareMockTokens,
  approve,
  deposit,
  withdraw,
  borrow,
  repay,
  setUserUseReserveAsCollateral,
} from './helpers/test-helpers.ts';

describe('LendingPool', function () {
  let owner;
  let addr1;

  it('deposit', async function () {
    [owner, addr1] = await ethers.getSigners();
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits('1', 6);
    const WBTC_DEPOSIT_SIZE = ethers.utils.parseUnits('1', 8);
    const WETH_DEPOSIT_SIZE = ethers.utils.parseUnits('1', 18);

    const {
      usdc,
      wbtc,
      weth,
      grainUSDC,
      grainWBTC,
      grainETH,
      lendingPoolProxy,
    } = await loadFixture(deployProtocol);

    await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
    await prepareMockTokens(wbtc, addr1, WBTC_DEPOSIT_SIZE);
    await prepareMockTokens(weth, addr1, WETH_DEPOSIT_SIZE);

    await approve(lendingPoolProxy.address, usdc, addr1);
    await approve(lendingPoolProxy.address, wbtc, addr1);
    await approve(lendingPoolProxy.address, weth, addr1);

    const usdcDeposit = await deposit(
      lendingPoolProxy,
      addr1,
      usdc.address,
      false,
      USDC_DEPOSIT_SIZE,
      addr1.address,
    );

    expect(usdcDeposit.events[6].event).to.equal('Deposit');
    expect(usdcDeposit.events[6].args?.reserve).to.equal(usdc.address);
    expect(usdcDeposit.events[6].args?.user).to.equal(addr1.address);
    expect(usdcDeposit.events[6].args?.onBehalfOf).to.equal(addr1.address);
    expect(usdcDeposit.events[6].args?.amount).to.equal(USDC_DEPOSIT_SIZE);
    expect(await grainUSDC.balanceOf(addr1.address)).to.equal(USDC_DEPOSIT_SIZE);

    const wbtcDeposit = await deposit(
      lendingPoolProxy,
      addr1,
      wbtc.address,
      false,
      WBTC_DEPOSIT_SIZE,
      addr1.address,
    );
    expect(wbtcDeposit.events[6].event).to.equal('Deposit');
    expect(wbtcDeposit.events[6].args?.reserve).to.equal(wbtc.address);
    expect(wbtcDeposit.events[6].args?.user).to.equal(addr1.address);
    expect(wbtcDeposit.events[6].args?.onBehalfOf).to.equal(addr1.address);
    expect(wbtcDeposit.events[6].args?.amount).to.equal(WBTC_DEPOSIT_SIZE);
    expect(await grainWBTC.balanceOf(addr1.address)).to.equal(WBTC_DEPOSIT_SIZE);

    const wethDeposit = await deposit(
      lendingPoolProxy,
      addr1,
      weth.address,
      false,
      WETH_DEPOSIT_SIZE,
      addr1.address,
    );
    expect(wethDeposit.events[5].event).to.equal('Deposit');
    expect(wethDeposit.events[5].args?.reserve).to.equal(weth.address);
    expect(wethDeposit.events[5].args?.user).to.equal(addr1.address);
    expect(wethDeposit.events[5].args?.onBehalfOf).to.equal(addr1.address);
    expect(wethDeposit.events[5].args?.amount).to.equal(WETH_DEPOSIT_SIZE);
    expect(await grainETH.balanceOf(addr1.address)).to.equal(WETH_DEPOSIT_SIZE);
  });

  it('withdraw', async function () {
    [owner, addr1] = await ethers.getSigners();
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits('1', 6);
    const WBTC_DEPOSIT_SIZE = ethers.utils.parseUnits('1', 8);
    const WETH_DEPOSIT_SIZE = ethers.utils.parseUnits('1', 18);

    const {
      usdc,
      wbtc,
      weth,
      grainUSDC,
      grainWBTC,
      grainETH,
      lendingPoolProxy,
    } = await loadFixture(deployProtocol);

    await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
    await prepareMockTokens(wbtc, addr1, WBTC_DEPOSIT_SIZE);
    await prepareMockTokens(weth, addr1, WETH_DEPOSIT_SIZE);

    await approve(lendingPoolProxy.address, usdc, addr1);
    await approve(lendingPoolProxy.address, wbtc, addr1);
    await approve(lendingPoolProxy.address, weth, addr1);

    await deposit(lendingPoolProxy, addr1, usdc.address, false, USDC_DEPOSIT_SIZE, addr1.address);
    await deposit(lendingPoolProxy, addr1, wbtc.address, false, WBTC_DEPOSIT_SIZE, addr1.address);
    await deposit(lendingPoolProxy, addr1, weth.address, false, WETH_DEPOSIT_SIZE, addr1.address);

    const usdcWithdrawal = await withdraw(
      lendingPoolProxy,
      addr1,
      usdc.address,
      false,
      USDC_DEPOSIT_SIZE,
      addr1.address,
    );
    expect(usdcWithdrawal.events[5].event).to.equal('Withdraw');
    expect(usdcWithdrawal.events[5].args?.reserve).to.equal(usdc.address);
    expect(usdcWithdrawal.events[5].args?.user).to.equal(addr1.address);
    expect(usdcWithdrawal.events[5].args?.to).to.equal(addr1.address);
    expect(usdcWithdrawal.events[5].args?.amount).to.equal(USDC_DEPOSIT_SIZE);
    expect(await grainUSDC.balanceOf(addr1.address)).to.equal('0');
    expect(await usdc.balanceOf(addr1.address)).to.equal(USDC_DEPOSIT_SIZE);

    const wbtcWithdrawal = await withdraw(
      lendingPoolProxy,
      addr1,
      wbtc.address,
      false,
      WBTC_DEPOSIT_SIZE,
      addr1.address,
    );
    expect(wbtcWithdrawal.events[5].event).to.equal('Withdraw');
    expect(wbtcWithdrawal.events[5].args?.reserve).to.equal(wbtc.address);
    expect(wbtcWithdrawal.events[5].args?.user).to.equal(addr1.address);
    expect(wbtcWithdrawal.events[5].args?.to).to.equal(addr1.address);
    expect(wbtcWithdrawal.events[5].args?.amount).to.equal(WBTC_DEPOSIT_SIZE);
    expect(await grainWBTC.balanceOf(addr1.address)).to.equal('0');
    expect(await wbtc.balanceOf(addr1.address)).to.equal(WBTC_DEPOSIT_SIZE);

    const wethWithdrawal = await withdraw(
      lendingPoolProxy,
      addr1,
      weth.address,
      false,
      WETH_DEPOSIT_SIZE,
      addr1.address,
    );
    expect(wethWithdrawal.events[5].event).to.equal('Withdraw');
    expect(wethWithdrawal.events[5].args?.reserve).to.equal(weth.address);
    expect(wethWithdrawal.events[5].args?.user).to.equal(addr1.address);
    expect(wethWithdrawal.events[5].args?.to).to.equal(addr1.address);
    expect(wethWithdrawal.events[5].args?.amount).to.equal(WETH_DEPOSIT_SIZE);
    expect(await grainETH.balanceOf(addr1.address)).to.equal('0');
    expect(await weth.balanceOf(addr1.address)).to.equal(WETH_DEPOSIT_SIZE);
  });

  it('borrow', async function () {
    [owner, addr1] = await ethers.getSigners();
    const VARIABLE_RATE_MODE = '2';
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits('1000', 6);
    const WBTC_DEPOSIT_SIZE = ethers.utils.parseUnits('1', 8);

    const {
      usdc,
      wbtc,
      variableDebtWBTC,
      lendingPoolProxy,
      usdcPriceFeed,
      wbtcPriceFeed,
      protocolDataProvider,
    } = await loadFixture(deployProtocol);

    const usdcDepositValue = (USDC_DEPOSIT_SIZE).mul(await usdcPriceFeed.latestAnswer());

    const usdcLTV = (
      await protocolDataProvider.getReserveConfigurationData(
        usdc.address,
        false,
      )
    ).ltv;

    // const usdcMaxBorrowNative = (USDC_DEPOSIT_SIZE * (usdcLTV / 10000));

    const usdcMaxBorrowValue = usdcDepositValue.mul(usdcLTV).div(10000).div(ethers.utils.parseUnits('1', 6));

    const maxBitcoinBorrow = usdcMaxBorrowValue.div((await wbtcPriceFeed.latestAnswer()).div(ethers.utils.parseUnits('1', 8)));

    await prepareMockTokens(usdc, owner, USDC_DEPOSIT_SIZE);
    await prepareMockTokens(wbtc, addr1, WBTC_DEPOSIT_SIZE);

    await approve(lendingPoolProxy.address, usdc, owner);
    await approve(lendingPoolProxy.address, wbtc, addr1);

    await deposit(lendingPoolProxy, owner, usdc.address, false, USDC_DEPOSIT_SIZE, owner.address);
    await deposit(lendingPoolProxy, addr1, wbtc.address, false, WBTC_DEPOSIT_SIZE, addr1.address);

    // owner deposits 1000 USDC ($1,000), addr1 deposits 1 WBTC ($16,000)
    const wbtcBorrow = await borrow(
      lendingPoolProxy,
      owner,
      wbtc.address,
      false,
      maxBitcoinBorrow,
      owner.address,
    );
    expect(wbtcBorrow.events[4].event).to.equal('Borrow');
    expect(wbtcBorrow.events[4].args?.reserve).to.equal(wbtc.address);
    expect(wbtcBorrow.events[4].args?.user).to.equal(owner.address);
    expect(wbtcBorrow.events[4].args?.onBehalfOf).to.equal(owner.address);
    expect(wbtcBorrow.events[4].args?.amount).to.equal(maxBitcoinBorrow);
    expect(wbtcBorrow.events[4].args?.borrowRateMode).to.equal(VARIABLE_RATE_MODE);
    expect(await variableDebtWBTC.balanceOf(owner.address)).to.equal(maxBitcoinBorrow);
    expect(await wbtc.balanceOf(owner.address)).to.equal(maxBitcoinBorrow);
  });

  it('repay', async function () {
    [owner, addr1] = await ethers.getSigners();
    // const VARIABLE_RATE_MODE = '2';
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits('1000', 6);
    const WBTC_DEPOSIT_SIZE = ethers.utils.parseUnits('1', 8);

    const {
      usdc,
      wbtc,
      variableDebtWBTC,
      lendingPoolProxy,
      usdcPriceFeed,
      wbtcPriceFeed,
      protocolDataProvider,
    } = await loadFixture(deployProtocol);

    const usdcDepositValue = (USDC_DEPOSIT_SIZE).mul(await usdcPriceFeed.latestAnswer());

    const usdcLTV = (
      await protocolDataProvider.getReserveConfigurationData(
        usdc.address,
        false,
      )
    ).ltv;

    // const usdcMaxBorrowNative = (USDC_DEPOSIT_SIZE * (usdcLTV / 10000));

    const usdcMaxBorrowValue = usdcDepositValue.mul(usdcLTV).div(10000).div(ethers.utils.parseUnits('1', 6));

    const maxBitcoinBorrow = usdcMaxBorrowValue.div((await wbtcPriceFeed.latestAnswer()).div(ethers.utils.parseUnits('1', 8)));

    await prepareMockTokens(usdc, owner, USDC_DEPOSIT_SIZE);
    await prepareMockTokens(wbtc, addr1, WBTC_DEPOSIT_SIZE);

    await approve(lendingPoolProxy.address, usdc, owner);
    await approve(lendingPoolProxy.address, wbtc, addr1);

    await deposit(lendingPoolProxy, owner, usdc.address, false, USDC_DEPOSIT_SIZE, owner.address);
    await deposit(lendingPoolProxy, addr1, wbtc.address, false, WBTC_DEPOSIT_SIZE, addr1.address);

    // owner deposits 1000 USDC ($1,000), addr1 deposits 1 WBTC ($16,000)
    await borrow(
      lendingPoolProxy,
      owner,
      wbtc.address,
      false,
      maxBitcoinBorrow,
      owner.address,
    );

    await approve(lendingPoolProxy.address, wbtc, owner);

    const wbtcRepay = await repay(
      lendingPoolProxy,
      owner,
      wbtc.address,
      false,
      maxBitcoinBorrow,
      owner.address,
    );
    expect(await variableDebtWBTC.balanceOf(owner.address)).to.equal('0');
    expect(await wbtc.balanceOf(owner.address)).to.equal('0');
    expect(wbtcRepay.events[5].event).to.equal('Repay');
    expect(wbtcRepay.events[5].args?.reserve).to.equal(wbtc.address);
    expect(wbtcRepay.events[5].args?.user).to.equal(owner.address);
    expect(wbtcRepay.events[5].args?.repayer).to.equal(owner.address);
    expect(wbtcRepay.events[5].args?.amount).to.equal(maxBitcoinBorrow);
  });

  it('setUserUseReserveAsCollateral', async function () {
    [owner, addr1] = await ethers.getSigners();
    const VARIABLE_RATE_MODE = '2';
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits('1000', 6);
    const WBTC_DEPOSIT_SIZE = ethers.utils.parseUnits('1', 8);

    const {
      usdc,
      wbtc,
      variableDebtWBTC,
      lendingPoolProxy,
      usdcPriceFeed,
      wbtcPriceFeed,
      protocolDataProvider,
    } = await loadFixture(deployProtocol);

    const usdcDepositValue = (USDC_DEPOSIT_SIZE).mul(await usdcPriceFeed.latestAnswer());

    const usdcLTV = (
      await protocolDataProvider.getReserveConfigurationData(
        usdc.address,
        false,
      )
    ).ltv;

    // const usdcMaxBorrowNative = (USDC_DEPOSIT_SIZE * (usdcLTV / 10000));

    const usdcMaxBorrowValue = usdcDepositValue.mul(usdcLTV).div(10000).div(ethers.utils.parseUnits('1', 6));

    const maxBitcoinBorrow = usdcMaxBorrowValue.div((await wbtcPriceFeed.latestAnswer()).div(ethers.utils.parseUnits('1', 8)));

    await prepareMockTokens(usdc, owner, USDC_DEPOSIT_SIZE);
    await prepareMockTokens(wbtc, addr1, WBTC_DEPOSIT_SIZE);

    await approve(lendingPoolProxy.address, usdc, owner);
    await approve(lendingPoolProxy.address, wbtc, addr1);

    await deposit(lendingPoolProxy, owner, usdc.address, false, USDC_DEPOSIT_SIZE, owner.address);
    await deposit(lendingPoolProxy, addr1, wbtc.address, false, WBTC_DEPOSIT_SIZE, addr1.address);

    const collateralDisabled = await setUserUseReserveAsCollateral(
      lendingPoolProxy,
      owner,
      usdc.address,
      false,
      false,
    );
    expect(collateralDisabled.events[0].event).to.equal('ReserveUsedAsCollateralDisabled');
    expect(collateralDisabled.events[0].args?.reserve).to.equal(usdc.address);
    expect(collateralDisabled.events[0].args?.user).to.equal(owner.address);

    await expect(
      borrow(lendingPoolProxy, owner, wbtc.address, false, maxBitcoinBorrow, owner.address),
    ).to.be.revertedWith('9');

    const collateralEnabled = await setUserUseReserveAsCollateral(
      lendingPoolProxy,
      owner,
      usdc.address,
      false,
      true,
    );
    expect(collateralEnabled.events[0].event).to.equal('ReserveUsedAsCollateralEnabled');
    expect(collateralEnabled.events[0].args?.reserve).to.equal(usdc.address);
    expect(collateralEnabled.events[0].args?.user).to.equal(owner.address);

    const wbtcBorrow = await borrow(
      lendingPoolProxy,
      owner,
      wbtc.address,
      false,
      maxBitcoinBorrow,
      owner.address,
    );
    expect(wbtcBorrow.events[4].event).to.equal('Borrow');
    expect(wbtcBorrow.events[4].args?.reserve).to.equal(wbtc.address);
    expect(wbtcBorrow.events[4].args?.user).to.equal(owner.address);
    expect(wbtcBorrow.events[4].args?.onBehalfOf).to.equal(owner.address);
    expect(wbtcBorrow.events[4].args?.amount).to.equal(maxBitcoinBorrow);
    expect(wbtcBorrow.events[4].args?.borrowRateMode).to.equal(VARIABLE_RATE_MODE);
    expect(await variableDebtWBTC.balanceOf(owner.address)).to.equal(maxBitcoinBorrow);
    expect(await wbtc.balanceOf(owner.address)).to.equal(maxBitcoinBorrow);
  });
});
