import express from 'express';
import request from 'supertest';
import feesRouter from '../src/api/routes/fees';
import rewardsRouter from '../src/api/routes/rewards';
import { makeTestConfig } from '../src/config';
import { query } from '../src/db/client';

jest.mock('../src/db/client', () => ({
  query: jest.fn(),
}));

const mockedQuery = query as jest.Mock;

function createApp(router: express.Router, path: string) {
  return express().use(path, router);
}

describe('economics data availability', () => {
  beforeEach(() => mockedQuery.mockReset());

  test('fee totals stay unavailable before full index coverage', async () => {
    mockedQuery.mockResolvedValueOnce({
      rows: [{ id: 1, tx_hash: '0xabc', block_number: 1 }],
      rowCount: 1,
    });
    const app = createApp(
      feesRouter(makeTestConfig(), {
        getSyncStatus: jest.fn().mockResolvedValue({
          latestIndexed: 1,
          chainHead: 10,
          isSynced: false,
        }),
      } as never),
      '/fees',
    );

    const response = await request(app).get('/fees');
    expect(response.status).toBe(200);
    expect(response.body.data.summary).toBeNull();
    expect(response.body.data.events).toHaveLength(1);
  });

  test('fee totals preserve configured, synchronized zero values', async () => {
    mockedQuery
      .mockResolvedValueOnce({
        rows: [{
          total_distributed: '0',
          total_validator: '0',
          total_treasury: '0',
          total_burn: '0',
          event_count: '0',
        }],
        rowCount: 1,
      })
      .mockResolvedValueOnce({ rows: [], rowCount: 0 });
    const app = createApp(
      feesRouter(makeTestConfig(), {
        getSyncStatus: jest.fn().mockResolvedValue({
          latestIndexed: 10,
          chainHead: 10,
          isSynced: true,
        }),
      } as never),
      '/fees',
    );

    const response = await request(app).get('/fees');
    expect(response.status).toBe(200);
    expect(response.body.data.summary).toMatchObject({
      total_distributed: '0',
      total_validator: '0',
      total_treasury: '0',
      total_burn: '0',
    });
  });

  test('reward endpoints distinguish unavailable contract data from an empty history', async () => {
    const config = makeTestConfig({
      contracts: {
        ...makeTestConfig().contracts,
        rewardVault: null,
      },
    });
    const app = createApp(
      rewardsRouter(config, {
        getSyncStatus: jest.fn().mockResolvedValue({
          latestIndexed: 10,
          chainHead: 10,
          isSynced: true,
        }),
      } as never),
      '/rewards',
    );

    const overview = await request(app).get('/rewards');
    const address = await request(app).get(`/rewards/0x${'11'.repeat(20)}`);
    expect(overview.body.data).toEqual({
      latestState: null,
      totalClaimed: null,
      emissionRate: null,
    });
    expect(address.body.data).toEqual({
      available: false,
      totalClaimed: null,
      events: [],
    });
    expect(mockedQuery).not.toHaveBeenCalled();
  });
});
