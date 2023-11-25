import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  deployProtocol,
  deployOracle,
  deployMockAggregator,
} from './helpers/test-helpers.ts';

describe('Oracle', function () {
  const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
  const BASE_CURRENCY_UNIT = '100000000';

  it('Sets fallback oracle', async function () {
    const {
      oracle,
      tokens,
      aggregators,
    } = await loadFixture(deployProtocol);

    const fallbackOracle = await deployOracle(
      tokens,
      aggregators,
      ZERO_ADDRESS, // fall back
      ZERO_ADDRESS, // base currency
      BASE_CURRENCY_UNIT,
    );

    await oracle.setFallbackOracle(fallbackOracle.address);

    expect(
      await oracle.getFallbackOracle(),
    ).to.be.equal(fallbackOracle.address, 'Invalid fallback oracle');
  });

  it('Gets asset price (asset is BASE_CURRENCY)', async function () {
    const USDC_BASE_CURRENCY = '1000000';

    const {
      tokens,
      aggregators,
      usdc,
    } = await loadFixture(deployProtocol);

    const oracle = await deployOracle(
      tokens,
      aggregators,
      ZERO_ADDRESS, // fall back
      usdc.address, // base currency
      USDC_BASE_CURRENCY,
    );

    expect(
      await oracle.getAssetPrice(usdc.address),
    ).to.be.equal(USDC_BASE_CURRENCY, 'Invalid base currency price');
  });

  it('Gets asset price (source is zero-address)', async function () {
    const USDC_PRICE = '100000000';
    const {
      oracle,
      tokens,
      aggregators,
      usdc,
    } = await loadFixture(deployProtocol);

    await oracle.setAssetSources([usdc.address], [ZERO_ADDRESS]);

    expect(
      await oracle.getSourceOfAsset(usdc.address),
    ).to.be.equal(ZERO_ADDRESS, 'Invalid oracle address');

    const fallbackOracle = await deployOracle(
      tokens,
      aggregators,
      ZERO_ADDRESS, // fall back
      ZERO_ADDRESS, // base currency
      BASE_CURRENCY_UNIT,
    );

    await oracle.setFallbackOracle(fallbackOracle.address);

    expect(
      await oracle.getAssetPrice(usdc.address),
    ).to.be.equal(USDC_PRICE, 'Invalid fallback price');
  });

  it('Gets asset price (if price is 0)', async function () {
    const ZERO = '0';
    const NEW_USDC_PRICE = '101000000';
    const {
      oracle,
      usdc,
    } = await loadFixture(deployProtocol);

    const zeroUSDCFeed = await deployMockAggregator(ZERO, '6');
    await oracle.setAssetSources([usdc.address], [zeroUSDCFeed.address]);

    await expect(oracle.getAssetPrice(usdc.address)).to.be.reverted;

    const newUSDCFeed = await deployMockAggregator(NEW_USDC_PRICE, '6');
    const fallbackOracle = await deployOracle(
      [usdc.address],
      [newUSDCFeed.address],
      ZERO_ADDRESS, // fall back
      ZERO_ADDRESS, // base currency
      BASE_CURRENCY_UNIT,
    );

    await oracle.setFallbackOracle(fallbackOracle.address);

    expect(
      await oracle.getAssetPrice(usdc.address),
    ).to.be.equal(NEW_USDC_PRICE, 'Invalid fallback price');
  });
});
