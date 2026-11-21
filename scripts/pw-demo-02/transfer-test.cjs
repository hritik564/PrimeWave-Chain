#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');

const workspaceRoot = path.resolve(__dirname, '../..');
const runtimeRoot = path.join(workspaceRoot, '.local-networks/pw-demo-02');
const readyPath = path.join(runtimeRoot, 'metadata/ready.json');
const statePath = path.join(runtimeRoot, 'data/network-state.env');
const keyPath = path.join(runtimeRoot, 'private/sender.key');
const accountsPath = path.join(runtimeRoot, 'metadata/accounts.json');
const attemptPath = path.join(runtimeRoot, 'metadata/transfer-attempted');
const resultPath = path.join(runtimeRoot, 'metadata/transfer.json');

if (!fs.existsSync(readyPath)) {
  throw new Error('Isolated network has not passed startup verification.');
}
if (fs.existsSync(attemptPath) || fs.existsSync(resultPath)) {
  throw new Error('A transfer was already attempted; refusing to send another transaction.');
}

function readEnvFile(filePath) {
  const values = {};
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^([A-Z0-9_]+)="(.*)"$/);
    if (match) values[match[1]] = match[2];
  }
  return values;
}

const state = readEnvFile(statePath);
if (state.PRIMEWAVE_DEV_CHAIN_ID !== '73571') {
  throw new Error('Saved runtime is not Chain ID 73571.');
}
const rpcUrl = state.PRIMEWAVE_RPC_URL;
if (!rpcUrl || !rpcUrl.startsWith('http://127.0.0.1:')) {
  throw new Error('Transfer is restricted to the isolated loopback RPC endpoint.');
}
const accounts = JSON.parse(fs.readFileSync(accountsPath, 'utf8'));
const privateKey = fs.readFileSync(keyPath, 'utf8').trim();
if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
  throw new Error('Isolated sender key file is malformed.');
}

const requireFromIndexer = createRequire(path.join(workspaceRoot, 'indexer/package.json'));
const { JsonRpcProvider, Wallet, parseEther } = requireFromIndexer('ethers');

(async () => {
  const provider = new JsonRpcProvider(rpcUrl);
  try {
    const wallet = new Wallet(privateKey, provider);
    if (wallet.address.toLowerCase() !== accounts.sender.toLowerCase()) {
      throw new Error('Sender key does not match the isolated account manifest.');
    }
    const chainId = await provider.send('eth_chainId', []);
    if (chainId !== '0x11f63') {
      throw new Error('RPC Chain ID changed; refusing to send a transaction.');
    }

    const amount = parseEther('1');
    const senderBefore = await provider.getBalance(accounts.sender);
    const recipientBefore = await provider.getBalance(accounts.recipient);
    if (recipientBefore !== 0n) {
      throw new Error('Disposable recipient is not empty; refusing an ambiguous transfer.');
    }
    fs.writeFileSync(attemptPath, 'one local PW transfer started\n', {
      mode: 0o600,
      flag: 'wx',
    });

    const transaction = await wallet.sendTransaction({
      to: accounts.recipient,
      value: amount,
    });
    const receipt = await transaction.wait(1);
    if (!receipt || receipt.status !== 1) {
      throw new Error('Development transfer did not receive a successful receipt.');
    }

    const senderAfter = await provider.getBalance(accounts.sender);
    const recipientAfter = await provider.getBalance(accounts.recipient);
    const gasPrice = receipt.gasPrice ?? 0n;
    const gasFee = gasPrice * receipt.gasUsed;
    if (recipientAfter - recipientBefore !== amount) {
      throw new Error('Recipient balance change does not equal exactly 1 PW.');
    }
    if (senderBefore - senderAfter !== amount + gasFee) {
      throw new Error('Sender balance change does not equal transfer plus gas.');
    }

    const result = {
      chainId: Number(BigInt(chainId)),
      sender: accounts.sender,
      recipient: accounts.recipient,
      amountWei: amount.toString(),
      transactionHash: transaction.hash,
      receiptStatus: receipt.status,
      blockNumber: receipt.blockNumber,
      blockHash: receipt.blockHash,
      gasUsed: receipt.gasUsed.toString(),
      effectiveGasPrice: gasPrice.toString(),
      gasFeeWei: gasFee.toString(),
      senderBeforeWei: senderBefore.toString(),
      senderAfterWei: senderAfter.toString(),
      recipientBeforeWei: recipientBefore.toString(),
      recipientAfterWei: recipientAfter.toString(),
    };
    fs.writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`, {
      mode: 0o600,
      flag: 'wx',
    });
    console.log(`Verified 1 PW transfer. Tx: ${transaction.hash}`);
    console.log(`Block: ${receipt.blockNumber}; receipt status: ${receipt.status}`);
    console.log(`Sender: ${accounts.sender}; recipient: ${accounts.recipient}`);
  } finally {
    await provider.destroy();
  }
})().catch((error) => {
  console.error(`Transfer test failed: ${error.message}`);
  process.exitCode = 1;
});
