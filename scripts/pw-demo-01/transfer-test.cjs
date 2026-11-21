#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');

const workspaceRoot = path.resolve(__dirname, '../..');
const runtimeRoot = path.join(workspaceRoot, '.local-networks/pw-demo-01');
const dataDir = path.join(runtimeRoot, 'data');
const privateKeyPath = path.join(runtimeRoot, 'private/sender.key');
const accountsPath = path.join(runtimeRoot, 'metadata/accounts.json');
const attemptPath = path.join(runtimeRoot, 'metadata/transfer-attempted');
const resultPath = path.join(runtimeRoot, 'metadata/transfer.json');

if (!fs.existsSync(path.join(runtimeRoot, 'metadata/ready'))) {
  throw new Error('Isolated network has not passed startup verification.');
}
if (fs.existsSync(attemptPath) || fs.existsSync(resultPath)) {
  throw new Error('A transfer test was already attempted; refusing to send another transaction.');
}

function readEnvFile(filePath) {
  const text = fs.readFileSync(filePath, 'utf8');
  const values = {};
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^([A-Z0-9_]+)="(.*)"$/);
    if (match) values[match[1]] = match[2];
  }
  return values;
}

const state = readEnvFile(path.join(dataDir, 'network-state.env'));
if (state.PRIMEWAVE_DEV_CHAIN_ID !== '73571') {
  throw new Error('Saved runtime does not identify Chain 73571.');
}
const rpcUrl = state.PRIMEWAVE_RPC_URL;
if (!rpcUrl || !rpcUrl.startsWith('http://127.0.0.1:')) {
  throw new Error('Transfer test requires the isolated loopback RPC endpoint.');
}

const accounts = JSON.parse(fs.readFileSync(accountsPath, 'utf8'));
const privateKey = fs.readFileSync(privateKeyPath, 'utf8').trim();
if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
  throw new Error('Isolated sender key file is malformed.');
}
fs.writeFileSync(attemptPath, 'started\n', { mode: 0o600, flag: 'wx' });

const requireFromIndexer = createRequire(
  path.join(workspaceRoot, 'indexer/package.json'),
);
const { JsonRpcProvider, Wallet, parseEther } = requireFromIndexer('ethers');

(async () => {
  const provider = new JsonRpcProvider(rpcUrl);
  const wallet = new Wallet(privateKey, provider);
  if (wallet.address.toLowerCase() !== accounts.sender.toLowerCase()) {
    throw new Error('Sender key does not match the isolated account manifest.');
  }
  const chainId = await provider.send('eth_chainId', []);
  if (chainId !== '0x11f93') {
    throw new Error('RPC Chain ID changed; refusing to send a transaction.');
  }

  const recipientBefore = await provider.getBalance(accounts.recipient);
  const transaction = await wallet.sendTransaction({
    to: accounts.recipient,
    value: parseEther('1'),
  });
  const receipt = await transaction.wait(1);
  if (!receipt || receipt.status !== 1) {
    throw new Error('Development transfer did not receive a successful receipt.');
  }

  const senderBalance = await provider.getBalance(accounts.sender);
  const recipientBalance = await provider.getBalance(accounts.recipient);
  const result = {
    chainId: Number(BigInt(chainId)),
    sender: accounts.sender,
    recipient: accounts.recipient,
    transactionHash: transaction.hash,
    receiptStatus: receipt.status,
    blockNumber: receipt.blockNumber,
    gasUsed: receipt.gasUsed.toString(),
    effectiveGasPrice: receipt.gasPrice?.toString() ?? null,
    gasFeeWei: receipt.gasPrice
      ? (receipt.gasPrice * receipt.gasUsed).toString()
      : null,
    recipientBeforeWei: recipientBefore.toString(),
    senderAfterWei: senderBalance.toString(),
    recipientAfterWei: recipientBalance.toString(),
  };
  const temporary = `${resultPath}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(result, null, 2)}\n`, {
    mode: 0o600,
    flag: 'wx',
  });
  fs.renameSync(temporary, resultPath);
  console.log(`Verified 1 PW transfer. Tx: ${transaction.hash}`);
  console.log(`Block: ${receipt.blockNumber}; receipt status: ${receipt.status}`);
  console.log(`Sender: ${accounts.sender}; recipient: ${accounts.recipient}`);
  await provider.destroy();
})().catch((error) => {
  console.error(`Transfer test failed: ${error.message}`);
  process.exitCode = 1;
});
