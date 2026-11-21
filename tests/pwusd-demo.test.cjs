'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const demo = require('../scripts/pwusd-demo.cjs');
const SENDER = '0x' + '11'.repeat(20), RECIPIENT = '0x' + '22'.repeat(20), TOKEN = '0x' + '33'.repeat(20);
const url = `http://127.0.0.1:9656/ext/bc/${demo.BLOCKCHAIN}/rpc`;
function fixture(t, options = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pwusd-offline-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  let sender = 10n * demo.PW, recipient = 0n, tokenSender = demo.SUPPLY, tokenRecipient = 0n;
  const receipts = {}, calls = [];
  let count = 0;
  function tx(kind) {
    count++;
    const hash = '0x' + count.toString(16).padStart(64, '0');
    return { hash, wait: async () => {
      sender -= 210000n;
      if (kind === 'pw') { sender -= demo.PW; recipient += demo.PW; }
      if (kind === 'pwusd') { tokenSender -= demo.TOKENS; tokenRecipient += demo.TOKENS; }
      receipts[hash] = { transactionHash: hash, status: options.failedReceipt ? '0x0' : '0x1',
        gasUsed: '0x5208', effectiveGasPrice: options.badGas ? '0xb' : '0xa',
        blockNumber: '0x' + count.toString(16), blockHash: '0x' + 'aa'.repeat(32),
        contractAddress: kind === 'deploy' ? TOKEN : null,
        logs: kind === 'pwusd' ? [{ address: TOKEN }] : [] };
    } };
  }
  let deployment;
  const token = { deploymentTransaction: () => deployment, getAddress: async () => TOKEN,
    name: async () => 'PWUSD Demo (Unbacked)', symbol: async () => 'PWUSD', decimals: async () => 18n,
    totalSupply: async () => demo.SUPPLY, balanceOf: async a => a === SENDER ? tokenSender : tokenRecipient,
    transfer: async (a, amount, opts) => { assert.equal(a, RECIPIENT); assert.equal(amount, demo.TOKENS); assert.equal(opts.chainId, 73571); return tx('pwusd'); },
    interface: { parseLog: () => ({ name: 'Transfer', args: [SENDER, RECIPIENT, demo.TOKENS] }) } };
  const ethers = { ContractFactory: class {
    async deploy(a, opts) { assert.equal(a, SENDER); assert.equal(opts.nonce, 0); deployment = tx('deploy'); return token; }
  } };
  const provider = { send: async (method, params) => {
    calls.push(method);
    switch (method) {
      case 'eth_chainId': return options.wrongChain ? '0x4d' : '0x11f63';
      case 'eth_getTransactionCount': return options.usedSender ? '0x1' : '0x0';
      case 'eth_getBalance': return '0x' + (params[0] === SENDER ? sender : recipient).toString(16);
      case 'eth_getTransactionReceipt': return receipts[params[0]];
      case 'eth_getCode': return options.badCode ? '0x01' : '0x1234';
      default: throw new Error(method);
    }
  } };
  const wallet = { address: SENDER, sendTransaction: async request => {
    assert.equal(request.chainId, 73571); assert.equal(request.value, demo.PW); return tx('pw');
  } };
  return { dir, provider, wallet, recipient: RECIPIENT, ethers,
    artifact: { abi: [], bytecode: { object: '0x1234' }, deployedBytecode: { object: '0x1234' } },
    broadcasts: () => count, calls };
}

test('endpoint requires explicit chain ID and exact local existing blockchain', () => {
  assert.equal(demo.endpoint(url, '73571'), url);
  for (const bad of [url.replace('127.0.0.1', 'example.com'), url.replace('http:', 'https:'),
    url + '?x=1', url.replace(demo.BLOCKCHAIN, 'other'), url.replace('127.0.0.1', 'user:password@127.0.0.1')]) {
    assert.throws(() => demo.endpoint(bad, '73571'));
  }
  assert.throws(() => demo.endpoint(url, '77'));
  assert.throws(() => demo.endpoint(url, undefined));
});
test('offline full transaction workflow validates three receipts, balances and gas', async t => {
  const f = fixture(t);
  const result = await demo.runDemo(f);
  assert.equal(f.broadcasts(), 3);
  assert.equal(result.contractAddress, TOKEN);
  assert.equal(result.totalGasFeeWei, 630000n);
  assert.equal(result.senderPWUSDAfter, demo.SUPPLY - demo.TOKENS);
  assert.equal(result.recipientPWUSDAfter, demo.TOKENS);
  assert.equal(result.recipientNativeAfterWei, demo.PW);
  assert.ok(fs.existsSync(path.join(f.dir, 'verified.json')));
});
for (const [option, expectedCount] of [['wrongChain', 0], ['usedSender', 0], ['failedReceipt', 1], ['badGas', 1], ['badCode', 1]]) {
  test(`refuses ${option} without further transactions`, async t => {
    const f = fixture(t, { [option]: true });
    await assert.rejects(demo.runDemo(f));
    assert.equal(f.broadcasts(), expectedCount);
    assert.equal(fs.existsSync(path.join(f.dir, 'verified.json')), false);
  });
}
test('prior attempt marker forbids a second deployment', async t => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.dir, 'attempt.json'), 'prior attempt');
  await assert.rejects(demo.runDemo(f));
  assert.equal(f.broadcasts(), 0);
});
test('missing effective gas price fails instead of using zero', () => {
  assert.throws(() => demo.receiptAccounting({ transactionHash: '0xaa', status: '0x1', gasUsed: '0x1' }, '0xaa', 2n, 1n, 0n));
});
test('live mode requires approval before loading keys or RPC dependencies', async () => {
  await assert.rejects(demo.main(['run', '--rpc-url', url, '--chain-id', '73571']), /approve-live-demo/);
});
