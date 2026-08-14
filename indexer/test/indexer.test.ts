/**
 * C12 Indexer Unit Tests
 *
 * Tests: RPC parsing, block/tx/log parsing, event decoding, domain handlers.
 * No real DB or RPC required — all external dependencies are mocked.
 */

import { parseBlock, IndexedBlock } from '../src/indexer/blocks';
import { parseTx, parseReceipt, parseLog } from '../src/indexer/transactions';
import { tryDecodeLog, registerContractAddress } from '../src/abi/events';
import { RpcBlock, RpcTransaction, RpcReceipt, RpcLog, hexToNumber, hexToBigInt, hexToDecStr } from '../src/rpc';
import { makeTestConfig } from '../src/config';

// ── Fixture data ──────────────────────────────────────────────────────────────

const SAMPLE_BLOCK: RpcBlock = {
  number:           '0x1',
  hash:             '0x' + 'aa'.repeat(32),
  parentHash:       '0x' + 'bb'.repeat(32),
  timestamp:        '0x64000000',
  gasLimit:         '0x1388',
  gasUsed:          '0x5208',
  baseFeePerGas:    '0x1',
  transactions:     [],
  miner:            '0x' + 'cc'.repeat(20),
  stateRoot:        '0x' + 'dd'.repeat(32),
  receiptsRoot:     '0x' + 'ee'.repeat(32),
};

const SAMPLE_TX: RpcTransaction = {
  hash:             '0x' + 'ff'.repeat(32),
  blockNumber:      '0x1',
  blockHash:        '0x' + 'aa'.repeat(32),
  transactionIndex: '0x0',
  from:             '0x' + '11'.repeat(20),
  to:               '0x' + '22'.repeat(20),
  value:            '0xde0b6b3a7640000', // 1 ETH in hex
  gas:              '0x5208',
  gasPrice:         '0x3b9aca00',
  nonce:            '0x5',
  input:            '0x',
  chainId:          '0x11f63', // 73571
  type:             '0x0',
};

const SAMPLE_RECEIPT: RpcReceipt = {
  transactionHash:   SAMPLE_TX.hash,
  blockNumber:       '0x1',
  blockHash:         '0x' + 'aa'.repeat(32),
  transactionIndex:  '0x0',
  from:              SAMPLE_TX.from,
  to:                SAMPLE_TX.to,
  status:            '0x1',
  gasUsed:           '0x5208',
  cumulativeGasUsed: '0x5208',
  effectiveGasPrice: '0x3b9aca00',
  contractAddress:   null,
  logs:              [],
};

const FD_ADDR = '0x' + 'fd'.repeat(20);

const FEE_DISTRIBUTED_LOG: RpcLog = {
  address:          FD_ADDR,
  topics:           [
    '0x' + 'a'.repeat(64), // placeholder topic0 — will use tryDecodeLog with registered iface
  ],
  data:             '0x',
  blockNumber:      '0x1',
  blockHash:        '0x' + 'aa'.repeat(32),
  transactionHash:  SAMPLE_TX.hash,
  transactionIndex: '0x0',
  logIndex:         '0x0',
};

// ── Hex util tests ────────────────────────────────────────────────────────────

describe('Hex utilities', () => {
  test('IDX-01: hexToNumber converts correctly', () => {
    expect(hexToNumber('0x1')).toBe(1);
    expect(hexToNumber('0x64')).toBe(100);
    expect(hexToNumber('0x11f63')).toBe(73571);
  });

  test('IDX-02: hexToBigInt handles large values', () => {
    const onePW = BigInt('1000000000000000000');
    expect(hexToBigInt('0xde0b6b3a7640000')).toBe(onePW);
  });

  test('IDX-03: hexToDecStr returns decimal string', () => {
    expect(hexToDecStr('0xde0b6b3a7640000')).toBe('1000000000000000000');
  });
});

// ── Block parsing ─────────────────────────────────────────────────────────────

