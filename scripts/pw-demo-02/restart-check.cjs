#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');

const workspaceRoot = path.resolve(__dirname, '../..');
const runtimeRoot = path.join(workspaceRoot, '.local-networks/pw-demo-02');
const statePath = path.join(runtimeRoot, 'data/network-state.env');
const readyPath = path.join(runtimeRoot, 'metadata/ready.json');
const transferPath = path.join(runtimeRoot, 'metadata/transfer.json');
const baselinePath = path.join(runtimeRoot, 'metadata/restart-baseline.json');
const reportPath = path.join(runtimeRoot, 'metadata/restart-verification.json');

if (!fs.existsSync(readyPath) || !fs.existsSync(transferPath)) {
  throw new Error('Startup and signed transfer must be verified before restart checks.');
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
if (!state.PRIMEWAVE_RPC_URL?.startsWith('http://127.0.0.1:')) {
  throw new Error('Restart check only permits a loopback RPC endpoint.');
}
const transfer = JSON.parse(fs.readFileSync(transferPath, 'utf8'));
const ready = JSON.parse(fs.readFileSync(readyPath, 'utf8'));
const requireFromIndexer = createRequire(path.join(workspaceRoot, 'indexer/package.json'));
const { JsonRpcProvider } = requireFromIndexer('ethers');

async function snapshot(provider) {
  const chainId = await provider.send('eth_chainId', []);
  const genesis = await provider.send('eth_getBlockByNumber', ['0x0', false]);
  const latest = await provider.send('eth_getBlockByNumber', ['latest', false]);
  const receipt = await provider.send('eth_getTransactionReceipt', [transfer.transactionHash]);
  const senderBalance = await provider.getBalance(transfer.sender);
  const recipientBalance = await provider.getBalance(transfer.recipient);
  if (!genesis || !latest || !receipt) throw new Error('Chain, block, or receipt is unavailable.');
  return {
    chainId,
    genesisHash: genesis.hash,
    latestNumber: Number(BigInt(latest.number)),
    latestHash: latest.hash,
    receiptStatus: Number(BigInt(receipt.status)),
    receiptBlockNumber: Number(BigInt(receipt.blockNumber)),
    receiptBlockHash: receipt.blockHash,
    senderBalanceWei: senderBalance.toString(),
    recipientBalanceWei: recipientBalance.toString(),
  };
}

(async () => {
  const provider = new JsonRpcProvider(state.PRIMEWAVE_RPC_URL);
  try {
    const current = await snapshot(provider);
    if (current.chainId !== '0x11f63') throw new Error('Unexpected EVM Chain ID.');
    if (current.genesisHash !== ready.genesisBlockHash) throw new Error('Genesis block hash differs from startup record.');
    if (current.receiptStatus !== 1) throw new Error('Transfer receipt is not successful.');

    if (process.argv[2] === 'capture') {
      if (fs.existsSync(baselinePath)) throw new Error('Restart baseline already exists; refusing overwrite.');
      if (fs.existsSync(reportPath)) throw new Error('Restart verification already exists.');
      const baseline = { ...current, transferHash: transfer.transactionHash };
      fs.writeFileSync(baselinePath, `${JSON.stringify(baseline, null, 2)}\n`, {
        mode: 0o600,
        flag: 'wx',
      });
      console.log(`Captured block ${current.latestNumber} and transfer receipt before stop.`);
      return;
    }

    if (process.argv[2] !== 'verify') {
      throw new Error('Expected capture or verify.');
    }
    if (!fs.existsSync(baselinePath)) throw new Error('No pre-stop baseline exists.');
    const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
    const priorBlock = await provider.send(
      'eth_getBlockByNumber',
      [`0x${baseline.latestNumber.toString(16)}`, false],
    );
    if (!priorBlock || priorBlock.hash !== baseline.latestHash) {
      throw new Error('Previously observed block hash did not survive restart.');
    }
    if (current.latestNumber < baseline.latestNumber) {
      throw new Error('Block height moved backwards after restart.');
    }
    for (const key of [
      'chainId', 'genesisHash', 'receiptStatus',
      'receiptBlockNumber', 'receiptBlockHash',
      'senderBalanceWei', 'recipientBalanceWei',
    ]) {
      if (current[key] !== baseline[key]) {
        throw new Error(`Restart persistence check failed for ${key}.`);
      }
    }
    const report = {
      verifiedAt: new Date().toISOString(),
      chainId: current.chainId,
      genesisHash: current.genesisHash,
      preservedBlockNumber: baseline.latestNumber,
      preservedBlockHash: baseline.latestHash,
      latestBlockNumber: current.latestNumber,
      transferHash: transfer.transactionHash,
      receiptStatus: current.receiptStatus,
      receiptBlockHash: current.receiptBlockHash,
      balancesPreserved: true,
    };
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, {
      mode: 0o600,
      flag: 'wx',
    });
    console.log(`Restart verified: chain, genesis, block ${baseline.latestNumber}, receipt, and balances persisted.`);
  } finally {
    await provider.destroy();
  }
})().catch((error) => {
  console.error(`Restart check failed: ${error.message}`);
  process.exitCode = 1;
});
