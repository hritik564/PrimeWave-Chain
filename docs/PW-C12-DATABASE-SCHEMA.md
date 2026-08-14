# PW-C12: Database Schema

**Sprint:** C12 — RPC + Indexing + Chain Data Layer
**Migration:** `indexer/src/db/migrations/001_initial.sql`
**Database:** PostgreSQL
**Table count:** 17

---

## Schema Overview

```
schema_migrations      — migration tracking
sync_state             — indexer progress per chain
blocks                 — indexed block headers
transactions           — indexed transactions
transaction_receipts   — indexed receipts
transaction_logs       — raw EVM logs
decoded_events         — decoded protocol events
addresses              — observed addresses
contracts              — contract-specific data
validators             — PrimeWave validator mirror
validator_events       — validator lifecycle events
staking_positions      — staking position mirror
staking_events         — staking lifecycle events
reward_vault_state     — RewardVault state snapshots
reward_events          — RewardVault events
fee_distribution       — FeeDistributor.FeeDistributed events
governance_events      — EMS + Timelock events
```

---

## Table Definitions

### `schema_migrations`

Tracks applied migrations. Safe to run multiple times.

| Column | Type | Constraint |
|---|---|---|
| version | INTEGER | PRIMARY KEY |
| applied_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() |

---

### `sync_state`

One row per indexed chain. Updated atomically inside each block's transaction.

| Column | Type | Constraint |
|---|---|---|
| chain_id | BIGINT | PRIMARY KEY |
| latest_block | BIGINT | NOT NULL DEFAULT -1 |
| latest_block_hash | VARCHAR(66) | |
| is_syncing | BOOLEAN | NOT NULL DEFAULT TRUE |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() |

---

### `blocks`

| Column | Type | Notes |
|---|---|---|
| number | BIGINT | PRIMARY KEY |
| hash | VARCHAR(66) | UNIQUE |
| parent_hash | VARCHAR(66) | |
| timestamp_unix | BIGINT | Seconds since epoch |
| gas_limit | TEXT | Decimal string (BigInt-safe) |
| gas_used | TEXT | Decimal string |
| base_fee_per_gas | TEXT | Nullable (EIP-1559) |
| transaction_count | INTEGER | |
| coinbase | VARCHAR(42) | |
| state_root | VARCHAR(66) | |
| receipts_root | VARCHAR(66) | |
| indexed_at | TIMESTAMPTZ | |

**Indexes:** `idx_blocks_hash`, `idx_blocks_timestamp`

---

### `transactions`

| Column | Type | Notes |
|---|---|---|
| hash | VARCHAR(66) | PRIMARY KEY |
| block_number | BIGINT | FK → blocks.number |
| block_hash | VARCHAR(66) | |
| transaction_index | INTEGER | |
| from_address | VARCHAR(42) | lowercase |
| to_address | VARCHAR(42) | nullable (contract creation) |
| value | TEXT | Decimal wei |
| gas_limit | TEXT | |
| gas_price | TEXT | nullable |
| max_fee_per_gas | TEXT | nullable (EIP-1559) |
| max_priority_fee | TEXT | nullable (EIP-1559) |
| nonce | BIGINT | |
| input | TEXT | null for empty calldata |
| chain_id | BIGINT | |
| tx_type | INTEGER | 0=legacy, 2=EIP-1559 |
| indexed_at | TIMESTAMPTZ | |

**Indexes:** `idx_tx_block_number`, `idx_tx_from`, `idx_tx_to`

---

### `transaction_receipts`

| Column | Type | Notes |
|---|---|---|
| tx_hash | VARCHAR(66) | PRIMARY KEY FK → transactions.hash |
| block_number | BIGINT | |
| status | INTEGER | 0=fail, 1=success |
| gas_used | TEXT | |
| cumulative_gas_used | TEXT | |
| effective_gas_price | TEXT | |
| transaction_fee | TEXT | gasUsed × effectiveGasPrice |
| contract_address | VARCHAR(42) | non-null for contract creation |
| indexed_at | TIMESTAMPTZ | |

**Indexes:** `idx_receipt_block`, `idx_receipt_contract`

---

### `transaction_logs`

Raw EVM logs. All events stored regardless of decodability.

| Column | Type | Notes |
|---|---|---|
| id | BIGSERIAL | PRIMARY KEY |
| block_number | BIGINT | |
| block_hash | VARCHAR(66) | |
| tx_hash | VARCHAR(66) | |
| tx_index | INTEGER | |
| log_index | INTEGER | |
| contract_address | VARCHAR(42) | |
| topic0 | VARCHAR(66) | |
| topic1 | VARCHAR(66) | |
| topic2 | VARCHAR(66) | |
| topic3 | VARCHAR(66) | |
| data | TEXT | null if empty |
| removed | BOOLEAN | |
| indexed_at | TIMESTAMPTZ | |

