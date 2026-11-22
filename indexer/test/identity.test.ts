import express from 'express';
import request from 'supertest';
import identityRouter, { readRpcIdentity } from '../src/api/routes/identity';
import { makeTestConfig } from '../src/config';

const chainIdHex = `0x${73571..toString(16)}`;
const genesisHash = `0x${'ab'.repeat(32)}`;

function rpcResponse(result: unknown) {
  return {
    ok: true,
    json: async () => ({ result }),
  } as Response;
}

describe('read-only RPC identity endpoint', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    jest.clearAllMocks();
  });

  test('returns live Chain ID and genesis hash without returning the RPC URL', async () => {
    global.fetch = jest.fn()
      .mockResolvedValueOnce(rpcResponse(chainIdHex))
      .mockResolvedValueOnce(rpcResponse({ hash: genesisHash })) as unknown as typeof fetch;

    const config = makeTestConfig({ expectedGenesisHash: genesisHash });
    const response = await request(express().use('/identity', identityRouter(config)))
      .get('/identity');

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({
      success: true,
      data: {
        chainId: 73571,
        genesisHash,
        expectedGenesisHash: genesisHash,
        verified: true,
      },
    });
    expect(JSON.stringify(response.body)).not.toContain(config.rpcUrl);
  });

  test('marks the identity unverified when the live Chain ID differs', async () => {
    global.fetch = jest.fn()
      .mockResolvedValueOnce(rpcResponse('0x4d'))
      .mockResolvedValueOnce(rpcResponse({ hash: genesisHash })) as unknown as typeof fetch;

    const response = await request(
      express().use('/identity', identityRouter(makeTestConfig())),
    ).get('/identity');

    expect(response.status).toBe(200);
    expect(response.body.data.chainId).toBe(77);
    expect(response.body.data.verified).toBe(false);
  });

  test('marks the identity unverified when the configured genesis hash differs', async () => {
    global.fetch = jest.fn()
      .mockResolvedValueOnce(rpcResponse(chainIdHex))
      .mockResolvedValueOnce(rpcResponse({ hash: genesisHash })) as unknown as typeof fetch;

    const response = await request(express().use(
      '/identity',
      identityRouter(makeTestConfig({ expectedGenesisHash: `0x${'cd'.repeat(32)}` })),
    )).get('/identity');

    expect(response.status).toBe(200);
    expect(response.body.data.verified).toBe(false);
  });

  test('fails closed and hides RPC transport details', async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error('private RPC details')) as unknown as typeof fetch;

    const response = await request(
      express().use('/identity', identityRouter(makeTestConfig())),
    ).get('/identity');

    expect(response.status).toBe(503);
    expect(response.body).toEqual({
      success: false,
      error: 'Network identity unavailable',
    });
    expect(JSON.stringify(response.body)).not.toContain('private RPC details');
  });

  test('opens a short circuit after repeated identity failures', async () => {
    const fetchMock = jest.fn().mockRejectedValue(new Error('private RPC details'));
    global.fetch = fetchMock as unknown as typeof fetch;
    const app = express().use('/identity', identityRouter(makeTestConfig()));

    await request(app).get('/identity');
    await request(app).get('/identity');
    const thirdFailure = await request(app).get('/identity');
    const requestDuringCooldown = await request(app).get('/identity');

    expect(thirdFailure.status).toBe(503);
    expect(thirdFailure.body.error).toBe('Network identity temporarily unavailable');
    expect(requestDuringCooldown.body.error).toBe('Network identity temporarily unavailable');
    expect(fetchMock).toHaveBeenCalledTimes(6);
  });

  test('rejects malformed genesis responses', async () => {
    const fetchMock = jest.fn()
      .mockResolvedValueOnce(rpcResponse(chainIdHex))
      .mockResolvedValueOnce(rpcResponse({ hash: '0x1234' }));

    await expect(readRpcIdentityWithFetch(fetchMock)).rejects.toThrow(/invalid genesis block/);
  });
});

async function readRpcIdentityWithFetch(fetchMock: jest.Mock): Promise<unknown> {
  const original = global.fetch;
  global.fetch = fetchMock as unknown as typeof fetch;
  try {
    return await readRpcIdentity('http://localhost:9650');
  } finally {
    global.fetch = original;
  }
}