describe('Block parser', () => {
  test('IDX-04: parseBlock extracts all fields', () => {
    const b: IndexedBlock = parseBlock(SAMPLE_BLOCK);
    expect(b.number).toBe(1);
    expect(b.hash).toBe(SAMPLE_BLOCK.hash.toLowerCase());
    expect(b.parentHash).toBe(SAMPLE_BLOCK.parentHash.toLowerCase());
    expect(b.timestampUnix).toBe(hexToNumber(SAMPLE_BLOCK.timestamp));
    expect(b.gasLimit).toBe('5000');
    expect(b.gasUsed).toBe('21000');
    expect(b.baseFeePerGas).toBe('1');
    expect(b.transactionCount).toBe(0);
    expect(b.coinbase).toBe(SAMPLE_BLOCK.miner!.toLowerCase());
  });

  test('IDX-05: parseBlock normalises hash to lowercase', () => {
    const upper = { ...SAMPLE_BLOCK, hash: '0x' + 'AA'.repeat(32) };
    const b = parseBlock(upper);
    expect(b.hash).toBe(b.hash.toLowerCase());
  });

  test('IDX-06: parseBlock handles missing optional fields', () => {
    const minimal: RpcBlock = {
      number:       '0x0',
      hash:         '0x' + '00'.repeat(32),
      parentHash:   '0x' + '00'.repeat(32),
      timestamp:    '0x0',
      gasLimit:     '0x0',
      gasUsed:      '0x0',
      transactions: [],
    };
    const b = parseBlock(minimal);
    expect(b.baseFeePerGas).toBeNull();
    expect(b.coinbase).toBeNull();
    expect(b.stateRoot).toBeNull();
    expect(b.receiptsRoot).toBeNull();
  });
});

// ── Transaction parsing ───────────────────────────────────────────────────────

describe('Transaction parser', () => {
  test('IDX-07: parseTx extracts all fields', () => {
    const tx = parseTx(SAMPLE_TX);
    expect(tx.hash).toBe(SAMPLE_TX.hash.toLowerCase());
    expect(tx.blockNumber).toBe(1);
    expect(tx.fromAddress).toBe(SAMPLE_TX.from.toLowerCase());
    expect(tx.toAddress).toBe(SAMPLE_TX.to!.toLowerCase());
    expect(tx.value).toBe('1000000000000000000');
    expect(tx.nonce).toBe(5);
    expect(tx.chainId).toBe(73571);
    expect(tx.txType).toBe(0);
  });

  test('IDX-08: parseTx handles null to (contract creation)', () => {
    const creationTx = { ...SAMPLE_TX, to: null };
    const tx = parseTx(creationTx);
    expect(tx.toAddress).toBeNull();
  });

  test('IDX-09: parseTx sets input to null for empty calldata', () => {
    const tx = parseTx(SAMPLE_TX);
    expect(tx.input).toBeNull(); // '0x' → null
  });

  test('IDX-10: parseTx preserves non-empty input', () => {
    const withData = { ...SAMPLE_TX, input: '0xdeadbeef' };
    const tx = parseTx(withData);
    expect(tx.input).toBe('0xdeadbeef');
  });
});

// ── Receipt parsing ───────────────────────────────────────────────────────────

describe('Receipt parser', () => {
  test('IDX-11: parseReceipt computes transaction fee', () => {
    const r = parseReceipt(SAMPLE_RECEIPT);
    // gasUsed=21000, effectiveGasPrice=1000000000 → fee=21000000000000
    expect(r.gasUsed).toBe('21000');
    expect(r.effectiveGasPrice).toBe('1000000000');
    expect(r.transactionFee).toBe((BigInt('21000') * BigInt('1000000000')).toString());
  });

  test('IDX-12: parseReceipt maps status correctly', () => {
    expect(parseReceipt(SAMPLE_RECEIPT).status).toBe(1);
    expect(parseReceipt({ ...SAMPLE_RECEIPT, status: '0x0' }).status).toBe(0);
  });

  test('IDX-13: parseReceipt handles missing effectiveGasPrice', () => {
    const r = parseReceipt({ ...SAMPLE_RECEIPT, effectiveGasPrice: undefined });
    expect(r.effectiveGasPrice).toBeNull();
    expect(r.transactionFee).toBeNull();
  });
});

// ── Log parsing ───────────────────────────────────────────────────────────────

describe('Log parser', () => {
  test('IDX-14: parseLog extracts all topic slots', () => {
    const rpcLog: RpcLog = {
      ...FEE_DISTRIBUTED_LOG,
      topics: ['0x1111', '0x2222', '0x3333', '0x4444'],
    };
    const l = parseLog(rpcLog);
    expect(l.topic0).toBe('0x1111');
    expect(l.topic1).toBe('0x2222');
    expect(l.topic2).toBe('0x3333');
    expect(l.topic3).toBe('0x4444');
  });

  test('IDX-15: parseLog fills missing topics with null', () => {
    const l = parseLog({ ...FEE_DISTRIBUTED_LOG, topics: ['0xAAA'] });
    expect(l.topic0).toBe('0xaaa');
    expect(l.topic1).toBeNull();
    expect(l.topic2).toBeNull();
    expect(l.topic3).toBeNull();
  });

  test('IDX-16: parseLog sets data to null for empty calldata', () => {
    const l = parseLog({ ...FEE_DISTRIBUTED_LOG, data: '0x' });
    expect(l.data).toBeNull();
  });
});

// ── Event decoding ─────────────────────────────────────────────────────────────