**Unique:** `(tx_hash, log_index)`

**Indexes:** `idx_logs_block`, `idx_logs_contract`, `idx_logs_topic0`, `idx_logs_tx_hash`, `idx_logs_contract_t0`

---

### `decoded_events`

Decoded PrimeWave protocol events. One row per successfully decoded log.

| Column | Type | Notes |
|---|---|---|
| id | BIGSERIAL | PRIMARY KEY |
| log_id | BIGINT | FK → transaction_logs.id |
| block_number | BIGINT | |
| tx_hash | VARCHAR(66) | |
| contract_address | VARCHAR(42) | |
| event_name | VARCHAR(100) | |
| event_signature | VARCHAR(300) | |
| decoded_json | JSONB | all args, BigInt → string |
| indexed_at | TIMESTAMPTZ | |

**Unique:** `(log_id)` — one decoded result per log

**Indexes:** `idx_decoded_block`, `idx_decoded_contract`, `idx_decoded_event`

---

### `addresses`

All addresses observed as tx sender, recipient, event emitter, or contract creator.

| Column | Type | Notes |
|---|---|---|
| address | VARCHAR(42) | PRIMARY KEY (lowercase) |
| first_seen_block | BIGINT | |
| last_seen_block | BIGINT | |
| tx_count | BIGINT | sent + received |
| sent_count | BIGINT | |
| received_count | BIGINT | |
| is_contract | BOOLEAN | |
| updated_at | TIMESTAMPTZ | |

---

### `contracts`

Additional data for contract addresses.

| Column | Type | Notes |
|---|---|---|
| address | VARCHAR(42) | PRIMARY KEY |
| creation_tx | VARCHAR(66) | |
| creation_block | BIGINT | |
| bytecode_hash | VARCHAR(66) | future use |
| is_verified | BOOLEAN | source not verified in C12 |
| is_known_protocol | BOOLEAN | true for PrimeWave core contracts |
| protocol_name | VARCHAR(100) | e.g. "FeeDistributor" |
| updated_at | TIMESTAMPTZ | |

---

### `validators`

Mirror of validator state from PrimeWaveValidatorRegistry and ValidatorFeeVault.

> CRITICAL: This is NOT the authoritative source. Chain state is authoritative.

| Column | Type | Notes |
|---|---|---|
| validation_id | VARCHAR(66) | PRIMARY KEY (bytes32) |
| reward_recipient | VARCHAR(42) | current reward recipient |
| acp99_weight | TEXT | from registry |
| uptime_bips | INTEGER | from registry |
| status | INTEGER | ValidatorStatus enum |
| is_active_in_vault | BOOLEAN | from VFV events |
| vault_base_weight | TEXT | from VFV |
| vault_uptime_bips | INTEGER | from VFV |
| total_fees_claimed | TEXT | running sum from VFV.ValidatorFeeClaimed |
| first_seen_block | BIGINT | |
| last_updated_block | BIGINT | |
| updated_at | TIMESTAMPTZ | |

**Indexes:** `idx_validators_status`, `idx_validators_recipient`

---

### `validator_events`

All validator-related events from both PrimeWaveValidatorRegistry and ValidatorFeeVault.

| Column | Type | Notes |
|---|---|---|
| id | BIGSERIAL | PRIMARY KEY |
| tx_hash | VARCHAR(66) | |
| block_number | BIGINT | |
| log_index | INTEGER | |
| validation_id | VARCHAR(66) | nullable (some events have no vid) |
| event_name | VARCHAR(100) | |
| contract_address | VARCHAR(42) | source contract |
| event_data | JSONB | |
| indexed_at | TIMESTAMPTZ | |

**Unique:** `(tx_hash, log_index)`

---

### `staking_positions`

One row per validator stake from PrimeWaveStakingManager.

| Column | Type | Notes |
|---|---|---|
| validation_id | VARCHAR(66) | PRIMARY KEY |
| staker | VARCHAR(42) | |
| amount | TEXT | decimal wei |
| stake_block | BIGINT | |
| is_returned | BOOLEAN | |
| return_block | BIGINT | |
| updated_at | TIMESTAMPTZ | |

---

### `staking_events`

