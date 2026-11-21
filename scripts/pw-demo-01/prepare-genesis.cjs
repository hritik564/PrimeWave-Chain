#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');

const workspaceRoot = path.resolve(__dirname, '../..');
const requireFromIndexer = createRequire(
  path.join(workspaceRoot, 'indexer/package.json'),
);
const { Wallet, parseEther } = requireFromIndexer('ethers');

const [sourcePath, outputPath, senderKeyPath, accountsPath] =
  process.argv.slice(2);
if (!sourcePath || !outputPath || !senderKeyPath || !accountsPath) {
  throw new Error('Expected source genesis, output genesis, key path, accounts path.');
}

for (const target of [outputPath, senderKeyPath, accountsPath]) {
  if (fs.existsSync(target)) {
    throw new Error(`Refusing to overwrite existing runtime file: ${target}`);
  }
}

const source = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));
const sender = Wallet.createRandom();
const recipient = Wallet.createRandom();
source.alloc ??= {};
source.alloc[sender.address.toLowerCase()] = {
  balance: `0x${parseEther('10000').toString(16)}`,
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true, mode: 0o700 });
fs.mkdirSync(path.dirname(senderKeyPath), { recursive: true, mode: 0o700 });
fs.mkdirSync(path.dirname(accountsPath), { recursive: true, mode: 0o700 });
fs.writeFileSync(outputPath, `${JSON.stringify(source, null, 2)}\n`, {
  mode: 0o600,
  flag: 'wx',
});
fs.writeFileSync(senderKeyPath, `${sender.privateKey}\n`, {
  mode: 0o600,
  flag: 'wx',
});
fs.writeFileSync(
  accountsPath,
  `${JSON.stringify(
    {
      sender: sender.address,
      recipient: recipient.address,
      allocation: '10000 PW',
    },
    null,
    2,
  )}\n`,
  { mode: 0o600, flag: 'wx' },
);
console.log(`Prepared isolated genesis. Sender: ${sender.address}`);
console.log(`Disposable recipient: ${recipient.address}`);
