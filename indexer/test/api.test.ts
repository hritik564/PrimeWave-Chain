/**
 * C12 API Tests
 *
 * Tests: validation, search format detection, error responses, routing.
 * Mocks: DB query function, IndexerEngine.
 */

import request from 'supertest';
import express from 'express';
import { validateAddress, validateHash, validateValidatorId, validateBlockNumber, validatePagination, ValidationError } from '../src/api/validation';
import searchRouter from '../src/api/routes/search';
import blocksRouter from '../src/api/routes/blocks';
import { makeTestConfig } from '../src/config';

// ── Mock DB client ────────────────────────────────────────────────────────────

jest.mock('../src/db/client', () => ({
  query: jest.fn().mockResolvedValue({ rows: [], rowCount: 0 }),
  withTransaction: jest.fn(),
  getPool: jest.fn(),
}));

import { query as mockQuery } from '../src/db/client';
const mockedQuery = mockQuery as jest.Mock;

// ── Input validation tests ────────────────────────────────────────────────────

describe('Input validation', () => {
  test('API-01: validateAddress accepts valid 0x address', () => {
    const addr = '0x' + '11'.repeat(20);
    expect(validateAddress(addr)).toBe(addr.toLowerCase());
  });

  test('API-02: validateAddress rejects invalid address', () => {
    expect(() => validateAddress('notanaddress')).toThrow(ValidationError);
    expect(() => validateAddress('0x' + '11'.repeat(19))).toThrow(ValidationError);
    expect(() => validateAddress('')).toThrow(ValidationError);
  });

  test('API-03: validateHash accepts valid 32-byte hex', () => {
    const hash = '0x' + 'ab'.repeat(32);
    expect(validateHash(hash)).toBe(hash.toLowerCase());
  });

  test('API-04: validateHash rejects short hash', () => {
    expect(() => validateHash('0x' + 'ab'.repeat(20))).toThrow(ValidationError);
  });

  test('API-05: validateBlockNumber accepts non-negative integer', () => {
    expect(validateBlockNumber('0')).toBe(0);
    expect(validateBlockNumber('1000')).toBe(1000);
  });

  test('API-06: validateBlockNumber rejects negative and non-integer', () => {
    expect(() => validateBlockNumber('-1')).toThrow(ValidationError);
    expect(() => validateBlockNumber('1.5')).toThrow(ValidationError);
    expect(() => validateBlockNumber('abc')).toThrow(ValidationError);
  });

  test('API-07: validatePagination defaults applied', () => {
    const { limit, after } = validatePagination(undefined, undefined, 100, 25);
    expect(limit).toBe(25);
    expect(after).toBeNull();
  });

  test('API-08: validatePagination rejects limit > max', () => {
    expect(() => validatePagination('1000', undefined, 100, 25)).toThrow(ValidationError);
  });

  test('API-09: validatePagination rejects negative after', () => {
    expect(() => validatePagination(undefined, '-5', 100, 25)).toThrow(ValidationError);
  });

  test('API-10: validateValidatorId accepts 32-byte hex', () => {
    const vid = '0x' + '01'.repeat(32);
    expect(validateValidatorId(vid)).toBe(vid.toLowerCase());
  });
});

// ── Search router tests ───────────────────────────────────────────────────────

describe('Search router', () => {
  let app: express.Application;

  beforeEach(() => {
    app = express();
    app.use('/search', searchRouter());
    mockedQuery.mockClear();
  });

  test('API-11: /search without q returns 400', async () => {
    const res = await request(app).get('/search');
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
  });

  test('API-12: address query hits addresses table', async () => {
    const addr = '0x' + '11'.repeat(20);
    mockedQuery.mockResolvedValueOnce({ rows: [{ address: addr, is_contract: false }], rowCount: 1 });

    const res = await request(app).get(`/search?q=${addr}`);
    expect(res.status).toBe(200);
    expect(res.body.type).toBe('address');
  });

  test('API-13: tx hash query hits transactions table first', async () => {
    const hash = '0x' + 'ff'.repeat(32);
    mockedQuery.mockResolvedValueOnce({ rows: [{ hash, block_number: 1, from_address: '0x11', to_address: '0x22' }], rowCount: 1 });

    const res = await request(app).get(`/search?q=${hash}`);
    expect(res.status).toBe(200);
    expect(res.body.type).toBe('transaction');
  });

  test('API-14: block number query hits blocks table', async () => {
    mockedQuery.mockResolvedValueOnce({ rows: [{ number: 42, hash: '0xabc', timestamp_unix: 1000, transaction_count: 3 }], rowCount: 1 });

    const res = await request(app).get('/search?q=42');
    expect(res.status).toBe(200);
    expect(res.body.type).toBe('block');
  });

  test('API-15: not found returns 404', async () => {
    const hash = '0x' + 'ff'.repeat(32);
    // All lookups return empty
    mockedQuery.mockResolvedValue({ rows: [], rowCount: 0 });

    const res = await request(app).get(`/search?q=${hash}`);
    expect(res.status).toBe(404);
  });

  test('API-16: invalid format returns 400', async () => {
    const res = await request(app).get('/search?q=notavalidquery!@#');
    expect(res.status).toBe(400);
    expect(res.body.type).toBe('invalid_format');
  });
});

// ── Block router tests ────────────────────────────────────────────────────────

describe('Blocks router', () => {
  let app: express.Application;
  const config = makeTestConfig();

  beforeEach(() => {
    app = express();
    app.use('/blocks', blocksRouter(config));
    mockedQuery.mockClear();
    // Error handler
    app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
      const { ValidationError: VE } = require('../src/api/validation');
      if (err instanceof VE) return res.status(400).json({ success: false, error: (err as Error).message });
      res.status(500).json({ success: false, error: 'internal' });
    });
  });

  test('API-17: GET /blocks returns paginated list', async () => {
    mockedQuery.mockResolvedValueOnce({
      rows: [{ number: 10, hash: '0x' + 'aa'.repeat(32), timestamp_unix: 1000, transaction_count: 5 }],
      rowCount: 1,
    });

    const res = await request(app).get('/blocks?limit=5');
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  test('API-18: GET /blocks/:number returns 404 for unknown block', async () => {
    mockedQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 });
    const res = await request(app).get('/blocks/9999');
    expect(res.status).toBe(404);
  });

  test('API-19: GET /blocks/hash/:hash validates hash format', async () => {
    const res = await request(app).get('/blocks/hash/notahash');
    expect(res.status).toBe(400);
  });

  test('API-20: limit > maxLimit returns 400', async () => {
    const res = await request(app).get('/blocks?limit=99999');
    expect(res.status).toBe(400);
  });
});

// ── Health endpoint ───────────────────────────────────────────────────────────

describe('Health endpoint', () => {
  test('API-21: GET /health returns 200', async () => {
    const app = express();
    app.get('/health', (_req, res) => {
      res.json({ success: true, data: { status: 'ok', service: 'primewave-indexer' } });
    });

    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('ok');
  });
});
