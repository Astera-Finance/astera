import { expect } from "chai";
import hre from "hardhat";
import { Wallet, utils, BigNumber } from "ethers"; 
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { 
  deployProtocol,
  prepareMockTokens,
  approve,
  depositETH,
  withdrawETH,
  borrowETH,
  repayETH,
  approveDelegation,
  prepareMockTokens,
  transfer,
  emergencyTokenTransfer,
  emergencyEtherTransfer,
  deploySelfdestructTransfer,
  destroyAndTransfer
} from "./helpers/test-helpers";

describe("WETHGateway", function () {
  let owner, addr1, addr2, addr3;

  it("depositETH", async function () {
    [owner, addr1] = await ethers.getSigners();
    const ETH_DEPOSIT_SIZE = ethers.utils.parseUnits("1", 18);

    const { grainETH, lendingPoolProxy, wETHGateway } = await loadFixture(deployProtocol);

    const ethDeposit = await depositETH(wETHGateway, addr1, lendingPoolProxy.address, false, ETH_DEPOSIT_SIZE, addr1.address);
    expect(await grainETH.balanceOf(addr1.address)).to.equal(ETH_DEPOSIT_SIZE);
  });

  it("withdrawETH", async function () {
    [owner, addr1] = await ethers.getSigners();
    const ETH_DEPOSIT_SIZE = ethers.utils.parseUnits("1", 18);
    const { grainETH, lendingPoolProxy, wETHGateway } = await loadFixture(deployProtocol);

    const depositTx = await depositETH(wETHGateway, owner, lendingPoolProxy.address, false, ETH_DEPOSIT_SIZE, owner.address);

    const priorEthersBalance = await owner.getBalance();

    const approveTx = await approve(wETHGateway.address, grainETH, owner);
    const { gasUsed: approveGas } = approveTx.receipt;
    const approveGasCost = approveGas.mul(approveTx.gasPrice);

    const withdrawalTx = await withdrawETH(wETHGateway, owner, lendingPoolProxy.address, false, ETH_DEPOSIT_SIZE, owner.address);
    const { gasUsed: withdrawalGas } = withdrawalTx.receipt;
    const withdrawalGasCost = withdrawalGas.mul(withdrawalTx.gasPrice);

    const afterEthersBalance = await owner.getBalance();

    const gasCost = approveGasCost.add(withdrawalGasCost);

    expect(await grainETH.balanceOf(owner.address)).to.equal("0");
    expect(afterEthersBalance).to.equal(
      priorEthersBalance.add(ETH_DEPOSIT_SIZE).sub(gasCost)
    );
  });

  it("borrowETH", async function () {
    [owner, addr1] = await ethers.getSigners();
    const ETH_DEPOSIT_SIZE = ethers.utils.parseUnits("1", 18);
    const { weth, variableDebtETH, lendingPoolProxy, wETHGateway, protocolDataProvider } = await loadFixture(deployProtocol);

    await depositETH(wETHGateway, owner, lendingPoolProxy.address, false, ETH_DEPOSIT_SIZE, owner.address);

    const priorEthersBalance = await owner.getBalance();

    const ethLTV = (await protocolDataProvider.getReserveConfigurationData(weth.address, false)).ltv;
    const ethMaxBorrowNative = ETH_DEPOSIT_SIZE.mul(ethLTV).div(10000);

    const approveTx = await approveDelegation(variableDebtETH, owner, wETHGateway.address, ethMaxBorrowNative);
    const { gasUsed: approveGas } = approveTx.receipt;
    const approveGasCost = approveGas.mul(approveTx.gasPrice);

    const borrowTx = await borrowETH(wETHGateway, owner, lendingPoolProxy.address, false, ethMaxBorrowNative);
    const { gasUsed: borrowGas } = borrowTx.receipt;
    const borrowGasCost = borrowGas.mul(borrowTx.gasPrice);

    const afterEthersBalance = await owner.getBalance();

    const gasCost = approveGasCost.add(borrowGasCost);

    expect(await variableDebtETH.balanceOf(owner.address)).to.equal(ethMaxBorrowNative);
    expect(afterEthersBalance).to.equal(
      priorEthersBalance.add(ethMaxBorrowNative).sub(gasCost)
    );
  });

  it("repayETH", async function () {
    [owner, addr1] = await ethers.getSigners();
    const ETH_DEPOSIT_SIZE = ethers.utils.parseUnits("1", 18);
    const { weth, variableDebtETH, lendingPoolProxy, wETHGateway, protocolDataProvider } = await loadFixture(deployProtocol);

    await depositETH(wETHGateway, owner, lendingPoolProxy.address, false, ETH_DEPOSIT_SIZE, owner.address);

    const priorEthersBalance = await owner.getBalance();

    const ethLTV = (await protocolDataProvider.getReserveConfigurationData(weth.address, false)).ltv;
    const ethMaxBorrowNative = ETH_DEPOSIT_SIZE.mul(ethLTV).div(10000);

    const approveTx = await approveDelegation(variableDebtETH, owner, wETHGateway.address, ethMaxBorrowNative);
    const { gasUsed: approveGas } = approveTx.receipt;
    const approveGasCost = approveGas.mul(approveTx.gasPrice);

    const borrowTx = await borrowETH(wETHGateway, owner, lendingPoolProxy.address, false, ethMaxBorrowNative);
    const { gasUsed: borrowGas } = borrowTx.receipt;
    const borrowGasCost = borrowGas.mul(borrowTx.gasPrice);

    const beforeRepay = await owner.getBalance();
    const repayTx = await repayETH(wETHGateway, owner, lendingPoolProxy.address, false, ethMaxBorrowNative.mul(2), owner.address);
    const { gasUsed: repayGas } = repayTx.receipt;
    const repayGasCost = repayGas.mul(repayTx.gasPrice);

    const repaidAmount = beforeRepay.sub(await owner.getBalance()).sub(repayGasCost);
    const accruedDebt = repaidAmount.sub(ethMaxBorrowNative);

    const afterEthersBalance = await owner.getBalance();

    const gasCost = approveGasCost.add(borrowGasCost).add(repayGasCost);

    expect(await variableDebtETH.balanceOf(owner.address)).to.equal("0");
    expect(afterEthersBalance).to.equal(
      priorEthersBalance.sub(gasCost).sub(accruedDebt)
    );
  });

  it("Should revert if receiver function receives Ether if not WETH", async function () {
    [owner, addr1] = await ethers.getSigners();
    const { wETHGateway } = await loadFixture(deployProtocol);
    const amount = ethers.utils.parseEther("1");

    await expect(
      owner.sendTransaction({
        to: wETHGateway.address,
        value: amount      
      })
    ).to.be.revertedWith('Receive not allowed');
  });

  it("Should revert if fallback functions is called with Ether", async function () {
    [owner, addr1] = await ethers.getSigners();
    const { wETHGateway } = await loadFixture(deployProtocol);
    const amount = ethers.utils.parseEther("1");
    const fakeABI = ['function wantToCallFallback()'];
    const abiCoder = new hre.ethers.utils.Interface(fakeABI);
    const fakeMethodEncoded = abiCoder.encodeFunctionData('wantToCallFallback', []);

    await expect(
      owner.sendTransaction({
        to: wETHGateway.address,
        data: fakeMethodEncoded,
        value: amount
      })
    ).to.be.revertedWith('Fallback not allowed');
  });

  it("Should revert if fallback functions is called", async function () {
    [owner, addr1] = await ethers.getSigners();
    const { wETHGateway } = await loadFixture(deployProtocol);
    const fakeABI = ['function wantToCallFallback()'];
    const abiCoder = new hre.ethers.utils.Interface(fakeABI);
    const fakeMethodEncoded = abiCoder.encodeFunctionData('wantToCallFallback', []);

    await expect(
      owner.sendTransaction({
        to: wETHGateway.address,
        data: fakeMethodEncoded
      })
    ).to.be.revertedWith('Fallback not allowed');
  });

  it("emergencyTokenTransfer", async function () {
    [owner, addr1] = await ethers.getSigners();
    const { usdc, wETHGateway } = await loadFixture(deployProtocol);
    const amount = ethers.utils.parseUnits("100", 6);
    
    await prepareMockTokens(usdc, owner, amount);
    expect(await usdc.balanceOf(owner.address)).to.equal(amount);

    await transfer(usdc, owner, wETHGateway.address, amount);
    expect(await usdc.balanceOf(wETHGateway.address)).to.equal(amount);
    expect(await usdc.balanceOf(owner.address)).to.equal("0");

    await emergencyTokenTransfer(wETHGateway, owner, usdc.address, owner.address, amount);
    expect(await usdc.balanceOf(owner.address)).to.equal(amount);
    expect(await usdc.balanceOf(wETHGateway.address)).to.equal("0");
  });

  it("emergencyEtherTransfer", async function () {
    [owner, addr1] = await ethers.getSigners();
    const { wETHGateway } = await loadFixture(deployProtocol);
    const amount = ethers.utils.parseEther("1");

    const selfdestructContract = await deploySelfdestructTransfer();
    const priorEthersBalance = await owner.getBalance();

    const callTx = await destroyAndTransfer(selfdestructContract, owner, wETHGateway.address, amount);
    const { gasUsed: destoryGas } = callTx.receipt;
    const destoryGasCost = destoryGas.mul(callTx.gasPrice);
    expect(await owner.getBalance()).to.equal(priorEthersBalance.sub(amount).sub(destoryGasCost));

    const transferTx = await emergencyEtherTransfer(wETHGateway, owner, owner.address, amount);
    const { gasUsed: transferGas } = transferTx.receipt;
    const transferGasCost = transferGas.mul(transferTx.gasPrice);
    expect(await owner.getBalance()).to.equal(priorEthersBalance.sub(destoryGasCost).sub(transferGasCost));
    expect(await hre.ethers.provider.getBalance(wETHGateway.address)).to.equal("0");
  });
});