import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  isSearchQueryEnabled,
  parseSearchApiResponse,
  type SearchApiResponse,
} from './search-client';

describe('PWCScan search client', () => {
  it('preserves the real block search response envelope and data', () => {
    const response = parseSearchApiResponse({
      success: true,
      type: 'block',
      data: { number: '5' },
    });

    assert.equal(response.success, true);
    assert.equal(response.type, 'block');
    assert.deepEqual(response.data, { number: '5' });
  });

  it('enables one-character block queries while rejecting empty queries', () => {
    assert.equal(isSearchQueryEnabled('5'), true);
    assert.equal(isSearchQueryEnabled(' 5 '), true);
    assert.equal(isSearchQueryEnabled(''), false);
    assert.equal(isSearchQueryEnabled('   '), false);
  });

  it('keeps block, transaction, and address results distinguishable', () => {
    const responses: SearchApiResponse[] = [
      { success: true, type: 'block', data: { number: '5' } },
      { success: true, type: 'transaction', data: { hash: '0xtransaction' } },
      { success: true, type: 'address', data: { address: '0xaddress' } },
    ];

    for (const expected of responses) {
      const response = parseSearchApiResponse(expected);

      assert.equal(response.success, true);
      assert.equal(response.type, expected.type);
      assert.deepEqual(response.data, expected.data);
    }
  });

  it('rejects unsuccessful invalid-format responses instead of treating them as results', () => {
    assert.throws(
      () =>
        parseSearchApiResponse({
          success: false,
          type: 'invalid_format',
          error: 'Query does not match any known format',
        }),
      /Invalid search API response/,
    );
  });
});