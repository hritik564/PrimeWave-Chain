-- PrimeWave Chain Indexer — Initial Schema
-- Migration 001: Full schema for C12 data layer
-- Do NOT modify after deployment. Add a new migration file for schema changes.

-- Migration tracking table
CREATE TABLE IF NOT EXISTS schema_migrations (
  version     INTEGER PRIMARY KEY,
  applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Sync State ────────────────────────────────────────────────────────────────
-- One row per (chain_id, registry_address). Tracks indexer progress.

CREATE TABLE IF NOT EXISTS sync_state (
  chain_id          BIGINT      PRIMARY KEY,
  latest_block      BIGINT      NOT NULL DEFAULT -1,
  latest_block_hash VARCHAR(66),
  is_syncing        BOOLEAN     NOT NULL DEFAULT TRUE,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Blocks ────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS blocks (
  number            BIGINT      PRIMARY KEY,
  hash              VARCHAR(66) NOT NULL UNIQUE,
  parent_hash       VARCHAR(66) NOT NULL,
  timestamp_unix    BIGINT      NOT NULL,
  gas_limit         TEXT        NOT NULL,
  gas_used          TEXT        NOT NULL,
  base_fee_per_gas  TEXT,
  transaction_count INTEGER     NOT NULL DEFAULT 0,
  coinbase          VARCHAR(42),
  state_root        VARCHAR(66),
  receipts_root     VARCHAR(66),
  indexed_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_blocks_hash         ON blocks (hash);
CREATE INDEX IF NOT EXISTS idx_blocks_timestamp     ON blocks (timestamp_unix DESC);

-- ── Transactions ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS transactions (
  hash               VARCHAR(66)  PRIMARY KEY,
  block_number       BIGINT       NOT NULL REFERENCES blocks(number) ON DELETE CASCADE,
  block_hash         VARCHAR(66)  NOT NULL,
  transaction_index  INTEGER      NOT NULL,
  from_address       VARCHAR(42)  NOT NULL,
  to_address         VARCHAR(42),
  value              TEXT         NOT NULL DEFAULT '0',
  gas_limit          TEXT         NOT NULL,
  gas_price          TEXT,
  max_fee_per_gas    TEXT,
  max_priority_fee   TEXT,
  nonce              BIGINT       NOT NULL,
  input              TEXT,
  chain_id           BIGINT,
  tx_type            INTEGER,
  indexed_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tx_block_number  ON transactions (block_number);
CREATE INDEX IF NOT EXISTS idx_tx_from          ON transactions (from_address);
CREATE INDEX IF NOT EXISTS idx_tx_to            ON transactions (to_address) WHERE to_address IS NOT NULL;

-- ── Transaction Receipts ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS transaction_receipts (
  tx_hash             VARCHAR(66)  PRIMARY KEY REFERENCES transactions(hash) ON DELETE CASCADE,
  block_number        BIGINT       NOT NULL,
  status              INTEGER,
  gas_used            TEXT         NOT NULL,
  cumulative_gas_used TEXT         NOT NULL,
  effective_gas_price TEXT,
  transaction_fee     TEXT,
  contract_address    VARCHAR(42),
  indexed_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_receipt_block  ON transaction_receipts (block_number);
CREATE INDEX IF NOT EXISTS idx_receipt_contract ON transaction_receipts (contract_address) WHERE contract_address IS NOT NULL;

-- ── Transaction Logs (raw EVM) ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS transaction_logs (
  id                BIGSERIAL    PRIMARY KEY,
  block_number      BIGINT       NOT NULL,
  block_hash        VARCHAR(66)  NOT NULL,
  tx_hash           VARCHAR(66)  NOT NULL,
  tx_index          INTEGER      NOT NULL,
  log_index         INTEGER      NOT NULL,
  contract_address  VARCHAR(42)  NOT NULL,
  topic0            VARCHAR(66),
  topic1            VARCHAR(66),
  topic2            VARCHAR(66),
  topic3            VARCHAR(66),
  data              TEXT,
  removed           BOOLEAN      NOT NULL DEFAULT FALSE,
  indexed_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_logs_block        ON transaction_logs (block_number);
CREATE INDEX IF NOT EXISTS idx_logs_contract      ON transaction_logs (contract_address);
CREATE INDEX IF NOT EXISTS idx_logs_topic0        ON transaction_logs (topic0) WHERE topic0 IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_logs_tx_hash       ON transaction_logs (tx_hash);
CREATE INDEX IF NOT EXISTS idx_logs_contract_t0   ON transaction_logs (contract_address, topic0) WHERE topic0 IS NOT NULL;

-- ── Decoded Protocol Events ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS decoded_events (
  id               BIGSERIAL    PRIMARY KEY,
  log_id           BIGINT       NOT NULL REFERENCES transaction_logs(id) ON DELETE CASCADE,
  block_number     BIGINT       NOT NULL,
  tx_hash          VARCHAR(66)  NOT NULL,
  contract_address VARCHAR(42)  NOT NULL,
  event_name       VARCHAR(100) NOT NULL,
  event_signature  VARCHAR(300) NOT NULL,
  decoded_json     JSONB        NOT NULL,
  indexed_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (log_id)
);

CREATE INDEX IF NOT EXISTS idx_decoded_block    ON decoded_events (block_number);
CREATE INDEX IF NOT EXISTS idx_decoded_contract ON decoded_events (contract_address);
CREATE INDEX IF NOT EXISTS idx_decoded_event    ON decoded_events (event_name);

-- ── Addresses ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS addresses (
  address          VARCHAR(42)  PRIMARY KEY,
  first_seen_block BIGINT       NOT NULL,
  last_seen_block  BIGINT       NOT NULL,
  tx_count         BIGINT       NOT NULL DEFAULT 0,
  sent_count       BIGINT       NOT NULL DEFAULT 0,
  received_count   BIGINT       NOT NULL DEFAULT 0,
  is_contract      BOOLEAN      NOT NULL DEFAULT FALSE,
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── Contracts ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS contracts (
  address          VARCHAR(42)  PRIMARY KEY,
  creation_tx      VARCHAR(66),
  creation_block   BIGINT,
  bytecode_hash    VARCHAR(66),
  is_verified      BOOLEAN      NOT NULL DEFAULT FALSE,
  is_known_protocol BOOLEAN     NOT NULL DEFAULT FALSE,
  protocol_name    VARCHAR(100),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── Validators ────────────────────────────────────────────────────────────────
-- Source of truth: PrimeWaveValidatorRegistry + ValidatorFeeVault events.
-- This is a MIRROR of chain state, not the authority.

CREATE TABLE IF NOT EXISTS validators (
  validation_id        VARCHAR(66)  PRIMARY KEY,
  reward_recipient     VARCHAR(42),
  acp99_weight         TEXT,
  uptime_bips          INTEGER,
  status               INTEGER,    -- ValidatorStatus enum value
  is_active_in_vault   BOOLEAN     NOT NULL DEFAULT FALSE,
  vault_base_weight    TEXT,
  vault_uptime_bips    INTEGER,
  total_fees_claimed   TEXT        NOT NULL DEFAULT '0',
  first_seen_block     BIGINT      NOT NULL,
  last_updated_block   BIGINT      NOT NULL,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_validators_status    ON validators (status);
CREATE INDEX IF NOT EXISTS idx_validators_recipient ON validators (reward_recipient)
  WHERE reward_recipient IS NOT NULL;

-- ── Validator Events ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS validator_events (
  id               BIGSERIAL    PRIMARY KEY,
  tx_hash          VARCHAR(66)  NOT NULL,
  block_number     BIGINT       NOT NULL,
  log_index        INTEGER      NOT NULL,
  validation_id    VARCHAR(66),
  event_name       VARCHAR(100) NOT NULL,
  contract_address VARCHAR(42)  NOT NULL,
  event_data       JSONB        NOT NULL,
  indexed_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_vev_vid   ON validator_events (validation_id) WHERE validation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_vev_block ON validator_events (block_number);

-- ── Staking Positions ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS staking_positions (
  validation_id  VARCHAR(66)  PRIMARY KEY,
  staker         VARCHAR(42)  NOT NULL,
  amount         TEXT         NOT NULL DEFAULT '0',
  stake_block    BIGINT       NOT NULL,
  is_returned    BOOLEAN      NOT NULL DEFAULT FALSE,
  return_block   BIGINT,
  updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_staking_staker ON staking_positions (staker);

-- ── Staking Events ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS staking_events (
  id             BIGSERIAL    PRIMARY KEY,
  tx_hash        VARCHAR(66)  NOT NULL,
  block_number   BIGINT       NOT NULL,
  log_index      INTEGER      NOT NULL,
  event_name     VARCHAR(100) NOT NULL,
  validation_id  VARCHAR(66),
  address        VARCHAR(42),
  amount         TEXT,
  event_data     JSONB        NOT NULL,
  indexed_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_staking_ev_block ON staking_events (block_number);
CREATE INDEX IF NOT EXISTS idx_staking_ev_vid   ON staking_events (validation_id)
  WHERE validation_id IS NOT NULL;

-- ── RewardVault State Snapshots ───────────────────────────────────────────────
-- One row per block where vault state changes.

CREATE TABLE IF NOT EXISTS reward_vault_state (
  id             SERIAL       PRIMARY KEY,
  block_number   BIGINT       NOT NULL UNIQUE,
  total_funded   TEXT         NOT NULL DEFAULT '0',
  total_emitted  TEXT         NOT NULL DEFAULT '0',
  emission_rate  TEXT         NOT NULL DEFAULT '0',
  updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── Reward Events ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS reward_events (
  id             BIGSERIAL    PRIMARY KEY,
  tx_hash        VARCHAR(66)  NOT NULL,
  block_number   BIGINT       NOT NULL,
  log_index      INTEGER      NOT NULL,
  event_name     VARCHAR(100) NOT NULL,
  recipient_id   VARCHAR(66),
  reward_address VARCHAR(42),
  amount         TEXT,
  event_data     JSONB        NOT NULL,
  indexed_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_reward_ev_block     ON reward_events (block_number);
CREATE INDEX IF NOT EXISTS idx_reward_ev_recipient ON reward_events (reward_address)
  WHERE reward_address IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reward_ev_rid       ON reward_events (recipient_id)
  WHERE recipient_id IS NOT NULL;

-- ── Fee Distribution ──────────────────────────────────────────────────────────
-- From FeeDistributor.FeeDistributed events — authoritative 70/20/10 split.

CREATE TABLE IF NOT EXISTS fee_distribution (
  id              BIGSERIAL    PRIMARY KEY,
  tx_hash         VARCHAR(66)  NOT NULL,
  block_number    BIGINT       NOT NULL,
  log_index       INTEGER      NOT NULL,
  total_amount    TEXT         NOT NULL,
  validator_share TEXT         NOT NULL,
  treasury_share  TEXT         NOT NULL,
  burn_share      TEXT         NOT NULL,
  indexed_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_fee_dist_block ON fee_distribution (block_number);

-- ── Governance Events ─────────────────────────────────────────────────────────
-- From EmergencyMultisig + PrimeWaveTimelock.

CREATE TABLE IF NOT EXISTS governance_events (
  id               BIGSERIAL    PRIMARY KEY,
  tx_hash          VARCHAR(66)  NOT NULL,
  block_number     BIGINT       NOT NULL,
  log_index        INTEGER      NOT NULL,
  contract_address VARCHAR(42)  NOT NULL,
  event_name       VARCHAR(100) NOT NULL,
  event_data       JSONB        NOT NULL,
  indexed_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_gov_ev_block    ON governance_events (block_number);
CREATE INDEX IF NOT EXISTS idx_gov_ev_contract ON governance_events (contract_address);

-- ── Record version in migration tracking ─────────────────────────────────────
INSERT INTO schema_migrations (version) VALUES (1)
ON CONFLICT (version) DO NOTHING;
