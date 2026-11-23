import assert from 'node:assert/strict';
import test from 'node:test';
import { pageQuery } from './pagination';

test('pagination sends numeric block cursor as after', () => {
  assert.deepEqual(pageQuery({ limit: 25, cursor: 500 }), { limit: 25, after: 500 });
});

test('pagination preserves composite transaction keyset cursor', () => {
  assert.deepEqual(pageQuery({ limit: 20, cursor: '500:3' }), { limit: 20, after: '500:3' });
});

test('first page omits the after cursor', () => {
  assert.deepEqual(pageQuery({ limit: 10 }), { limit: 10, after: undefined });
});
