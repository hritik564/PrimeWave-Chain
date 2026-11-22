import test from 'node:test';
import assert from 'node:assert/strict';
import {
  formatAge,
  formatEmissionRate,
  formatGas,
  formatGasPercent,
  formatNumber,
  formatPW,
  formatTimestamp,
} from './format';

test('formatters preserve true zero values', () => {
  assert.equal(formatPW('0'), '0 PW');
  assert.equal(formatNumber('0'), '0');
  assert.equal(formatGas('0'), '0');
  assert.equal(formatEmissionRate('0'), '0 PW / year');
  assert.equal(formatTimestamp(0, true).includes('1970'), true);
});

test('formatters distinguish missing or invalid values from zero', () => {
  assert.equal(formatPW(null), 'Unavailable');
  assert.equal(formatPW('not-a-number'), 'Unavailable');
  assert.equal(formatNumber(null), 'Unavailable');
  assert.equal(formatGas(undefined), 'Unavailable');
  assert.equal(formatEmissionRate(null), 'Unavailable');
  assert.equal(formatGasPercent('0', '0'), 'Unavailable');
  assert.equal(formatAge(Number.NaN), 'Unavailable');
});
