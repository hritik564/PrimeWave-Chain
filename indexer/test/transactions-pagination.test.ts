import express from 'express';
import request from 'supertest';
import transactionsRouter from '../src/api/routes/transactions';
import addressesRouter from '../src/api/routes/addresses';
import { makeTestConfig } from '../src/config';
import { ValidationError } from '../src/api/validation';

jest.mock('../src/db/client', () => ({
  query: jest.fn(),
}));

import { query } from '../src/db/client';

const mockedQuery = query as jest.Mock;
const address = `0x${'11'.repeat(20)}`;

function createApp() {
  const app = express();
  const config = makeTestConfig();
  app.use('/transactions', transactionsRouter(config));
  app.use('/addresses', addressesRouter(config));
  app.use((error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    res.status(error instanceof ValidationError ? 400 : 500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Unexpected error',
    });
  });
  return app;
}

describe('composite transaction pagination', () => {
  beforeEach(() => mockedQuery.mockReset());

  test('keeps transactions from the same block in subsequent pages', async () => {
    mockedQuery.mockResolvedValueOnce({
      rows: [{
        hash: `0x${'aa'.repeat(32)}`,
        block_number: 42,
        transaction_index: 3,
      }],
      rowCount: 1,
    });

    const response = await request(createApp())
      .get('/transactions?block=42&limit=1&after=42%3A4');

    expect(response.status).toBe(200);
    expect(response.body.pagination.nextCursor).toBe('42:3');
    expect(mockedQuery.mock.calls[0]?.[1]).toEqual([42, 4, 1, 42]);
  });

  test('rejects malformed composite transaction cursors without querying the database', async () => {
    const response = await request(createApp())
      .get('/transactions?after=42%3Ax');

    expect(response.status).toBe(400);
    expect(mockedQuery).not.toHaveBeenCalled();
  });

  test('address history uses block and transaction index to avoid skipped rows', async () => {
    mockedQuery.mockResolvedValueOnce({
      rows: [{
        hash: `0x${'bb'.repeat(32)}`,
        block_number: 42,
        transaction_index: 3,
        timestamp_unix: 100,
      }],
      rowCount: 1,
    });

    const response = await request(createApp())
      .get(`/addresses/${address}/transactions?limit=1&after=42%3A4`);

    expect(response.status).toBe(200);
    expect(response.body.pagination.nextCursor).toBe('42:3');
    expect(mockedQuery.mock.calls[0]?.[1]).toEqual([address, 42, 4, 1]);
  });
});