| Column | Type | Notes |
|---|---|---|
| id | BIGSERIAL | PRIMARY KEY |
| tx_hash | VARCHAR(66) | |
| block_number | BIGINT | |
| log_index | INTEGER | |
| event_name | VARCHAR(100) | |
| validation_id | VARCHAR(66) | nullable |
| address | VARCHAR(42) | staker or recipient |
| amount | TEXT | decimal wei |
| event_data | JSONB | |
| indexed_at | TIMESTAMPTZ | |

---

### `reward_vault_state`

Snapshots of RewardVault state, one row per block where state changes.

| Column | Type | Notes |
|---|---|---|
| id | SERIAL | PRIMARY KEY |
| block_number | BIGINT | UNIQUE |
| total_funded | TEXT | |
| total_emitted | TEXT | cumulative |
| emission_rate | TEXT | wei/second |
| updated_at | TIMESTAMPTZ | |

---

### `reward_events`

Events from RewardVault contract.

| Column | Type | Notes |
|---|---|---|
| id | BIGSERIAL | PRIMARY KEY |
| tx_hash | VARCHAR(66) | |
| block_number | BIGINT | |
| log_index | INTEGER | |
| event_name | VARCHAR(100) | |
| recipient_id | VARCHAR(66) | bytes32 recipient ID |
| reward_address | VARCHAR(42) | |
| amount | TEXT | decimal wei |
| event_data | JSONB | |
| indexed_at | TIMESTAMPTZ | |

---

### `fee_distribution`

From `FeeDistributor.FeeDistributed`. Authoritative 70/20/10 split record.

| Column | Type | Notes |
|---|---|---|
| id | BIGSERIAL | PRIMARY KEY |
| tx_hash | VARCHAR(66) | |
| block_number | BIGINT | |
| log_index | INTEGER | |
| total_amount | TEXT | decimal wei |
| validator_share | TEXT | 70% |
| treasury_share | TEXT | 20% |
| burn_share | TEXT | 10% |
| indexed_at | TIMESTAMPTZ | |

**Invariant:** `total_amount = validator_share + treasury_share + burn_share` (INDEX-11)

---

### `governance_events`

Events from EmergencyMultisig and PrimeWaveTimelock.

| Column | Type | Notes |
|---|---|---|
| id | BIGSERIAL | PRIMARY KEY |
| tx_hash | VARCHAR(66) | |
| block_number | BIGINT | |
| log_index | INTEGER | |
| contract_address | VARCHAR(42) | |
| event_name | VARCHAR(100) | |
| event_data | JSONB | |
| indexed_at | TIMESTAMPTZ | |

---

## Known Event Index

| Event | Source Contract | topic0 Computed From |
|---|---|---|
| `FeeReceived` | FeeDistributor | `keccak256("FeeReceived(uint256,uint256,address)")` |
| `FeeDistributed` | FeeDistributor | `keccak256("FeeDistributed(uint256,uint256,uint256,uint256,uint256)")` |
| `ValidatorRegistered` | ValidatorFeeVault | `keccak256("ValidatorRegistered(bytes32,address,uint128,uint16)")` |
| `ValidatorActivated` | ValidatorFeeVault | `keccak256("ValidatorActivated(bytes32)")` |
| `ValidatorDeactivated` | ValidatorFeeVault | `keccak256("ValidatorDeactivated(bytes32,uint256)")` |
| `ValidatorFeeClaimed` | ValidatorFeeVault | `keccak256("ValidatorFeeClaimed(bytes32,address,uint256)")` |
| `ValidatorRegistered` | PrimeWaveValidatorRegistry | `keccak256("ValidatorRegistered(bytes32,address,uint64,uint16)")` |
| `ValidatorSynced` | PrimeWaveValidatorRegistry | `keccak256("ValidatorSynced(bytes32,uint8,bool)")` |
| `RewardVaultFunded` | RewardVault | `keccak256("RewardVaultFunded(address,uint256,uint256)")` |
| `RewardClaimed` | RewardVault | `keccak256("RewardClaimed(bytes32,address,uint256)")` |
| `StakeDeposited` | PrimeWaveStakingManager | `keccak256("StakeDeposited(bytes32,address,uint256)")` |
| `StakeReturned` | PrimeWaveStakingManager | `keccak256("StakeReturned(address,uint256)")` |
| `ProposalCreated` | EmergencyMultisig | `keccak256("ProposalCreated(bytes32,address,address,bytes,uint256)")` |
| `OperationScheduled` | PrimeWaveTimelock | `keccak256("OperationScheduled(bytes32,address,address,bytes,bytes32,bytes32,uint256)")` |
