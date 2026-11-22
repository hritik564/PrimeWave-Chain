# PWCScan Mainnet Readiness

## Current behavior

- The root URL redirects to the Mainnet route regardless of a saved network
  preference. Explicit `/testnet/...` routes remain Testnet-scoped.
- Mainnet remains unconfigured unless all of the following are present:
  `VITE_MAINNET_INDEXER_API_URL`, `VITE_MAINNET_CHAIN_ID`, and
  `VITE_MAINNET_GENESIS_HASH`. The public frontend does not accept a direct
  Mainnet RPC URL.
- The indexer exposes a read-only `/identity` endpoint. It reads `eth_chainId`
  and the genesis block hash from its server-side `INDEXER_RPC_URL`; it never
  returns that RPC URL. Mainnet data is accepted only when the observed Chain
  ID and genesis hash match the frontend's expected values, and the indexer
  reports `verified: true`.
- Configure `INDEXER_EXPECTED_GENESIS_HASH` on the Mainnet indexer to bind its
  own RPC identity to the approved genesis hash. Without this server-side
  marker, the browser will refuse Mainnet data even if its other settings are
  present.
- Production indexers on any Chain ID other than historical Testnet 77 require
  `INDEXER_EXPECTED_GENESIS_HASH`; startup checks the live genesis hash before
  opening the database or applying migrations.
- The identity endpoint caches its RPC result for 15 seconds. The browser
  caches successful identity checks for 10 seconds. Explorer queries have an
  8-second timeout, one retry for transient failures, and a 10-second query
  freshness window. The identity endpoint opens a 10-second circuit after
  three consecutive RPC failures.
- API pagination remains read-only and bounded by `INDEXER_API_MAX_LIMIT`.
  Client page history now supports Previous/Next navigation and uses the
  indexer's `after` cursor contract.
- Testnet remains Chain ID 77. It is checked against the live RPC Chain ID;
  its genesis is observed but is not compared to a configured expected hash
  unless `VITE_TESTNET_GENESIS_HASH` is supplied.

## Existing data coverage and limits

- The indexer serves blocks, transactions and receipts, logs/events, address
  activity, validators, staking, rewards, fees, contracts, search, and stats.
- Address history comes from indexed activity. Current native PW balances are
  read through the server-side RPC client; RPC failures produce an unavailable
  value, and no balance is inferred from transaction history.
- Reward and fee totals remain unavailable until their contract is configured
  and the indexer confirms full chain coverage. Fee allocation percentages are
  calculated from indexed events rather than hardcoded.
- Contract records expose an indexed verified/unverified flag, but the API
  does not provide verified source, ABI, or read-only contract calls.
- The prior governance page displayed unverified multisig/timelock values and
  claimed there were no proposals. Those claims were removed; the explorer now
  reports governance data as unavailable because no verified source exists.
- Historical charts and a complete address/contract discovery history require
  additional indexed data and are not presented as available functionality.
- Reorg protection checks indexed block hashes against RPC and stops on parent
  hash inconsistency. It does not automatically delete or rebuild indexed
  rows; any reindex remains an explicit maintenance action.
- The API has bounded pagination and read-only routes, but no rate-limiting
  middleware was found. A public Mainnet deployment needs an approved abuse
  protection policy before launch.

## Operator access and launch gates

- No Clerk authentication, authorized operator identity, or verified
  operations telemetry source is configured in this workspace.
- No operator dashboard or telemetry endpoint is exposed. Do not add one until
  server-enforced authentication, an explicit operator allowlist, and trusted
  monitoring sources are provisioned.
- Production artifact configuration remains Testnet-only (Chain ID 77); this
  work does not change it or publish the Mainnet experience.
- Before enabling Mainnet, verify the approved Chain ID and genesis hash from
  launch evidence, configure the server-side RPC/indexer and expected genesis
  hash, configure the matching frontend identity values, then exercise identity
  mismatch and unavailable-RPC checks against a controlled test environment.
- Address balances, verified source/ABI, Mainnet contract values, and operator
  telemetry remain unavailable until their respective data sources and
  security gates exist.
