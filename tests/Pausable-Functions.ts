import { expect } from "chai";
import hre from "hardhat";
import { Wallet, utils, BigNumber } from "ethers"; 
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { 
  deployProtocol,
  prepareMockTokens,
  approve,
  deposit,
  withdraw,
  borrow,
  repay,
  deployMockFlashLoanReceiver,
  setUserUseReserveAsCollateral,
  deployMockAggregator,
  setAssetSources
} from "./helpers/test-helpers";

describe("Pausable-Functions", function () {
  let owner, addr1, addr2, addr3, depositor, borrower, liquidator;

  it("Tries to transfer grainToken while LendingPool is paused", async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);

    const { usdc, grainUSDC, lendingPoolProxy, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);

    await approve(lendingPoolProxy.address, usdc, addr1);

    const usdcDeposit = await deposit(lendingPoolProxy, addr1, usdc.address, false, USDC_DEPOSIT_SIZE, addr1.address);
    const addr1Balance = await grainUSDC.balanceOf(addr1.address);
    const addr2Balance = await grainUSDC.balanceOf(addr2.address);

    await lendingPoolConfiguratorProxy.setPoolPause(true);

    await expect(
      grainUSDC.connect(addr1).transfer(addr2.address, USDC_DEPOSIT_SIZE)
    ).to.revertedWith("64");

    const pausedFromBalance = await grainUSDC.balanceOf(addr1.address);
    const pausedToBalance = await grainUSDC.balanceOf(addr2.address);

    expect(pausedFromBalance).to.be.equal(addr1Balance);
    expect(pausedToBalance).to.be.equal(addr2Balance);

    await lendingPoolConfiguratorProxy.setPoolPause(false);

    grainUSDC.connect(addr1).transfer(addr2.address, USDC_DEPOSIT_SIZE);

    const fromBalance = await grainUSDC.balanceOf(addr1.address);
    const toBalance = await grainUSDC.balanceOf(addr2.address);

    expect(fromBalance).to.be.equal(addr1Balance.sub(USDC_DEPOSIT_SIZE));
    expect(toBalance).to.be.equal(addr2Balance.add(USDC_DEPOSIT_SIZE));
  });

  it("Deposit", async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);

    const { usdc, lendingPoolProxy, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
    await approve(lendingPoolProxy.address, usdc, addr1);

    await lendingPoolConfiguratorProxy.setPoolPause(true);

    await expect(
      deposit(lendingPoolProxy, addr1, usdc.address, false, USDC_DEPOSIT_SIZE, addr1.address)
    ).to.revertedWith("64");
  });

  it("Withdraw", async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);
    
    const { usdc, lendingPoolProxy, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
    await approve(lendingPoolProxy.address, usdc, addr1);
    await deposit(lendingPoolProxy, addr1, usdc.address, false, USDC_DEPOSIT_SIZE, addr1.address);
    await lendingPoolConfiguratorProxy.setPoolPause(true);

    await expect(
      withdraw(lendingPoolProxy, addr1, usdc.address, false,USDC_DEPOSIT_SIZE, addr1.address)
    ).to.revertedWith("64");
  });

  it("Borrow", async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);
    const USDC_BORROW_SIZE = ethers.utils.parseUnits("15", 6);

    const { usdc, lendingPoolProxy, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
    await approve(lendingPoolProxy.address, usdc, addr1);
    await deposit(lendingPoolProxy, addr1, usdc.address, false, USDC_DEPOSIT_SIZE, addr1.address);
    await lendingPoolConfiguratorProxy.setPoolPause(true);

    await expect(
      borrow(lendingPoolProxy, addr1, usdc.address, false, USDC_BORROW_SIZE, addr1.address)
    ).to.revertedWith("64");
  });

  it("Repay", async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);
    const USDC_BORROW_SIZE = ethers.utils.parseUnits("16", 6);

    const { usdc, lendingPoolProxy, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
    await approve(lendingPoolProxy.address, usdc, addr1);
    await deposit(lendingPoolProxy, addr1, usdc.address, false, USDC_DEPOSIT_SIZE, addr1.address);
    await borrow(lendingPoolProxy, addr1, usdc.address, false, USDC_BORROW_SIZE, addr1.address)

    await lendingPoolConfiguratorProxy.setPoolPause(true);

    await expect(
      repay(lendingPoolProxy, addr1, usdc.address, false, USDC_BORROW_SIZE, addr1.address)
    ).to.revertedWith("64");
  });


  it("Flash loan", async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    const FLASH_LOAN_SIZE = ethers.utils.parseEther("0.8");

    const { weth, lendingPoolProxy, lendingPoolConfiguratorProxy, lendingPoolAddressesProvider } = await loadFixture(deployProtocol);

    let mockFlashLoanReceiver = await deployMockFlashLoanReceiver(lendingPoolAddressesProvider.address);

    await mockFlashLoanReceiver.setFailExecutionTransfer(true);
    await lendingPoolConfiguratorProxy.setPoolPause(true);

    const flashloanParams = {
      receiverAddress: mockFlashLoanReceiver.address,
      assets: [weth.address],
      reserveTypes: [false],
      onBehalfOf: owner.address,
      referralCode: '0'
    };

    await expect(
      lendingPoolProxy.flashLoan(
          flashloanParams,
          [FLASH_LOAN_SIZE],
          [1],
          '0x10'
        )
    ).revertedWith("64");
  });


  it("Liquidation call", async function () {
    [owner, depositor, borrower, liquidator] = await ethers.getSigners();
    const USDC_DEPOSIT_SIZE = ethers.utils.parseUnits("1000", 6);
    const WETH_DEPOSIT_SIZE = ethers.utils.parseEther("1");


    const { usdc, weth, usdcPriceFeed, ethPriceFeed, lendingPoolProxy, lendingPoolConfiguratorProxy, oracle, protocolDataProvider } = await loadFixture(deployProtocol);

    await prepareMockTokens(usdc, depositor, USDC_DEPOSIT_SIZE);
    await approve(lendingPoolProxy.address, usdc, depositor);
    await deposit(lendingPoolProxy, depositor, usdc.address, false, USDC_DEPOSIT_SIZE, depositor.address);

    await prepareMockTokens(weth, borrower, WETH_DEPOSIT_SIZE);
    await approve(lendingPoolProxy.address, weth, borrower);
    await deposit(lendingPoolProxy, borrower, weth.address, false, WETH_DEPOSIT_SIZE, borrower.address);

    const userGlobalData = await lendingPoolProxy.getUserAccountData(borrower.address);

    const wethDepositValue = (WETH_DEPOSIT_SIZE).mul(await ethPriceFeed.latestAnswer());
    const wethLTV = (await protocolDataProvider.getReserveConfigurationData(weth.address, false)).ltv;
    const wethMaxBorrowValue = wethDepositValue.mul(wethLTV).div(10000).div(ethers.utils.parseEther("1"));
    const maxUsdcBorrow = wethMaxBorrowValue.div((await usdcPriceFeed.latestAnswer()).div(ethers.utils.parseUnits("1", 6)));

    await lendingPoolProxy.connect(borrower).borrow(usdc.address, false, maxUsdcBorrow, "2", "0", borrower.address);

    let newUsdcPriceFeed = await deployMockAggregator("120000000", usdc.decimals());
    await setAssetSources(oracle, owner, [usdc.address], [newUsdcPriceFeed.address])

    await prepareMockTokens(usdc, liquidator, USDC_DEPOSIT_SIZE);
    await approve(lendingPoolProxy.address, usdc, liquidator);

    const userReserveDataBefore = await protocolDataProvider.getUserReserveData(
      usdc.address,
      false,
      borrower.address
    );

    const amountToLiquidate = userReserveDataBefore.currentVariableDebt.div(2);

    await lendingPoolConfiguratorProxy.setPoolPause(true);

    await expect(
      lendingPoolProxy.liquidationCall(weth.address, false, usdc.address, false, borrower.address, amountToLiquidate, true)
    ).revertedWith("64");
  });

  it("setUserUseReserveAsCollateral", async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    const USDC_DEPOSIT_SIZE = ethers.utils.parseEther("1");

    const { usdc, lendingPoolProxy, lendingPoolConfiguratorProxy } = await loadFixture(deployProtocol);

    await prepareMockTokens(usdc, addr1, USDC_DEPOSIT_SIZE);
    await approve(lendingPoolProxy.address, usdc, addr1);
    await deposit(lendingPoolProxy, addr1, usdc.address, false, USDC_DEPOSIT_SIZE, addr1.address);

    await lendingPoolConfiguratorProxy.setPoolPause(true);

    await expect(
      setUserUseReserveAsCollateral(lendingPoolProxy, addr1, usdc.address, false, false)
    ).to.revertedWith("64");
  });
});