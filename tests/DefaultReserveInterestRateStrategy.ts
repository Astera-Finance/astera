import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  deployProtocol,
  percentMul,
} from './helpers/test-helpers.ts';

describe('DefaultReserveInterestRateStrategy', function () {
  const PERCENTAGE_FACTOR = BigNumber.from('10000');

  it('Checks rates at 0% utilization rate, empty reserve', async function () {
    const {
      stableStrategy,
      usdc,
      grainUSDC,
      protocolDataProvider,
    } = await loadFixture(deployProtocol);

    const usdcReserveConfig = await protocolDataProvider.getReserveConfigurationData(
      usdc.address,
      false,
    );
    const usdcReserveFactor = usdcReserveConfig.reserveFactor;

    const {
      0: currentLiquidityRate,
      1: currentVariableBorrowRate,
    } = await stableStrategy['calculateInterestRates(address,address,uint256,uint256,uint256,uint256)'](
      usdc.address,
      grainUSDC.address,
      '0',
      '0',
      '0',
      usdcReserveFactor,
    );

    expect(currentLiquidityRate).to.be.equal('0', 'Invalid liquidity rate');
    expect(currentVariableBorrowRate).to.be.equal('0', 'Invalid variable borrow rate');
  });

  it('Checks rates at 80% utilization rate', async function () {
    const {
      stableStrategy,
      usdc,
      grainUSDC,
      protocolDataProvider,
    } = await loadFixture(deployProtocol);

    const usdcReserveConfig = await protocolDataProvider.getReserveConfigurationData(
      usdc.address,
      false,
    );
    const usdcReserveFactor = usdcReserveConfig.reserveFactor;

    const {
      0: currentLiquidityRate,
      1: currentVariableBorrowRate,
    } = await stableStrategy['calculateInterestRates(address,address,uint256,uint256,uint256,uint256)'](
      usdc.address,
      grainUSDC.address,
      '200000000000000000',
      '0',
      '800000000000000000',
      usdcReserveFactor,
    );

    const baseVariableBorrowRate = await stableStrategy.baseVariableBorrowRate();
    const variableRateSlope1 = await stableStrategy.variableRateSlope1();
    const expectedVariableRate = baseVariableBorrowRate.add(variableRateSlope1);

    const value = expectedVariableRate.mul('80').div('100');
    const percentage = PERCENTAGE_FACTOR.sub(usdcReserveFactor);
    const expectedLiquidityRate = await percentMul(value, percentage);

    expect(currentLiquidityRate).to.be.equal(expectedLiquidityRate, 'Invalid liquidity rate');
    expect(currentVariableBorrowRate).to.be.equal(expectedVariableRate, 'Invalid variable borrow rate');
  });

  it('Checks rates at 100% utilization rate', async function () {
    const {
      stableStrategy,
      usdc,
      grainUSDC,
      protocolDataProvider,
    } = await loadFixture(deployProtocol);

    const usdcReserveConfig = await protocolDataProvider.getReserveConfigurationData(
      usdc.address,
      false,
    );
    const usdcReserveFactor = usdcReserveConfig.reserveFactor;

    const {
      0: currentLiquidityRate,
      1: currentVariableBorrowRate,
    } = await stableStrategy['calculateInterestRates(address,address,uint256,uint256,uint256,uint256)'](
      usdc.address,
      grainUSDC.address,
      '0',
      '0',
      '800000000000000000',
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
    expect(currentVariableBorrowRate).to.be.equal(expectedVariableRate, 'Invalid variable borrow rate');
  });
});
