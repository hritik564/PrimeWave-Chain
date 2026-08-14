# PW-C13 PWCScan Routes Reference

**Sprint:** C13  
**Status:** COMPLETE — LOCKED  
**Date:** 2026-08-14

---

## Route Map

| Route | Component | API Hooks | Description |
|---|---|---|---|
| `/` | `Home` | `useStats`, `useBlocks`, `useTransactions` | Network dashboard + hero |
| `/blocks` | `Blocks` | `useBlocks` | Paginated block list |
| `/blocks/:number` | `BlockDetail` | `useBlock` | Block detail + prev/next nav |
| `/transactions` | `Transactions` | `useTransactions` | Paginated transaction list |
| `/tx/:hash` | `TransactionDetail` | `useTransaction` | Tx detail: overview + logs + raw |
| `/address/:address` | `AddressDetail` | `useAddress`, `useAddressTransactions`, `useStakingByAddress`, `useRewardsByAddress` | Address detail with 4 tabs |
| `/contracts` | `Contracts` | `useContracts` | Contract directory |
| `/validators` | `Validators` | `useValidators`, `useStats` | Validator directory with status filter |
| `/validator/:id` | `ValidatorDetail` | `useValidator`, `useValidatorEvents` | Validator overview + events tab |
| `/staking` | `Staking` | `useStaking`, `useStats` | Staking dashboard |
| `/rewards` | `Rewards` | `useStats` | RewardVault dashboard + reserve bar |
| `/fees` | `Fees` | `useFees`, `useStats` | Fee distribution dashboard |
| `/governance` | `Governance` | *(decoded events from fee/validator endpoints)* | Governance event log |
| `/stats` | `Stats` | `useStats` | Full network statistics grid |
| `/search` | `SearchResults` | `useSearch` | Search redirect page |
| `*` | `NotFound` | — | 404 page with nav links |

---

## Page Specifications

### `/` — Homepage

**Purpose**: Network at-a-glance dashboard.

**Hero Section**:
- "PrimeWave Explorer" heading
- Subtitle describing the explorer
- `Chain ID: 73571` badge
- Sync status badge (`Synced` / `Syncing...`)

**Metrics Grid** (6 cards, 3-column on desktop):
1. Latest Block — `stats.network.currentBlock`
2. Total Transactions — `stats.transactions.total` + TPS subtitle
3. Active Validators — `stats.validators.activeCount`
4. RewardVault Remaining — `stats.rewardVault.totalFunded` (note: display total funded as proxy until remaining is broken out)
5. Fees Distributed — `stats.fees.totalDistributed`
6. Gas Latest Block — `stats.gas.gasUsedLatestBlock`

**Latest Blocks** (10 rows): Block # | Age | Miner | Txns → links to `/blocks/:number`

**Latest Transactions** (10 rows): Tx Hash | Block | From | To | Value → links to `/tx/:hash`

**Auto-refresh**: Polls every 10 seconds when `settings.autoRefresh` is true.

---

### `/blocks` — Block List

**Table columns**: Block # | Age | Txns | Gas Used | Gas Limit | Gas % (GasBar) | Miner

**Pagination**: Cursor-based (Next/Previous). Shows "Showing latest blocks" label.

---

### `/blocks/:number` — Block Detail

**Header card fields**:
- Block number (large)
- Timestamp (local/UTC toggle via settings)
- Hash + CopyButton
- Parent Hash → link to previous block
- Transactions count
- Gas Used / Gas Limit (with GasBar)
- Base Fee Per Gas
- Miner (AddressDisplay)
- State Root
- Receipts Root

**Navigation**: ← Previous Block | Next Block → buttons

**Note**: No direct block→transactions endpoint in C12. A note directs users to search by address or tx hash for transactions in this block.

---

### `/transactions` — Transaction List

**Table columns**: Status | Tx Hash | Age | Block # | From | To | Value | Fee

**Status badge**: Green (status=1) / Red (status=0)  
**Value**: `formatPW(value)`  
**Fee**: `formatPW(transaction_fee)` or `—`

---

### `/tx/:hash` — Transaction Detail

**Tabs**: Overview | Event Logs | Raw

**Overview fields**:
- Status badge (Success/Failed)
- Transaction Hash + CopyButton
- Block # → link
- Timestamp
- From → AddressDisplay → link
- To → AddressDisplay → link (or "Contract Creation" badge)
- Value
- Transaction Fee
- Gas Used
- Gas Price / Max Fee / Max Priority Fee
- Nonce
- Input Data (monospace, collapsible)

**Event Logs tab**: Lists `decodedEvents` array. Each rendered via `EventLogItem`.