describe('Event decoder (tryDecodeLog)', () => {
  const config = makeTestConfig();

  // Register the test contract addresses so the decoder knows which iface to use
  beforeAll(() => {
    registerContractAddress(config.contracts.feeDistributor!, 'feeDistributor');
    registerContractAddress(config.contracts.validatorRegistry!, 'validatorRegistry');
  });

  test('IDX-17: unknown topic returns null without throwing', () => {
    const result = tryDecodeLog(
      config.contracts.feeDistributor!,
      ['0x' + 'deadbeef'.padEnd(64, '0')],
      '0x'
    );
    expect(result).toBeNull();
  });

  test('IDX-18: empty topics returns null', () => {
    const result = tryDecodeLog(config.contracts.feeDistributor!, [], '0x');
    expect(result).toBeNull();
  });

  test('IDX-19: FeeDistributed decodes correctly', () => {
    // Manually encode a FeeDistributed log
    const { Interface, AbiCoder } = require('ethers');
    const iface = new Interface([
      'event FeeDistributed(uint256 amount, uint256 validatorShare, uint256 treasuryShare, uint256 burnShare, uint256 indexed blockNumber)',
    ]);
    const fragment = iface.getEvent('FeeDistributed')!;
    const topic0 = fragment.topicHash;

    // ABI-encode non-indexed params
    const coder = AbiCoder.defaultAbiCoder();
    const data  = coder.encode(
      ['uint256', 'uint256', 'uint256', 'uint256'],
      [1000n, 700n, 200n, 100n]
    );
    // blockNumber is indexed
    const blockNumTopic = '0x' + (1n).toString(16).padStart(64, '0');
    const topics = [topic0, blockNumTopic];

    const result = tryDecodeLog(config.contracts.feeDistributor!, topics, data);
    expect(result).not.toBeNull();
    expect(result!.eventName).toBe('FeeDistributed');
    expect(result!.args['amount']).toBe('1000');
    expect(result!.args['validatorShare']).toBe('700');
    expect(result!.args['treasuryShare']).toBe('200');
    expect(result!.args['burnShare']).toBe('100');
  });

  test('IDX-20: ValidatorRegistered (registry) decodes correctly', () => {
    const { Interface, AbiCoder, zeroPadValue, getBytes } = require('ethers');
    const iface = new Interface([
      'event ValidatorRegistered(bytes32 indexed validationID, address indexed rewardRecipient, uint64 acp99Weight, uint16 uptimeBips)',
    ]);
    const fragment = iface.getEvent('ValidatorRegistered')!;
    const topic0 = fragment.topicHash;

    const validationID   = '0x' + '01'.repeat(32);
    const rewardRecipient = '0x' + '11'.repeat(20);
    const topic1 = validationID;
    const topic2 = '0x' + '00'.repeat(12) + rewardRecipient.slice(2);

    const coder = AbiCoder.defaultAbiCoder();
    const data  = coder.encode(['uint64', 'uint16'], [1000n, 9000n]);

    const result = tryDecodeLog(config.contracts.validatorRegistry!, [topic0, topic1, topic2], data);
    expect(result).not.toBeNull();
    expect(result!.eventName).toBe('ValidatorRegistered');
    expect(result!.args['acp99Weight']).toBe('1000');
    expect(result!.args['uptimeBips']).toBe('9000');
  });

  test('IDX-21: bigint args are serialised to strings', () => {
    const { Interface, AbiCoder } = require('ethers');
    const iface = new Interface([
      'event RewardVaultFunded(address indexed funder, uint256 amount, uint256 newTotalFunded)',
    ]);
    const fragment = iface.getEvent('RewardVaultFunded')!;
    const funderAddr = '0x' + '11'.repeat(20);
    const topic1 = '0x' + '00'.repeat(12) + funderAddr.slice(2);
    const coder = AbiCoder.defaultAbiCoder();
    const data  = coder.encode(['uint256', 'uint256'], [BigInt('15000000000000000000000000'), BigInt('15000000000000000000000000')]);

    registerContractAddress(config.contracts.rewardVault!, 'rewardVault');
    const result = tryDecodeLog(config.contracts.rewardVault!, [fragment.topicHash, topic1], data);
    expect(result).not.toBeNull();
    expect(typeof result!.args['amount']).toBe('string');
    expect(result!.args['amount']).toBe('15000000000000000000000000');
  });
});

// ── Config tests ──────────────────────────────────────────────────────────────

describe('Config', () => {
  test('IDX-22: makeTestConfig returns valid config', () => {
    const config = makeTestConfig();
    expect(config.chainId).toBe(73571);
    expect(config.contracts.feeDistributor).not.toBeNull();
    expect(config.logLevel).toBe('error');
  });
});
