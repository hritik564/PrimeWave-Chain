import assert from 'node:assert/strict';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const workspaceRoot = path.resolve(packageRoot, '../..');
const hook = path.join(workspaceRoot, 'scripts/post-merge.sh');

test('post-merge runs frozen install only and never invokes database schema push', () => {
  const temporaryRoot = mkdtempSync(path.join(os.tmpdir(), 'pwcscan-post-merge-test-'));
  try {
    const bin = path.join(temporaryRoot, 'bin');
    const calls = path.join(temporaryRoot, 'calls.txt');
    const pnpm = path.join(bin, 'pnpm');
    mkdirSync(bin, { recursive: true });
    writeFileSync(pnpm, '#!/bin/sh\nprintf "%s\\n" "$*" >> "$PW_TEST_CALLS"\n');
    chmodSync(pnpm, 0o755);

    const result = spawnSync('bash', [hook], {
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${bin}${path.delimiter}${process.env.PATH ?? ''}`,
        PW_TEST_CALLS: calls,
      },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(readFileSync(calls, 'utf8').trim().split('\n'), ['install --frozen-lockfile']);
    assert.match(result.stdout, /Database schema changes are not applied automatically/);
    assert.doesNotMatch(readFileSync(hook, 'utf8'), /--filter\s+db\s+push/);
  } finally {
    rmSync(temporaryRoot, { recursive: true, force: true });
  }
});
