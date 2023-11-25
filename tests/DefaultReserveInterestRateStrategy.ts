import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  deployProtocol,
  percentMul,
} from './helpers/test-helpers.ts';

describe('DefaultReserveInterestRateStrategy', function () {
  const PERCENTAGE_FACTOR = BigNumber.from('10000');

  // Checks rates at 0% utilization rate, empty reserve
  it('Checks rates at 0% utilization rate, empty reserve', async function () {
    const {
      stableStrategy,
      usdc,
      grainUSDC,
      protocolDataProvider,
      lendingRateOracle,
    } = await loadFixture(deployProtocol);

    const usdcReserveConfig = await protocolDataProvider.getReserveConfigurationData(
      usdc.address,
      false,
    );
    const usdcReserveFactor = usdcReserveConfig.reserveFactor;
    const usdcStableBorrowRate = await lendingRateOracle.getMarketBorrowRate(usdc.address);

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await stableStrategy['calculateInterestRates(address,address,uint256,uint256,uint256,uint256,uint256,uint256)'](
      usdc.address,
      grainUSDC.address,
      '0',
      '0',
      '0',
      '0',
      '0',
      usdcReserveFactor,
    );

    expect(currentLiquidityRate).to.be.equal('0', 'Invalid liquidity rate');
    expect(currentStableBorrowRate).to.be.equal(usdcStableBorrowRate, 'Invalid stable borrow rate');
    expect(currentVariableBorrowRate).to.be.equal('0', 'Invalid variable borrow rate');
  });

  // Checks rates at 80% utilization rate
  it('Checks rates at 80% utilization rate', async function () {
    const {
      stableStrategy,
      usdc,
      grainUSDC,
      protocolDataProvider,
      lendingRateOracle,
    } = await loadFixture(deployProtocol);

    const usdcReserveConfig = await protocolDataProvider.getReserveConfigurationData(
      usdc.address,
      false,
    );
    const usdcReserveFactor = usdcReserveConfig.reserveFactor;
    const usdcStableBorrowRate = await lendingRateOracle.getMarketBorrowRate(usdc.address);

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await stableStrategy['calculateInterestRates(address,address,uint256,uint256,uint256,uint256,uint256,uint256)'](
      usdc.address,
      grainUSDC.address,
      '200000000000000000',
      '0',
      '0',
      '800000000000000000',
      '0',
      usdcReserveFactor,
    );

    const baseVariableBorrowRate = await stableStrategy.baseVariableBorrowRate();
    const variableRateSlope1 = await stableStrategy.variableRateSlope1();
    const expectedVariableRate = baseVariableBorrowRate.add(variableRateSlope1);

    const value = expectedVariableRate.mul('80').div('100');
    const percentage = PERCENTAGE_FACTOR.sub(usdcReserveFactor);
    const expectedLiquidityRate = await percentMul(value, percentage);

    expect(currentLiquidityRate).to.be.equal(expectedLiquidityRate, 'Invalid liquidity rate');
    expect(currentStableBorrowRate).to.be.equal(usdcStableBorrowRate, 'Invalid stable borrow rate');
    expect(currentVariableBorrowRate).to.be.equal(expectedVariableRate, 'Invalid variable borrow rate');
  });

  // Checks rates at 100% utilization rate
  it('Checks rates at 100% utilization rate', async function () {
    const {
      stableStrategy,
      usdc,
      grainUSDC,
      protocolDataProvider,
      lendingRateOracle,
    } = await loadFixture(deployProtocol);

    const usdcReserveConfig = await protocolDataProvider.getReserveConfigurationData(
      usdc.address,
      false,
    );
    const usdcReserveFactor = usdcReserveConfig.reserveFactor;
    const usdcStableBorrowRate = await lendingRateOracle.getMarketBorrowRate(usdc.address);

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await stableStrategy['calculateInterestRates(address,address,uint256,uint256,uint256,uint256,uint256,uint256)'](
      usdc.address,
      grainUSDC.address,
      '0',
      '0',
      '0',
      '800000000000000000',
      '0',
      usdcReserveFactor,
    );

    const baseVariableBorrowRate = await stableStrategy.baseVariableBorrowRate();
    const variableRateSlope1 = await stableStrategy.variableRateSlope1();
    const variableRateSlope2 = await stableStrategy.variableRateSlope2();
    const expectedVariableRate = baseVariableBorrowRate
      .add(variableRateSlope1)
      .add(variableRateSlope2);

    const value = expectedVariableRate;
    const percentage = PERCENTAGE_FACTOR.sub(usdcReserveFactor);
    const expectedLiquidityRate = await percentMul(value, percentage);

    expect(currentLiquidityRate).to.be.equal(expectedLiquidityRate, 'Invalid liquidity rate');
    expect(currentStableBorrowRate).to.be.equal(usdcStableBorrowRate, 'Invalid stable borrow rate');
    expect(currentVariableBorrowRate).to.be.equal(expectedVariableRate, 'Invalid variable borrow rate');
  });

  // Checks rates at 100% utilization rate, 50% stable debt and 50% variable debt, with a 10% avg stable rate
  it('Checks rates at 100% utilization rate, 50% stable debt and 50% variable debt, with a 10% avg stable rate', async function () {
    const {
      stableStrategy,
      usdc,
      grainUSDC,
      protocolDataProvider,
      lendingRateOracle,
    } = await loadFixture(deployProtocol);

    const averageStableBorrowRate = BigNumber.from('100000000000000000000000000');
    const usdcReserveConfig = await protocolDataProvider.getReserveConfigurationData(
      usdc.address,
      false,
    );
    const usdcReserveFactor = usdcReserveConfig.reserveFactor;
    const usdcStableBorrowRate = await lendingRateOracle.getMarketBorrowRate(usdc.address);

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await stableStrategy['calculateInterestRates(address,address,uint256,uint256,uint256,uint256,uint256,uint256)'](
      usdc.address,
      grainUSDC.address,
      '0',
      '0',
      '400000000000000000',
      '400000000000000000',
      averageStableBorrowRate,
      usdcReserveFactor,
    );

    const baseVariableBorrowRate = await stableStrategy.baseVariableBorrowRate();
    const variableRateSlope1 = await stableStrategy.variableRateSlope1();
    const variableRateSlope2 = await stableStrategy.variableRateSlope2();
    const expectedVariableRate = baseVariableBorrowRate
      .add(variableRateSlope1)
      .add(variableRateSlope2);

    const value = currentVariableBorrowRate.add(averageStableBorrowRate).div('2');
    const percentage = PERCENTAGE_FACTOR.sub(usdcReserveFactor);
    const expectedLiquidityRate = await percentMul(value, percentage);

    expect(currentLiquidityRate).to.be.equal(expectedLiquidityRate, 'Invalid liquidity rate');
    expect(currentStableBorrowRate).to.be.equal(usdcStableBorrowRate, 'Invalid stable borrow rate');
    expect(currentVariableBorrowRate).to.be.equal(expectedVariableRate, 'Invalid variable borrow rate');
  });
});
