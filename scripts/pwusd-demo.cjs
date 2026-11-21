#!/usr/bin/env node
'use strict';
// Local PWUSD demonstration only: unbacked, nonredeemable, disposable wallets.
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const ROOT = path.resolve(__dirname, '..');
const BLOCKCHAIN = 'XDwGN3ztu8JDEFALEeKWS3FPax8U2XghGFZVDxrGesNs5w7D7';
const SUPPLY = 1000000n * 10n ** 18n;
const TOKENS = 25n * 10n ** 18n;
const PW = 10n ** 18n;
class DemoError extends Error {}
function ensure(ok, message) { if (!ok) throw new DemoError(message); }
function endpoint(value, chainId) {
  ensure(chainId === '73571', 'Explicit --chain-id 73571 required');
  const u = new URL(value);
  ensure(u.protocol === 'http:' && u.hostname === '127.0.0.1' && u.port &&
    !u.username && !u.password && !u.search && !u.hash &&
    u.pathname === `/ext/bc/${BLOCKCHAIN}/rpc`, 'Only the existing loopback pw-demo-04 RPC is allowed');
  return u.href;
}
function safeDir(dir) {
  for (let p = dir; ; p = path.dirname(p)) {
    ensure(!fs.lstatSync(p).isSymbolicLink(), 'Symlink wallet/output path refused');
    if (path.dirname(p) === p) break;
  }
}
function write(file, data) {
  fs.writeFileSync(file, `${JSON.stringify(data, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2)}\n`,
    { mode: 0o600, flag: 'wx' });
}
function prepare(dir, ethers) {
  ensure(!fs.existsSync(dir), 'Demo wallet directory already exists; do not overwrite');
  safeDir(path.dirname(dir));
  fs.mkdirSync(dir, { mode: 0o700 });
  const sender = ethers.Wallet.createRandom();
  const recipient = ethers.Wallet.createRandom();
  // Only newly generated disposable wallet secrets, never existing validator keys.
  write(path.join(dir, 'sender.json'), { privateKey: sender.privateKey });
  write(path.join(dir, 'recipient.json'), { privateKey: recipient.privateKey });
  const manifest = { purpose: 'disposable-pwusd-demo', chainId: 73571,
    sender: sender.address, recipient: recipient.address, createdAt: new Date().toISOString() };
  write(path.join(dir, 'wallets.json'), manifest);
  return manifest;
}
async function chain(provider) {
  ensure(await provider.send('eth_chainId', []) === '0x11f63', 'RPC chain identity mismatch');
}
async function balance(provider, address, tag = 'latest') {
  return BigInt(await provider.send('eth_getBalance', [address, tag]));
}
function receiptAccounting(receipt, hash, before, after, value) {
  ensure(receipt && receipt.transactionHash.toLowerCase() === hash.toLowerCase() &&
    receipt.status === '0x1', 'Transaction receipt failed or mismatched');
  const gasUsed = BigInt(receipt.gasUsed);
  const gasPrice = BigInt(receipt.effectiveGasPrice);
  ensure(gasUsed > 0n && gasPrice > 0n, 'Receipt gas accounting unavailable');
  const fee = gasUsed * gasPrice;
  ensure(before - after === fee + value, 'Sender PW balance delta differs from value plus gas');
  return { hash, blockHash: receipt.blockHash, blockNumber: receipt.blockNumber,
    status: receipt.status, gasUsed, effectiveGasPrice: gasPrice, gasFeeWei: fee,
    senderBeforeWei: before, senderAfterWei: after };
}
async function runDemo({ provider, wallet, recipient, ethers, artifact, dir }) {
  await chain(provider);
  ensure(await provider.send('eth_getTransactionCount', [wallet.address, 'latest']) === '0x0' &&
    await provider.send('eth_getTransactionCount', [wallet.address, 'pending']) === '0x0',
    'Disposable sender must have no prior or pending transactions');
  ensure(await balance(provider, recipient) === 0n &&
    await provider.send('eth_getTransactionCount', [recipient, 'pending']) === '0x0',
    'Disposable recipient must be unused');
  ensure(await balance(provider, wallet.address) > PW, 'Fund the disposable sender with PW plus gas first');
  ensure(artifact.abi && /^0x[0-9a-f]+$/i.test(artifact.bytecode.object) &&
    /^0x[0-9a-f]+$/i.test(artifact.deployedBytecode.object), 'Build PWUSDDemo with Forge first');
  // Exclusive attempt marker BEFORE any broadcast. Never silently retry deployment.
  write(path.join(dir, 'attempt.json'), { chainId: 73571, blockchainId: BLOCKCHAIN,
    sender: wallet.address, recipient, startedAt: new Date().toISOString() });
  const report = { chainId: 73571, blockchainId: BLOCKCHAIN, demonstrationOnly: true,
    usdBacked: false, redeemable: false, sender: wallet.address, recipient, transactions: [] };
  async function execute(kind, send, value = 0n) {
    await chain(provider);
    const before = await balance(provider, wallet.address);
    const tx = await send();
    fs.appendFileSync(path.join(dir, 'transactions.jsonl'), JSON.stringify({ kind, hash: tx.hash }) + '\n', { mode: 0o600 });
    await tx.wait(1, 60000);
    const receipt = await provider.send('eth_getTransactionReceipt', [tx.hash]);
    const after = await balance(provider, wallet.address, receipt.blockNumber);
    const entry = { kind, ...receiptAccounting(receipt, tx.hash, before, after, value) };
    report.transactions.push(entry);
    write(path.join(dir, `${kind}-receipt.json`), receipt);
    return receipt;
  }
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode.object, wallet);
  let token;
  const deployment = await execute('deployment', async () => {
    token = await factory.deploy(wallet.address, { nonce: 0, chainId: 73571 });
    return token.deploymentTransaction();
  });
  const address = await token.getAddress();
  ensure(deployment.contractAddress?.toLowerCase() === address.toLowerCase(), 'Deployment address mismatch');
  ensure(await provider.send('eth_getCode', [address, deployment.blockNumber]) === artifact.deployedBytecode.object,
    'Deployed bytecode differs from compiled PWUSDDemo');
  ensure(await token.name() === 'PWUSD Demo (Unbacked)' && await token.symbol() === 'PWUSD' &&
    await token.decimals() === 18n && await token.totalSupply() === SUPPLY &&
    await token.balanceOf(wallet.address) === SUPPLY, 'PWUSD initial state incorrect');
  const transfer = await execute('pwusd-transfer', () => token.transfer(recipient, TOKENS, { nonce: 1, chainId: 73571 }));
  const event = transfer.logs.filter(l => l.address.toLowerCase() === address.toLowerCase())
    .map(l => { try { return token.interface.parseLog(l); } catch { return null; } })
    .find(l => l?.name === 'Transfer' && l.args[0].toLowerCase() === wallet.address.toLowerCase() &&
      l.args[1].toLowerCase() === recipient.toLowerCase() && l.args[2] === TOKENS);
  ensure(event && await token.balanceOf(recipient) === TOKENS &&
    await token.balanceOf(wallet.address) === SUPPLY - TOKENS && await token.totalSupply() === SUPPLY,
    'PWUSD transfer event or balances incorrect');
  const recipientBefore = await balance(provider, recipient);
  const native = await execute('pw-transfer', () => wallet.sendTransaction({ to: recipient, value: PW, nonce: 2, chainId: 73571 }), PW);
  const recipientAfter = await balance(provider, recipient, native.blockNumber);
  ensure(recipientAfter - recipientBefore === PW, 'Native PW recipient delta incorrect');
  report.contractAddress = address;
  report.totalSupply = SUPPLY;
  report.pwusdTransferred = TOKENS;
  report.nativeTransferredWei = PW;
  report.recipientNativeBeforeWei = recipientBefore;
  report.recipientNativeAfterWei = recipientAfter;
  report.totalGasFeeWei = report.transactions.reduce((sum, t) => sum + t.gasFeeWei, 0n);
  report.senderPWUSDAfter = await token.balanceOf(wallet.address);
  report.recipientPWUSDAfter = await token.balanceOf(recipient);
  write(path.join(dir, 'verified.json'), report);
  return report;
}
async function main(argv = process.argv.slice(2)) {
  const [mode, ...rest] = argv;
  const options = {};
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--approve-live-demo') options.approved = true;
    else if (rest[i] === '--chain-id' || rest[i] === '--rpc-url') {
      ensure(rest[i + 1], 'Missing option value'); options[rest[i].slice(2)] = rest[++i];
    } else throw new DemoError('Unknown argument');
  }
  ensure(mode === 'prepare' || mode === 'run', 'Expected prepare or run');
  const url = endpoint(options['rpc-url'], options['chain-id']);
  ensure(mode !== 'run' || options.approved, 'Live deployment requires --approve-live-demo');
  const ethers = createRequire(path.join(ROOT, 'indexer/package.json'))('ethers');
  const dir = path.join(ROOT, 'local-data/pwusd-demo');
  if (mode === 'prepare') {
    const parent = path.dirname(dir);
    if (!fs.existsSync(parent)) { safeDir(path.dirname(parent)); fs.mkdirSync(parent, { mode: 0o700 }); }
    console.log(JSON.stringify(prepare(dir, ethers)));
    return;
  }
  safeDir(dir);
  ensure(!fs.existsSync(path.join(dir, 'attempt.json')), 'Prior attempt exists; inspect receipts, never rerun blindly');
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'wallets.json')));
  ensure(manifest.purpose === 'disposable-pwusd-demo' && manifest.chainId === 73571, 'Disposable wallet manifest required');
  const keyFile = path.join(dir, 'sender.json');
  ensure((fs.statSync(dir).mode & 0o077) === 0 && (fs.statSync(keyFile).mode & 0o077) === 0,
    'Disposable wallet directory/key permissions must be private');
  ensure(!fs.lstatSync(keyFile).isSymbolicLink(), 'Symlink key refused');
  const artifact = JSON.parse(fs.readFileSync(path.join(ROOT, 'contracts/out/PWUSDDemo.sol/PWUSDDemo.json')));
  const provider = new ethers.JsonRpcProvider(url, undefined, { cacheTimeout: -1 });
  try {
    const wallet = new ethers.Wallet(JSON.parse(fs.readFileSync(keyFile)).privateKey, provider);
    ensure(wallet.address === manifest.sender && ethers.isAddress(manifest.recipient) &&
      manifest.recipient !== wallet.address, 'Disposable wallet identity mismatch');
    const result = await runDemo({ provider, wallet, recipient: manifest.recipient, ethers, artifact, dir });
    console.log(JSON.stringify({ contractAddress: result.contractAddress,
      transactions: result.transactions.map(t => ({ kind: t.kind, hash: t.hash })), verified: true }));
  } finally { provider.destroy(); }
}
module.exports = { endpoint, receiptAccounting, runDemo, prepare, main, BLOCKCHAIN, SUPPLY, TOKENS, PW };
if (require.main === module) main().catch(error => {
  console.error(error instanceof DemoError ? error.message : 'PWUSD demo failed; inspect public receipts.');
  console.error('Preserve any attempt marker and public receipts; do not retry blindly.');
  process.exitCode = 1;
});
