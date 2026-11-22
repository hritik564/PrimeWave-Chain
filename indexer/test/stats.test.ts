import express from 'express';
import request from 'supertest';
import statsRouter from '../src/api/routes/stats';
import { makeTestConfig } from '../src/config';

jest.mock('../src/db/client', () => ({
  query: jest.fn(),
}));

import { query } from '../src/db/client';

const mockedQuery = query as jest.Mock;

function mockEmptyStatsRows() {
  mockedQuery
    .mockResolvedValueOnce({ rows: [], rowCount: 0 })
    .mockResolvedValueOnce({ rows: [{ count: '0' }], rowCount: 1 })
    .mockResolvedValueOnce({ rows: [{ count: '0' }], rowCount: 1 })
    .mockResolvedValueOnce({ rows: [], rowCount: 0 })
    .mockResolvedValueOnce({ rows: [{ total: '0' }], rowCount: 1 })
    .mockResolvedValueOnce({ rows: [{ total: '0' }], rowCount: 1 });
}

describe('stats availability and zero values', () => {
  afterEach(() => jest.clearAllMocks());

  test('returns unavailable economics when corresponding contracts are not configured', async () => {
    mockEmptyStatsRows();
    const config = makeTestConfig({
      contracts: {
        ...makeTestConfig().contracts,
        rewardVault: null,
        feeDistributor: null,
      },
    });
    const engine = { getSyncStatus: jest.fn().mockResolvedValue({
      latestIndexed: -1,
      chainHead: 0,
      isSynced: false,
    }) };

    const response = await request(express().use(
      '/stats',
      statsRouter(config, engine as never),
    )).get('/stats');

    expect(response.status).toBe(200);
    expect(response.body.data.rewardVault).toEqual({
      totalFunded: null,
      totalEmitted: null,
      emissionRate: null,
    });
    expect(response.body.data.fees).toEqual({
      totalDistributed: null,
      totalToValidators: null,
    });
    expect(response.body.data.gas).toEqual({
      gasUsedLatestBlock: null,
      gasLimitLatestBlock: null,
    });
  });

  test('preserves genuine zero economic values when contracts are configured', async () => {
    mockedQuery
      .mockResolvedValueOnce({
        rows: [{
          number: 0,
          timestamp_unix: 0,
          transaction_count: 0,
          gas_used: '0',
          gas_limit: '0',
        }],
        rowCount: 1,
      })
      .mockResolvedValueOnce({ rows: [{ count: '0' }], rowCount: 1 })
      .mockResolvedValueOnce({ rows: [{ count: '0' }], rowCount: 1 })
      .mockResolvedValueOnce({
        rows: [{ total_funded: '0', total_emitted: '0', emission_rate: '0' }],
        rowCount: 1,
      })
      .mockResolvedValueOnce({ rows: [{ total: '0' }], rowCount: 1 })
      .mockResolvedValueOnce({ rows: [{ total: '0' }], rowCount: 1 })
      .mockResolvedValueOnce({ rows: [{ tx_count: '0', block_count: '1' }], rowCount: 1 });

    const response = await request(express().use(
      '/stats',
      statsRouter(makeTestConfig(), {
        getSyncStatus: jest.fn().mockResolvedValue({
          latestIndexed: 0,
          chainHead: 0,
          isSynced: true,
        }),
      } as never),
    )).get('/stats');

    expect(response.status).toBe(200);
    expect(response.body.data.rewardVault).toEqual({
      totalFunded: '0',
      totalEmitted: '0',
      emissionRate: '0',
    });
    expect(response.body.data.fees).toEqual({
      totalDistributed: '0',
      totalToValidators: '0',
    });
    expect(response.body.data.network).toMatchObject({
      currentBlock: 0,
      isSynced: true,
    });
    expect(response.body.data.transactions).toMatchObject({
      total: '0',
      inLatestBlock: 0,
      tps_60s: 0,
    });
  });
});
