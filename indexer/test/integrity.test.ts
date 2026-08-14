/**
 * C12 Integrity Check Tests
 *
 * Tests: each INDEX-1..13 check with mocked DB responses.
 * Confirms: correct pass/fail classification, SQL queries run.
 */

import { checkResultShape } from './helpers/integrity-helpers';

// Mock the DB client
jest.mock('../src/db/client', () => ({
  query: jest.fn(),
  withTransaction: jest.fn(),
  getPool: jest.fn(),
}));

import { query as mockQuery } from '../src/db/client';
const mockedQuery = mockQuery as jest.Mock;

// Mock RPC client
const mockRpc = {
  getBlockNumber: jest.fn().mockResolvedValue(100),
  getBlockByNumber: jest.fn().mockResolvedValue({
    number: '0x64',
    hash: '0x' + 'aa'.repeat(32),
    parentHash: '0x' + 'bb'.repeat(32),
    timestamp: '0x1',
    gasLimit: '0x0',
    gasUsed: '0x0',
    transactions: [],
  }),
};

// We only test the logic layer (mocked DB), not real SQL
// Full integration tests require real PostgreSQL

describe('Integrity checks — structure', () => {
  test('INT-01: runAllChecks returns 13 results', async () => {
    // Make all queries return valid "passing" responses
    mockedQuery.mockImplementation(async (sql: string) => {
      if (sql.includes('sync_state'))        return { rows: [{ latest_block: '10', is_syncing: true }], rowCount: 1 };
      if (sql.includes('violations'))        return { rows: [{ violations: '0' }], rowCount: 1 };
      if (sql.includes('orphans'))           return { rows: [{ orphans: '0' }], rowCount: 1 };
      if (sql.includes('dups'))              return { rows: [{ dups: '0' }], rowCount: 1 };
      if (sql.includes('blocks WHERE'))      return { rows: [{ hash: '0x' + 'aa'.repeat(32), exists: true }], rowCount: 1 };
      if (sql.includes('EXISTS'))            return { rows: [{ exists: true }], rowCount: 1 };
      if (sql.includes('decoded_events'))    return { rows: [{ count: '5', bad: '0' }], rowCount: 1 };
      if (sql.includes('fee_distribution'))  return { rows: [{ violations: '0' }], rowCount: 1 };
      if (sql.includes('reward_vault_state')) return { rows: [{ violations: '0' }], rowCount: 1 };
      if (sql.includes('validator_events'))  return { rows: [{ count: '3' }], rowCount: 1 };
      if (sql.includes('validators'))        return { rows: [{ count: '3' }], rowCount: 1 };
      return { rows: [], rowCount: 0 };
    });

    const { runAllChecks } = await import('../src/integrity/checks');
    const results = await runAllChecks(mockRpc as unknown as import('../src/rpc').RpcClient, 73571, () => {});
    expect(results).toHaveLength(13);
  });

  test('INT-02: all results have required fields', async () => {
    mockedQuery.mockResolvedValue({ rows: [{ violations: '0', orphans: '0', dups: '0', count: '0', bad: '0', latest_block: '5', exists: true }], rowCount: 1 });

    const { runAllChecks } = await import('../src/integrity/checks');
    const results = await runAllChecks(mockRpc as unknown as import('../src/rpc').RpcClient, 73571, () => {});

    for (const r of results) {
      checkResultShape(r);
    }
  });

  test('INT-03: INDEX-11 fails when split does not sum to total', async () => {
    mockedQuery.mockImplementation(async (sql: string) => {
      if (sql.includes('fee_distribution') && sql.includes('violations')) {
        return { rows: [{ violations: '2' }], rowCount: 1 };
      }
      if (sql.includes('sync_state')) return { rows: [{ latest_block: '5' }], rowCount: 1 };
      return { rows: [{ violations: '0', orphans: '0', dups: '0', count: '0', bad: '0', exists: true }], rowCount: 1 };
    });

    const { runAllChecks } = await import('../src/integrity/checks');
    const results = await runAllChecks(mockRpc as unknown as import('../src/rpc').RpcClient, 73571, () => {});
    const index11 = results.find(r => r.id === 'INDEX-11');
    expect(index11).toBeDefined();
    expect(index11!.passed).toBe(false);
    expect(index11!.count).toBe(2);
  });

  test('INT-04: INDEX-12 fails when emitted > funded', async () => {
    mockedQuery.mockImplementation(async (sql: string) => {
      if (sql.includes('reward_vault_state') && sql.includes('violations')) {
        return { rows: [{ violations: '1' }], rowCount: 1 };
      }
      if (sql.includes('sync_state')) return { rows: [{ latest_block: '5' }], rowCount: 1 };
      return { rows: [{ violations: '0', orphans: '0', dups: '0', count: '0', bad: '0', exists: true }], rowCount: 1 };
    });

    const { runAllChecks } = await import('../src/integrity/checks');
    const results = await runAllChecks(mockRpc as unknown as import('../src/rpc').RpcClient, 73571, () => {});
    const index12 = results.find(r => r.id === 'INDEX-12');
    expect(index12!.passed).toBe(false);
  });

  test('INT-05: INDEX-2 passes when no parent hash violations', async () => {
    mockedQuery.mockImplementation(async (sql: string) => {
      if (sql.includes('violations')) return { rows: [{ violations: '0' }], rowCount: 1 };
      if (sql.includes('sync_state')) return { rows: [{ latest_block: '5' }], rowCount: 1 };
      return { rows: [{ orphans: '0', dups: '0', count: '0', bad: '0', exists: true }], rowCount: 1 };
    });

    const { runAllChecks } = await import('../src/integrity/checks');
    const results = await runAllChecks(mockRpc as unknown as import('../src/rpc').RpcClient, 73571, () => {});
    const index2 = results.find(r => r.id === 'INDEX-2');
    expect(index2!.passed).toBe(true);
  });

  test('INT-06: checks handle DB error gracefully', async () => {
    mockedQuery.mockRejectedValue(new Error('DB connection refused'));

    const { runAllChecks } = await import('../src/integrity/checks');
    // Should not throw — errors are caught per check
    const results = await runAllChecks(mockRpc as unknown as import('../src/rpc').RpcClient, 73571, () => {});
    expect(results).toHaveLength(13);
    const errorResults = results.filter(r => r.id === 'ERROR');
    expect(errorResults.length).toBeGreaterThan(0);
    for (const r of errorResults) {
      expect(r.passed).toBe(false);
    }
  });
});
