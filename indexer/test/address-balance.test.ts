import express from 'express';
import request from 'supertest';
import addressesRouter from '../src/api/routes/addresses';
import { makeTestConfig } from '../src/config';
import { query } from '../src/db/client';

jest.mock('../src/db/client', () => ({
  query: jest.fn(),
}));

const mockedQuery = query as jest.Mock;
const address = `0x${'11'.repeat(20)}`;

describe('read-only address balance lookup', () => {
  beforeEach(() => mockedQuery.mockReset());

  test('returns decimal wei from the server-side RPC without exposing its URL', async () => {
    mockedQuery.mockResolvedValueOnce({
      rows: [{
        address,
        is_contract: false,
        tx_count: 0,
        sent_count: 0,
        received_count: 0,
        first_seen_block: 0,
        last_seen_block: 0,
        creation_tx: null,
        is_known_protocol: false,
        protocol_name: null,
      }],
      rowCount: 1,
    });
    const config = makeTestConfig({ rpcUrl: 'http://private-rpc.invalid/rpc' });
    const rpc = { getBalance: jest.fn().mockResolvedValue('0x16345785d8a0000') };
    const response = await request(express().use(
      '/addresses',
      addressesRouter(config, rpc as never),
    )).get(`/addresses/${address}`);

    expect(response.status).toBe(200);
    expect(response.body.data.native_balance_wei).toBe('100000000000000000');
    expect(JSON.stringify(response.body)).not.toContain(config.rpcUrl);
    expect(rpc.getBalance).toHaveBeenCalledWith(address);
  });

  test('reports an unavailable balance when the read-only RPC fails', async () => {
    mockedQuery.mockResolvedValueOnce({
      rows: [{ address, is_contract: false }],
      rowCount: 1,
    });
    const response = await request(express().use(
      '/addresses',
      addressesRouter(makeTestConfig(), {
        getBalance: jest.fn().mockRejectedValue(new Error('private RPC detail')),
      } as never),
    )).get(`/addresses/${address}`);

    expect(response.status).toBe(200);
    expect(response.body.data.native_balance_wei).toBeNull();
    expect(JSON.stringify(response.body)).not.toContain('private RPC detail');
  });
});
