'use strict';
// Uses existing indexer ethers dependency. No node, RPC, broadcast, or chain creation.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { createRequire } = require('node:module');
const root = path.resolve(__dirname, '..');
const ethers = createRequire(path.join(root, 'indexer/package.json'))('ethers');
const demo = require('../scripts/pwusd-demo.cjs');
const artifact = JSON.parse(fs.readFileSync(path.join(root, 'contracts/out/PWUSDDemo.sol/PWUSDDemo.json')));

test('compiled OpenZeppelin token deployment and transfers sign for chain 73571 offline', async () => {
  const sender = ethers.Wallet.createRandom();
  const recipient = ethers.Wallet.createRandom();
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode.object, sender);
  const deploy = await factory.getDeployTransaction(sender.address);
  const contract = new ethers.Interface(artifact.abi);
  const requests = [
    { ...deploy, gasLimit: 2000000n },
    { to: ethers.getCreateAddress({ from: sender.address, nonce: 0 }), data: contract.encodeFunctionData('transfer', [recipient.address, demo.TOKENS]), gasLimit: 100000n },
    { to: recipient.address, value: demo.PW, gasLimit: 21000n },
  ];
  for (const [nonce, request] of requests.entries()) {
    const signed = await sender.signTransaction({ ...request, nonce, chainId: 73571, gasPrice: 1000000000n });
    const parsed = ethers.Transaction.from(signed);
    assert.equal(parsed.chainId, 73571n);
    assert.equal(parsed.from, sender.address);
    assert.equal(parsed.nonce, nonce);
  }
  assert.equal(artifact.metadata.settings.compilationTarget['contracts/src/PWUSDDemo.sol'], 'PWUSDDemo');
});

test('prepare creates only new private disposable wallets and refuses overwrite', t => {
  const parent = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'pwusd-wallet-test-'));
  t.after(() => fs.rmSync(parent, { recursive: true, force: true }));
  const dir = path.join(parent, 'demo');
  const manifest = demo.prepare(dir, ethers);
  assert.equal(manifest.purpose, 'disposable-pwusd-demo');
  assert.equal(manifest.chainId, 73571);
  assert.equal(fs.statSync(dir).mode & 0o077, 0);
  const secret = JSON.parse(fs.readFileSync(path.join(dir, 'sender.json')));
  assert.equal(new ethers.Wallet(secret.privateKey).address, manifest.sender);
  assert.equal(fs.statSync(path.join(dir, 'sender.json')).mode & 0o077, 0);
  assert.throws(() => demo.prepare(dir, ethers));
});
