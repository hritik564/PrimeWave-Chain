import express from 'express';
import request from 'supertest';
import contractsRouter from '../src/api/routes/contracts';
import validatorsRouter from '../src/api/routes/validators';
import { makeTestConfig } from '../src/config';
import { ValidationError } from '../src/api/validation';

jest.mock('../src/db/client', () => ({
  query: jest.fn(),
}));

import { query } from '../src/db/client';

const mockedQuery = query as jest.Mock;
const contractAddress = `0x${'22'.repeat(20)}`;
const validatorId = `0x${'33'.repeat(32)}`;

function createApp() {
  const app = express();
  const config = makeTestConfig();
  app.use('/contracts', contractsRouter(config));
  app.use('/validators', validatorsRouter(config));
  app.use((error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    res.status(error instanceof ValidationError ? 400 : 500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Unexpected error',
    });
  });
  return app;
}

describe('stable list cursors', () => {
  beforeEach(() => mockedQuery.mockReset());

  test('contracts use unique address cursors so same-block deployments are not skipped', async () => {
    mockedQuery.mockResolvedValueOnce({
      rows: [{ address: contractAddress, creation_block: 10 }],
      rowCount: 1,
    });

    const response = await request(createApp())
      .get(`/contracts?known=true&limit=1&after=${contractAddress}`);

    expect(response.status).toBe(200);
    expect(response.body.pagination.nextCursor).toBe(contractAddress);
    expect(mockedQuery.mock.calls[0]?.[1]).toEqual([true, contractAddress, 1]);
  });

  test('validators use block plus validator ID cursors to preserve equal-height records', async () => {
    mockedQuery.mockResolvedValueOnce({
      rows: [{ first_seen_block: 5, validation_id: validatorId }],
      rowCount: 1,
    });

    const response = await request(createApp())
      .get(`/validators?status=2&limit=1&after=5%3A${validatorId}`);

    expect(response.status).toBe(200);
    expect(response.body.pagination.nextCursor).toBe(`5:${validatorId}`);
    expect(mockedQuery.mock.calls[0]?.[1]).toEqual([2, 5, validatorId, 1]);
  });

  test('rejects malformed validator cursors without querying the database', async () => {
    const response = await request(createApp()).get('/validators?after=bad');
    expect(response.status).toBe(400);
    expect(mockedQuery).not.toHaveBeenCalled();
  });
});