**Raw tab**: Full JSON dump of the transaction + logs in monospace `<pre>`.

---

### `/address/:address` — Address Detail

**Header card**:
- Address (full + CopyButton + QRModal)
- `is_contract` → "Contract" badge
- `is_known_protocol` → protocol name badge (e.g. "RewardVault")
- Tx count, first/last seen block

**Tabs**:
1. **Transactions** — `useAddressTransactions` paginated table
2. **Logs** — decoded events where `contract_address` = this address (for contracts)
3. **Staking** — `useStakingByAddress` → StakingPosition table
4. **Rewards** — `useRewardsByAddress` → RewardEvent table

**Native PW Balance**: C12 does not index `eth_getBalance`. The balance field shows `—`. (Per C12 data contract — documented limitation.)

---

### `/contracts` — Contract Directory

**Filter toggle**: "Known Protocol Contracts" / "All Contracts"

**Table columns**: Protocol Badge | Address | Created Block | Tx Count

---

### `/validators` — Validator Directory

**Metric cards**: Active Validators | Total Validator Rewards

**Status filter tabs**: All | Active | Pending

**Table columns**: Validator ID | Status | Reward Recipient | Uptime | Total Claimed

---

### `/validator/:id` — Validator Detail

**Header**: Validation ID (monospace) + status badge + "Active in Vault" badge if applicable

**Tabs**:
1. **Overview** — all fields as `<dl>` rows: reward_recipient, uptime_bips, acp99_weight, vault_base_weight, total_fees_claimed, first/last block
2. **Events** — `useValidatorEvents` paginated list → event name + block + tx hash + JSON payload

---

### `/staking` — Staking Dashboard

**Metric cards** (from `useStats`): Active Validators | Total Staking Emitted | Emission Rate | RewardVault Remaining

**Recent Staking Events table**: Tx Hash | Action | Validator | Staker | Amount

---

### `/rewards` — RewardVault Dashboard

**Header**: "PrimeWave RewardVault" with shield icon

**ReserveBar**: Visual funded/emitted/remaining progress bar

**Metric cards**: Total Funded | Total Emitted | Remaining | Emission Rate (annual)

**Footer note**: Links to `/validators` for per-validator claim history.

---

### `/fees` — Fee Distribution Dashboard

**Visual split bar**: 70% Validators (green) | 20% Treasury (blue) | 10% Burn (red)

**Metric cards**: Total Distributed | To Validators | To Treasury | Burned

**Recent Fee Distributions table**: Tx Hash | Block | Total Fee | To Validators (70%) | To Treasury (20%) | Burned (10%)

---

### `/governance` — Governance Activity

**Info cards**:
- Emergency Multisig: 3-of-5 threshold
- Timelock: 48 hours minimum delay

**Governance Events table**: Shows decoded events filtered to governance-related event names (ProposalCreated, ProposalApproved, ProposalExecuted, ProposalCancelled, OperationScheduled, OperationExecuted).

---

### `/stats` — Network Statistics

**Metric grid** (7 cards): Current Block | Transactions | TPS (60s avg) | Active Validators | RewardVault Remaining | RewardVault Emitted | Fees Distributed | Fees to Validators | Gas Limit | Gas Used

**Historical Charts section**: Recharts area/line charts — rendered when data available, empty state with clear messaging when insufficient data.

---

### `/search?q=` — Search Results

**Behavior**: Immediately redirects based on the `SearchResult.type` from the `/search?q=` API:
- `block` → `/blocks/:number`
- `transaction` → `/tx/:hash`
- `address` → `/address/:address`
- `validator` → `/validator/:id`
- `not_found` / `invalid_format` → shows EmptyState with explanation

---

## SEO Title Pattern

| Route | `<title>` |
|---|---|
| `/` | `PWCScan — PrimeWave Blockchain Explorer` |
| `/blocks` | `Blocks — PWCScan` |
| `/blocks/:n` | `Block #N — PWCScan` |
| `/transactions` | `Transactions — PWCScan` |
| `/tx/:hash` | `Tx 0x1234...ABCD — PWCScan` |
| `/address/:addr` | `Address 0x1234...ABCD — PWCScan` |
| `/validators` | `Validators — PWCScan` |
| `/validator/:id` | `Validator :id — PWCScan` |
| `/contracts` | `Contracts — PWCScan` |
| `/staking` | `Staking — PWCScan` |
| `/rewards` | `RewardVault — PWCScan` |
| `/fees` | `Fee Distribution — PWCScan` |
| `/governance` | `Governance — PWCScan` |
| `/stats` | `Network Statistics — PWCScan` |
| `*` | `Not Found — PWCScan` |
