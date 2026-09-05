# MAINNET-1 — ARCHITECTURE FREEZE PACKAGE

**Project:** PrimeWave Chain  
**Phase:** MAINNET-1 — Architecture Freeze  
**Scope:** Planning and architecture only  
**Status:** Prepared for owner decisions

## Scope and safety boundary

[ESTABLISHED] The Replit migration is closed. Chain 77 is the validated test environment.

[ESTABLISHED] This package does not:

- deploy anything;
- provision servers;
- modify Netcup;
- modify Chain 77;
- generate keys;
- access secrets;
- create wallets;
- create a genesis;
- deploy contracts;
- modify production infrastructure;
- start production services; or
- make blockchain transactions.

[ESTABLISHED] Testnet facts are reference evidence only. They are not automatically mainnet approvals.

## 1. Executive Summary

[ESTABLISHED] PrimeWave Chain has a validated software and testnet architecture consisting of a sovereign Avalanche L1, validator nodes, RPC access, an indexer, PostgreSQL, a keeper, PWCScan, protocol contracts, governance controls, and operational documentation.

[TESTNET VERIFIED] The current Chain 77 reference includes:

- Chain ID `77`;
- a sovereign Avalanche L1 on Fuji;
- four currently live validators;
- external RPC access;
- nginx-based edge proxying;
- seven deployed protocol contracts;
- verified fee distribution;
- an external indexer and PostgreSQL data layer;
- a keeper architecture for synchronizing validator state; and
- PWCScan explorer architecture.

[ESTABLISHED] Older C14 documentation describes a five-validator testnet target, but the current validated Chain 77 state is four live validators. Neither number is a mainnet decision.

[MAINNET DECISION] The mainnet architecture must be approved as a set of boundaries and responsibilities before mainnet identity, genesis, keys, infrastructure, or deployment work begins.

[IMPLEMENTATION REQUIRED] Replit remains the development and preparation environment. Mainnet runtime services should run externally.

[SECURITY REVIEW REQUIRED] The highest-risk boundaries are:

- public Internet to RPC and explorer edge;
- application services to blockchain RPC;
- keeper signing authority;
- governance signing authority;
- validator administration;
- PostgreSQL access and backup custody; and
- production recovery procedures.

[MAINNET DECISION] StakingManager is an explicit launch decision. If mainnet includes staking, validator registration, or dynamic reward claims, unresolved StakingManager behavior blocks that launch scope.

## 2. Responsibility Matrix

### 2.1 Responsibility ownership

| Component | Owner / responsibility | Inputs | Outputs | Dependencies | Security boundary | Failure boundary |
|---|---|---|---|---|---|---|
| Source code | [ESTABLISHED] Replit project and maintainers | Approved requirements, source changes, tests | Versioned source and release artifacts | Repository, review process | No production credentials or private keys | Build or review failure does not directly stop a running chain |
| Development | [ESTABLISHED] Replit | Local chain, fixtures, test configuration | Development builds and test results | Local toolchain and packages | Development identities must not cross into production | Local development failure is isolated from mainnet |
| Testing | [ESTABLISHED] Replit | Contracts, indexer, keeper, UI, testnet evidence | Test reports and release evidence | Test runners and controlled RPC access | Test credentials must be separate | Test failure blocks release preparation, not live production by itself |
| Builds | [ESTABLISHED] Replit | Pinned source and dependency versions | Binaries, bundles, deployment artifacts | Reproducible build environment | Artifacts must be integrity-checked before external use | Build failure blocks the affected release |
| Architecture | [ESTABLISHED] Replit with owner approval | Repository evidence and operational lessons | Approved architecture and decision register | Owner decisions | Architecture documents must not contain secrets | Ambiguity blocks dependent implementation |
| Deployment preparation | [ESTABLISHED] Replit; execution external | Approved identities, manifests, scripts, runbooks | Dry-run and ceremony packages | Architecture, tokenomics, governance | No broadcast or production key access during preparation | Preparation failure blocks deployment |
| Genesis tooling | [ESTABLISHED] Replit | Approved mainnet decisions and identities | Reproducible genesis inputs and validators | Chain identity, validator design, tokenomics | No mainnet genesis creation during MAINNET-1 | Invalid or unreproducible artifact blocks genesis |
| Dry-run preparation | [ESTABLISHED] Replit; dry run external and isolated | Approved architecture and test credentials | Rehearsal plan and evidence | All upstream architecture decisions | Must not touch Chain 77 or production | Failed rehearsal blocks ceremony |
| Documentation | [ESTABLISHED] Replit | Decisions, evidence, runbooks | Reviewable project records | Owner approvals | Do not record secrets or private key material | Missing documentation blocks sign-off |
| Release artifacts | [ESTABLISHED] Replit | Tested source and configuration templates | Immutable release package | Build and security review | Artifact hashes and provenance required | Untrusted artifact cannot be deployed |
| Validators | [IMPLEMENTATION REQUIRED] External mainnet operator(s) | Mainnet genesis, chain configuration, validator keys | Consensus, blocks, peer health | Approved infrastructure, networking, key custody | Validator admin must be private; P2P is separately controlled | Validator failure affects liveness or validator weight |
| RPC | [IMPLEMENTATION REQUIRED] External RPC operator(s) | Validator RPC backends, edge policy | Public, private, indexer, and keeper RPC | Validators, nginx/edge, TLS, monitoring | Public access must not expose admin methods | RPC failure affects clients and dependent services, not necessarily consensus |
| Indexer | [IMPLEMENTATION REQUIRED] External service operator | Read-only blockchain RPC | Indexed blocks, transactions, events, API data | RPC, PostgreSQL, contract manifest | Indexer signer authority is not required | Indexer failure affects data freshness, not chain state |
| PostgreSQL | [IMPLEMENTATION REQUIRED] External database operator | Indexer writes, migration artifacts | Durable indexed data and sync state | Indexer, storage, backups | Private network and credential isolation | Database failure affects explorer/indexer state |
| Keeper | [IMPLEMENTATION REQUIRED] External operations operator | Read RPC, contract state, approved transaction signer | Permissionless synchronization transactions and health metrics | Mainnet RPC, Registry, PoAManager, state file | Keeper key is not governance authority; custody remains pending | Keeper failure delays synchronization and must be recoverable |
| PWCScan | [IMPLEMENTATION REQUIRED] External application operator | Indexer API, approved RPC links, network metadata | Public explorer pages and API consumption | Indexer, edge proxy, TLS | Public UI must not expose internal administration | Explorer failure does not stop consensus |
| Nginx/TLS | [IMPLEMENTATION REQUIRED] External edge operator | Public routes, certificates, backend targets | HTTPS edge access, routing, rate limiting | DNS, certificates, RPC/API/explorer services | Edge is the public trust boundary | Edge failure affects public access |
| Monitoring | [IMPLEMENTATION REQUIRED] External operations owner | Metrics and health endpoints | Dashboards, alerts, escalation | All production components | Monitoring credentials are read-only wherever possible | Monitoring failure can hide incidents and requires independent checks |
| Backups | [IMPLEMENTATION REQUIRED] External recovery owner | Database, configuration, state, approved operational records | Encrypted recovery artifacts | Storage, encryption, access policy | Backup custody must not expose signing keys | Backup failure affects recovery, not normal operation |
| Production key custody | [SECURITY REVIEW REQUIRED] Owner-approved custody participants | Governance, validator, keeper, and deployment key material | Controlled signing capability | Ceremony, hardware, backup, rotation policy | Separate signing domains and least privilege | Key loss or compromise can affect control or recovery |

### 2.2 Boundary rules

[ESTABLISHED] Replit may prepare artifacts but does not become the production runtime by default.

[SECURITY REVIEW REQUIRED] Production private keys, database credentials, keeper credentials, validator keys, and governance signer material must remain outside source control and outside ordinary development configuration.

[MAINNET DECISION] The owner must assign named operational ownership for validators, RPC, indexer/PostgreSQL, keeper, PWCScan, monitoring, backups, and incident response.

## 3. Mainnet Component Architecture

### 3.1 Logical request and consensus path

```text
                         Public users and applications
                                      │
                                      ▼
                         Public RPC / Explorer edge
                         (HTTPS, TLS, rate limits)
                                      │
                 ┌────────────────────┴────────────────────┐
                 │                                         │
                 ▼                                         ▼
          Public RPC service                         PWCScan web app
                 │                                         │
                 ▼                                         ▼
          Mainnet RPC layer ───────────────► Indexer API
                 │                                         │
                 ▼                                         ▼
             Validators ─────────────────► PostgreSQL
                 │                                         │
                 ▼                                         ▼
             PrimeWave L1 ◄─────────────── Indexer sync
```

[ESTABLISHED] Public RPC and explorer traffic must terminate at an edge layer rather than exposing validator administration.

[SECURITY REVIEW REQUIRED] The diagram represents logical trust boundaries, not a server or IP allocation.

### 3.2 Indexing path

```text
Validators
    │
    ▼
Private or allowlisted read-only RPC
    │
    ▼
Indexer engine
    │  writes blocks, transactions, receipts, logs, domains, sync state
    ▼
PostgreSQL
    │  read-only application queries
    ▼
Indexer API
    │
    ▼
PWCScan
```

[ESTABLISHED] The C12 architecture co-locates the indexer and read-only API in one service while preserving a future process split.

[IMPLEMENTATION REQUIRED] Mainnet configuration must replace development and testnet RPC URLs, Chain IDs, start block, confirmations, and contract addresses.

### 3.3 Keeper path

```text
P-Chain / native validator-manager state
              │
              ▼
        Keeper read loop
              │
              ▼
     Mainnet read/write RPC
              │
              ▼
 ValidatorRegistry / PoAManager / protocol contracts
              │
              ▼
    Permissionless synchronization transactions
```

[TESTNET VERIFIED] The keeper is intended to synchronize validator state because external validator-manager state does not directly trigger EVM registry updates.

[TESTNET VERIFIED] The keeper's supported operations are operational synchronization calls. It cannot register validators, change emission rates, withdraw funds, change fee splits, or alter governance.

[MAINNET DECISION] Keeper redundancy and custody remain unresolved.

### 3.4 Governance path

```text
Approved governance operators
              │
              ▼
        Multisig approval
              │
              ▼
        PrimeWaveTimelock
              │
              ▼
 Protocol administration and ordinary changes
              │
              ▼
 ValidatorRegistry / treasury / rewards / fees / staking

Emergency event
              │
              ▼
     EmergencyMultisig
              │
              ▼
 Narrow pause / freeze controls only
```

[TESTNET VERIFIED] The existing governance reference separates ordinary timelocked administration from narrowly scoped emergency pause controls.

[MAINNET DECISION] Mainnet signer identities, signer custody, thresholds, role separation, and final emergency scope require owner approval.

### 3.5 Monitoring path

```text
Validators ─┐
RPC        ─┤
Indexer    ─┤
Keeper     ─┤──► Metrics / health collection ─► Dashboards / alerts
PostgreSQL ─┤
PWCScan    ─┘
```

[IMPLEMENTATION REQUIRED] Monitoring must be independent enough to detect failures in the applications it monitors.

[MAINNET DECISION] Alert ownership, escalation, on-call coverage, and incident response authority remain open.

## 4. Component Dependency Map

```text
MAINNET ARCHITECTURE DECISIONS
       │
       ├──► Chain identity ───────────────┐
       ├──► Tokenomics and allocations ───┤
       ├──► Validator policy ─────────────┤
       ├──► Governance and custody ───────┤
       └──► Operations and recovery ──────┤
                                          ▼
                              Genesis and deployment design
                                          │
              ┌───────────────────────────┼───────────────────────────┐
              ▼                           ▼                           ▼
       Validator layer              Contract layer                Edge layer
       - AvalancheGo               - EMS                         - RPC edge
       - subnet-EVM                - Timelock                     - PWCScan edge
       - validator keys            - Registry                     - TLS/DNS
       - P2P                        - FeeVault
                                  - Treasury
                                  - FeeDistributor
                                  - RewardVault
                                  - StakingManager
                                          │
              ┌───────────────────────────┼───────────────────────────┐
              ▼                           ▼                           ▼
           RPC layer                  Keeper layer                Data layer
       - public RPC                - read state                  - indexer
       - private RPC               - submit sync txs              - PostgreSQL
       - indexer RPC               - state file                  - explorer API
       - keeper RPC                - health/metrics
                                          │
                                          ▼
                                  Monitoring and recovery
```

### Dependency rules

- [ESTABLISHED] Genesis depends on chain identity, validator design, gas policy, and approved allocations.
- [IMPLEMENTATION REQUIRED] ValidatorRegistry depends on the final native validator-manager integration.
- [IMPLEMENTATION REQUIRED] ValidatorFeeVault depends on ValidatorRegistry.
- [IMPLEMENTATION REQUIRED] FeeDistributor depends on the final fee destinations and fee policy.
- [IMPLEMENTATION REQUIRED] RewardVault depends on approved emission, funding, administration, and pause controls.
- [MAINNET DECISION] StakingManager dependencies and launch status are unresolved.
- [IMPLEMENTATION REQUIRED] Indexer depends on mainnet RPC and the final contract address manifest.
- [IMPLEMENTATION REQUIRED] PWCScan depends on the indexer API, network identity, and RPC links.
- [IMPLEMENTATION REQUIRED] Keeper depends on mainnet RPC, ValidatorRegistry, PoAManager, and approved transaction custody.
- [IMPLEMENTATION REQUIRED] Monitoring depends on health and metrics surfaces from every service.
- [IMPLEMENTATION REQUIRED] Recovery depends on backups, clean rebuild procedures, and assigned owners.

## 5. Validator Design

### 5.1 Chain 77 reference architecture

[TESTNET VERIFIED]

- Current validated Chain 77 state has four live validators.
- The validators run the approved AvalancheGo/subnet-EVM combination for the testnet.
- Validator P2P networking is separate from public RPC access.
- Public RPC is served externally through an edge proxy.
- The live testnet uses external infrastructure rather than Replit as its validator runtime.

[ESTABLISHED] C14 architecture documentation describes a five-validator rehearsal target, but that was a target topology rather than proof that five validators are currently live.

### 5.2 Candidate mainnet architecture

[MAINNET DECISION] The candidate architecture is:

- A validator set with an owner-approved count, not automatically four.
- Validators distributed across more than one geographic location.
- Validators distributed across more than one infrastructure/provider failure domain where practical.
- Private validator administration.
- Restricted P2P access between approved peers.
- Public RPC nodes without validator signing keys.
- Separate operational services for indexer, keeper, explorer, and monitoring.
- Documented replacement and recovery paths.

No final validator count is selected in MAINNET-1.

### 5.3 Validator decisions required

| Area | Current evidence | Mainnet decision |
|---|---|---|
| Validator count | [TESTNET VERIFIED] Four currently live on Chain 77; older design target was five | [MAINNET DECISION] Approve initial and target count |
| Geographic diversity | [ESTABLISHED] Testnet provides an operational reference only | [MAINNET DECISION] Approve regions and minimum separation |
| Provider diversity | [ESTABLISHED] Provider concentration is a failure-domain concern | [MAINNET DECISION] Approve whether multiple providers are required |
| Hardware | [ESTABLISHED] Testnet hardware is not a mainnet sizing approval | [MAINNET DECISION] Approve sizing method and baseline |
| Storage | [ESTABLISHED] Fast durable storage is required for node state | [MAINNET DECISION] Approve capacity, endurance, and replacement policy |
| Networking | [ESTABLISHED] P2P and RPC must be separate | [IMPLEMENTATION REQUIRED] Produce firewall and routing design |
| Validator key custody | [SECURITY REVIEW REQUIRED] Mainnet keys have not been generated | [MAINNET DECISION] Approve custody and ceremony model |
| Node recovery | [IMPLEMENTATION REQUIRED] Clean rebuild and rejoin must be documented | [MAINNET DECISION] Assign recovery owner and target |
| Validator replacement | [MAINNET DECISION] Admission/removal policy is unresolved | Approve replacement authority and procedure |
| Upgrade coordination | [IMPLEMENTATION REQUIRED] Coordinated software upgrades are required | [MAINNET DECISION] Approve rollout authority and abort criteria |
| Monitoring | [IMPLEMENTATION REQUIRED] Process, peers, blocks, resources, and network require monitoring | [MAINNET DECISION] Assign alert ownership |

### 5.4 Validator security boundary

[SECURITY REVIEW REQUIRED]

- Validator administration must not be reachable from the public Internet.
- P2P access must be limited to the required network policy.
- Validator keys must be separate from governance, treasury, deployer, and keeper keys.
- A public RPC node must not carry validator signing authority.
- Validator backups must not become an uncontrolled copy of private keys.

## 6. RPC Design

### 6.1 Logical RPC classes

| RPC class | Consumers | Access | Capabilities | Mainnet status |
|---|---|---|---|---|
| Public RPC | Users and applications | Public through edge | Public JSON-RPC methods, subject to policy | [MAINNET DECISION] Topology and limits |
| Private RPC | Operators and trusted services | Private or allowlisted | Broader read access as approved | [MAINNET DECISION] Network and access model |
| Indexer RPC | Indexer | Private or allowlisted | Read-only chain data | [IMPLEMENTATION REQUIRED] Mainnet endpoint and failover |
| Keeper RPC | Keeper | Private or allowlisted | Read state and submit keeper transactions | [MAINNET DECISION] Redundancy and custody |
| Validator administration | Node operators | Local or secure administration network only | Node control and administration | [SECURITY REVIEW REQUIRED] Must never be public |
| Monitoring RPC/health | Monitoring | Private or authenticated | Health and metrics collection | [IMPLEMENTATION REQUIRED] Read-only monitoring path |

### 6.2 Edge architecture

```text
Public Internet
      │
      ▼
DNS / TLS edge
      │
      ├──► Public JSON-RPC route ──► RPC backend pool
      ├──► PWCScan route ──────────► Explorer backend
      └──► Public API route ───────► Indexer API

Private administration network
      │
      ├──► Indexer RPC
      ├──► Keeper RPC
      ├──► Monitoring endpoints
      └──► Validator administration
```

[IMPLEMENTATION REQUIRED] Nginx or an equivalent edge proxy must provide TLS termination, request controls, routing, health checks, and access logging.

[SECURITY REVIEW REQUIRED] Public routes must block validator administrative methods and must not expose internal service ports directly.

### 6.3 Rate limiting and health

[IMPLEMENTATION REQUIRED]

- Public RPC requires request and connection limits.
- Backend health checks must detect unavailable or stale RPC nodes.
- The edge must fail over without exposing private node administration.
- RPC error rate and latency must be monitored.
- Public abuse must not be allowed to starve indexer or keeper traffic.

[MAINNET DECISION] The project must approve public quotas, authentication requirements for private routes, and whether paid or authenticated access is needed.

### 6.4 WebSocket

[TESTNET VERIFIED] The testnet architecture documents JSON-RPC and WebSocket as possible public RPC functions, while the indexer uses polling rather than WebSocket subscriptions.

[MAINNET DECISION] Approve whether mainnet public WebSocket access is required.

[IMPLEMENTATION REQUIRED] If enabled, WebSocket connections need separate limits, idle timeouts, health checks, and failover behavior.

### 6.5 Archive requirements

[MAINNET DECISION] Approve whether the mainnet must provide:

- Full historical state queries.
- Archive state.
- Historical logs only.
- A separate archive provider.
- Internal archive access limited to indexer or analytics.

No archive requirement is assumed from the testnet.

## 7. Indexer / PostgreSQL Design

### 7.1 Data path

```text
Mainnet validators
        │
        ▼
Read-only / allowlisted RPC
        │
        ▼
Indexer engine + read-only API
        │
        ├── writes ──► PostgreSQL
        │
        └── serves ──► PWCScan
```

[ESTABLISHED] The C12 indexer is a TypeScript/Node.js service with a poll-based sync engine, PostgreSQL storage, and a read-only REST API.

[TESTNET VERIFIED] The indexer test suite and schema were validated during the testnet preparation work. Live mainnet performance and recovery remain future work.

### 7.2 Database boundary

[SECURITY REVIEW REQUIRED]

- PostgreSQL must be private and unavailable to the public Internet.
- Only the indexer migration/write role may write indexed data.
- PWCScan receives API responses, not direct database access.
- Operators receive database access only through approved administrative paths.
- Database credentials must be external to source control.

### 7.3 RPC read-only boundary

[IMPLEMENTATION REQUIRED]

The indexer should use RPC for:

- Block and transaction retrieval.
- Receipt and log retrieval.
- Current chain head.
- Chain ID verification.
- Contract code detection.

The indexer should not require blockchain signing authority.

### 7.4 Indexer write authority

[IMPLEMENTATION REQUIRED]

- The indexer writes only to its own schema/data store.
- It must not have authority to submit blockchain transactions.
- It must not have governance, treasury, validator, or keeper signing keys.
- Migrations must be reviewed and versioned.

### 7.5 Replay and consistency

[TESTNET VERIFIED] The existing indexer design includes:

- Transactional sync-state updates.
- Restart from the last committed block.
- Idempotent writes.
- Parent-hash verification.
- Retry handling for transient RPC failures.
- Raw storage of unknown events without stopping the indexer.

[IMPLEMENTATION REQUIRED] Mainnet must define:

- Start block.
- Confirmation depth.
- Reorganization handling.
- Replay authorization.
- Maximum replay scope.
- Operational procedure for a corrupt or stale index.

### 7.6 Backup and restore

[IMPLEMENTATION REQUIRED]

- PostgreSQL backups must be encrypted.
- Backup retention must be approved.
- Restore must be tested on isolated infrastructure.
- Indexer replay must be available if a database is lost.
- Backup freshness must be monitored.
- Database credentials must not be stored with backups in recoverable plaintext.

[MAINNET DECISION] The project must assign database backup ownership and approve RPO/RTO targets.

### 7.7 Failover and monitoring

[IMPLEMENTATION REQUIRED]

Monitor:

- Chain head.
- Indexed head.
- Indexer lag.
- Database availability.
- Database storage.
- Migration state.
- RPC error rate.
- Parent-hash consistency.

[MAINNET DECISION] Approve the failover model: rebuild, standby instance, managed database, or another owner-approved approach.

## 8. Keeper Design

### 8.1 Responsibilities

[TESTNET VERIFIED] The keeper is an operational synchronization service. Its intended responsibilities are:

- Read native validator-manager state.
- Compare it to ValidatorRegistry state.
- Submit permissionless synchronization calls.
- Track pending and successful synchronizations.
- Retry transient failures.
- Expose health and metrics.

[TESTNET VERIFIED] The keeper cannot:

- Register new validators.
- Set emission rates.
- Withdraw funds.
- Change fee splits.
- Alter governance.

### 8.2 RPC and contract access

[IMPLEMENTATION REQUIRED]

The mainnet keeper requires:

- Read access to mainnet RPC.
- Contract addresses for ValidatorRegistry and validator-manager integration.
- Ability to submit only the approved operational synchronization transactions.
- Gas funding sufficient for operations.
- Confirmation and retry policy.

[SECURITY REVIEW REQUIRED] The keeper must not receive protocol-admin, treasury, multisig, validator-staking, or deployment authority.

### 8.3 State-file architecture

[TESTNET VERIFIED] The keeper state design includes:

- Chain ID.
- Registry address.
- Last poll time and block.
- Per-validator status.
- Pending sync status.
- Failure counters.
- Last successful sync.
- Last transaction hash.
- Atomic temporary-file write followed by rename.

[IMPLEMENTATION REQUIRED] Mainnet state must be isolated from testnet and local state.

[SECURITY REVIEW REQUIRED] State files may contain operational metadata but must not contain private keys.

### 8.4 Transaction authority

[MAINNET DECISION] The final custody model for the keeper signer is unresolved.

The keeper signer should be:

- Dedicated to keeper operations.
- Separate from all governance, treasury, validator, and deployer keys.
- Limited to gas funding and permissionless calls.
- Rotatable without changing protocol administration.

### 8.5 Redundancy and duplicate execution

[MAINNET DECISION] Choose between:

- Active/passive keeper instances.
- Multiple active keepers with idempotent execution.
- A policy-controlled scheduler.
- Another owner-approved model.

[TESTNET VERIFIED] The underlying synchronization calls are designed to be safe to repeat.

[IMPLEMENTATION REQUIRED] Multiple keeper instances still require coordination for:

- Transaction nonce handling.
- Gas competition.
- Alert deduplication.
- State ownership.
- Recovery after a partial submission.

### 8.6 Failure recovery and monitoring

[IMPLEMENTATION REQUIRED]

Monitor:

- Poll freshness.
- Consecutive RPC failures.
- Pending synchronizations.
- Transaction failures.
- Stale state.
- Gas balance.
- Keeper process and health endpoint.

[MAINNET DECISION] Assign the keeper recovery owner and approve the operational response to an unavailable keeper.

## 9. PWCScan Design

### 9.1 Public explorer path

```text
User
  │
  ▼
HTTPS PWCScan edge
  │
  ▼
PWCScan application
  │
  ├──► Indexer API
  └──► Approved public RPC links
```

[IMPLEMENTATION REQUIRED] PWCScan must receive network metadata through an explicit mainnet configuration, including:

- Mainnet network name.
- Mainnet Chain ID.
- Mainnet RPC links.
- Mainnet indexer API URL.
- Mainnet contract addresses.
- Mainnet explorer metadata.

### 9.2 Safety requirements

[ESTABLISHED] The architecture must retain the testnet safety improvement:

**NO SILENT LOCAL 73571 FALLBACK.**

[SECURITY REVIEW REQUIRED] PWCScan must also enforce:

**NO TESTNET ADDRESS FALLBACK.**

[IMPLEMENTATION REQUIRED]

- Missing mainnet Chain ID must be a visible configuration error.
- Missing mainnet contract addresses must be a visible configuration error.
- Testnet addresses must not be silently substituted.
- Local development endpoints must not be used by a production build.
- The visible network identity must match the connected RPC.

### 9.3 Synchronization and outage behavior

[IMPLEMENTATION REQUIRED]

PWCScan must distinguish:

- Explorer application unavailable.
- Indexer API unavailable.
- Indexer behind chain head.
- RPC unavailable.
- Database or indexer synchronization failure.

The UI should show an explicit unavailable or stale state rather than displaying fabricated or stale-looking success data.

[MAINNET DECISION] Approve public availability targets and outage communication ownership.

### 9.4 Public/private boundary

[SECURITY REVIEW REQUIRED]

- PWCScan may expose public indexed data.
- PWCScan must not expose PostgreSQL directly.
- PWCScan must not expose keeper state or health internals beyond approved public status.
- PWCScan deployment administration must be private.
- Internal API credentials must not be shipped to the browser.

## 10. Governance / Control Design

### 10.1 Control map

| Component | Technical control relationship | Ordinary governance | Emergency control | Mainnet status |
|---|---|---|---|---|
| EmergencyMultisig | Pause/freeze authority for the explicitly approved contracts | Not a general administrator | Immediate narrow pause/unpause only | [MAINNET DECISION] Final signers, threshold, and scope |
| PrimeWaveTimelock | Delayed protocol administration | Multisig proposal plus timelock execution | Not a bypass for ordinary changes | [MAINNET DECISION] Delay and roles |
| Treasury | Holds project-controlled funds | Separate treasury administration path | No emergency fund movement by default | [MAINNET DECISION] Custody and spending policy |
| ValidatorRegistry | Tracks validator and fee-accounting state | Protocol/validator governance path | No unrestricted emergency validator changes | [IMPLEMENTATION REQUIRED] Final manager and admin wiring |
| PoAManager | Native validator-manager authority | Validator lifecycle according to approved policy | Native control behavior must be reviewed | [MAINNET DECISION] Validator governance relationship |
| RewardVault | Holds and distributes approved rewards | Timelocked parameter/admin control | Emergency pause as approved | [MAINNET DECISION] Emission and administrator |
| FeeDistributor | Routes fees to approved destinations | Timelocked fee policy | Emergency pause as approved | [MAINNET DECISION] Fee split and pause authority |
| StakingManager | Staking, validator/delegator relationship, and reward claims if launched | Governance-controlled protocol path | Emergency pause as approved | [MAINNET DECISION] Launch scope and authority |

### 10.2 Existing evidence

[TESTNET VERIFIED] The testnet governance implementation and tests provide a reference for:

- EmergencyMultisig behavior.
- Timelock-controlled routine administration.
- Pause controls.
- Role separation.
- Fee, reward, and validator control relationships.

[TESTNET VERIFIED] The documented testnet governance reference uses a 3-of-5 emergency multisig and a 48-hour timelock.

[MAINNET DECISION] Those values must not be silently promoted to mainnet. The owner must explicitly approve or change them.

### 10.3 Emergency versus routine controls

[ESTABLISHED] Emergency controls should be narrow and reversible:

- Pause an affected protocol component.
- Freeze only explicitly approved functionality.
- Do not transfer funds.
- Do not change supply.
- Do not upgrade contracts.
- Do not change validators unless separately approved by the ordinary governance path.

[MAINNET DECISION] The owner must approve the final emergency action list and the unpause authority.

[ESTABLISHED] Routine controls should be:

- Proposed by the approved governance authority.
- Subject to timelock where applicable.
- Publicly reviewable through on-chain transactions.
- Executed only after the approved delay.

### 10.4 Validator-related controls

[IMPLEMENTATION REQUIRED] Validator-related controls must identify:

- Native validator-manager authority.
- ValidatorRegistry authority.
- Keeper operational authority.
- Protocol administration authority.
- Validator removal and replacement authority.

[SECURITY REVIEW REQUIRED] A keeper must not be able to change validator membership merely because it can submit synchronization transactions.

## 11. StakingManager Decision

### 11.1 Why it exists

[ESTABLISHED] StakingManager is intended to provide the protocol-level relationship between staking/delegation behavior, validators, rewards, and claims.

[IMPLEMENTATION REQUIRED] Its final scope must be explicit before any mainnet feature depends on it.

### 11.2 Components that may depend on it

| Component | Relationship | Status |
|---|---|---|
| ValidatorRegistry | May consume or coordinate validator registration and status | [MAINNET DECISION] Interface and authority unresolved |
| RewardVault | Supplies or accounts for validator/delegator rewards | [MAINNET DECISION] Claim and funding relationship unresolved |
| FeeDistributor | May be separate from staking rewards but must not conflict with fee accounting | [IMPLEMENTATION REQUIRED] Verify final boundaries |
| Keeper | Synchronizes native validator-manager state, not necessarily staking state | [ESTABLISHED] Keep operational synchronization separate |
| PWCScan/indexer | Indexes staking and reward events | [IMPLEMENTATION REQUIRED] Final ABI/events/configuration required |
| Governance | Controls pause, upgrade, and parameters | [MAINNET DECISION] Final role ownership unresolved |

### 11.3 Required behavior decisions

[MAINNET DECISION]

- Whether staking is in the initial mainnet launch.
- Whether deposits and withdrawals exist at launch.
- Whether delegation exists at launch.
- Validator registration flow.
- Reward accrual and claim flow.
- Reward recipient and accounting model.
- Validator removal and exit behavior.
- Any slashing or penalty behavior.
- Emergency pause behavior.
- Upgrade authority.
- Interaction with PoAManager.

### 11.4 Does unresolved functionality block mainnet?

[MAINNET DECISION] The owner must explicitly decide whether mainnet launches with staking.

[TECHNICAL RECOMMENDATION] If mainnet includes staking, validator registration through StakingManager, or dynamic reward claims, unresolved StakingManager behavior is a launch blocker. The protocol, keeper, indexer, explorer, and security review cannot be considered complete until the interfaces and failure modes are implemented and tested.

[TECHNICAL RECOMMENDATION] A PoA-only launch without staking-dependent rewards could be architecturally separated, but that would require an explicit owner decision, disabled or excluded staking-dependent behavior, and a revised tokenomics and launch scope. It must not be assumed.

[ESTABLISHED] StakingManager is not implemented in this phase.

## 12. Monitoring Design

### 12.1 Validator domain

[IMPLEMENTATION REQUIRED]

Monitor:

- Process health.
- Peer count and peer identity.
- Block production.
- Missed or delayed blocks.
- Disk capacity and I/O.
- CPU.
- Memory.
- Network connectivity.
- Version consistency.
- Configuration hash.

[MAINNET DECISION] Assign validator alert ownership and escalation.

### 12.2 RPC domain

[IMPLEMENTATION REQUIRED]

Monitor:

- Availability.
- Request latency.
- Error rate.
- Backend health.
- Failover status.
- Public rate-limit events.
- WebSocket health if enabled.
- Chain ID and head consistency.

[MAINNET DECISION] Assign public RPC incident ownership.

### 12.3 Indexer and database domain

[IMPLEMENTATION REQUIRED]

Monitor:

- Chain head.
- Indexed head.
- Indexing lag.
- Parent-hash consistency.
- RPC retry and error rate.
- Database availability.
- Database storage.
- Migration state.
- Backup freshness.

[MAINNET DECISION] Assign database and indexer alert ownership.

### 12.4 Keeper domain

[IMPLEMENTATION REQUIRED]

Monitor:

- Poll freshness.
- Action success.
- Action failure.
- Stale state.
- Pending synchronization count.
- Transaction errors.
- RPC errors.
- Gas balance.
- Health endpoint.

[MAINNET DECISION] Assign keeper operations and failure-response ownership.

### 12.5 PWCScan domain

[IMPLEMENTATION REQUIRED]

Monitor:

- Public availability.
- Indexer API availability.
- Synchronization status.
- API response errors.
- Configuration/network identity.
- TLS health.

[MAINNET DECISION] Assign explorer ownership and public status communication.

### 12.6 Infrastructure domain

[IMPLEMENTATION REQUIRED]

Monitor:

- TLS certificates.
- Backups.
- Storage.
- CPU and memory.
- Service health.
- Firewall or edge errors.
- Time synchronization.

[MAINNET DECISION] Alert ownership and escalation remain open for every domain.

## 13. Backup / Recovery Design

| Domain | What is backed up | Where it is backed up | Encryption requirement | Restore procedure | Recovery dependency | Security owner |
|---|---|---|---|---|---|---|
| Validators | Approved configuration, deployment metadata, operational records; node state only where useful and safe | [MAINNET DECISION] Separate protected recovery storage | [SECURITY REVIEW REQUIRED] Encrypted at rest and in transit | Rebuild clean node, restore approved config, rejoin according to validator procedure | Genesis, validator identity, approved keys, networking | [MAINNET DECISION] Validator recovery owner |
| RPC | Edge configuration, routing policy, certificates or certificate metadata, approved backend map | [MAINNET DECISION] Separate protected configuration backup | [SECURITY REVIEW REQUIRED] Certificates and credentials protected separately | Rebuild edge, restore config, issue/restore certificates through approved process | DNS, backend RPC, TLS authority | [MAINNET DECISION] RPC owner |
| Indexer | Release artifact, environment schema without secrets, migrations, configuration manifest, sync metadata | [MAINNET DECISION] Protected artifact/config storage | [SECURITY REVIEW REQUIRED] No secrets in ordinary backups | Rebuild service, apply migrations, replay from approved block | RPC, PostgreSQL, contract manifest | [MAINNET DECISION] Indexer owner |
| PostgreSQL | Encrypted database backups and restore metadata | [MAINNET DECISION] Independent backup location | [SECURITY REVIEW REQUIRED] Strong encryption and separated credentials | Restore database, verify migrations, replay indexer if necessary | Database engine, storage, indexer replay | [MAINNET DECISION] Database owner |
| Keeper | Atomic state file, release artifact, non-secret configuration schema | [MAINNET DECISION] Protected operational backup | [SECURITY REVIEW REQUIRED] State contains no private keys | Restore state only after chain ID and registry checks; rotate signer separately if needed | RPC, Registry, signer custody, nonce policy | [MAINNET DECISION] Keeper owner |
| PWCScan | Release artifacts, public configuration, deployment metadata | [MAINNET DECISION] Artifact storage | [SECURITY REVIEW REQUIRED] No browser secrets | Rebuild and point to approved API/RPC | Indexer API, edge, TLS | [MAINNET DECISION] Explorer owner |
| Monitoring | Dashboards, alert rules, service discovery, runbooks | [MAINNET DECISION] Protected configuration backup | [SECURITY REVIEW REQUIRED] Notification credentials protected | Restore monitoring stack and validate alerts | Metrics endpoints, notification provider | [MAINNET DECISION] Monitoring owner |
| Governance and keys | Public addresses and ceremony attestations only in ordinary records | [SECURITY REVIEW REQUIRED] Private keys use separate custody procedures, not ordinary backups | Hardware/offline or owner-approved secure custody | Recovery or rotation through approved ceremony and governance process | Signer quorum, timelock, emergency process | [MAINNET DECISION] Governance/custody owner |

### Recovery rules

[IMPLEMENTATION REQUIRED]

- A database can be rebuilt from backups or replayed from chain data.
- An indexer must not require blockchain signing authority to recover.
- Keeper state must be rejected if Chain ID or registry address does not match configuration.
- Validator recovery must not silently replace validator identity.
- PWCScan can be rebuilt from release artifacts and public configuration.
- Monitoring must have a fallback alert path if the primary monitoring stack fails.

[MAINNET DECISION] Approve recovery time and recovery point targets for every production component.

## 14. Security Boundaries

### 14.1 Public request boundary

```text
Public Internet
      │
      ▼
RPC / Explorer Edge
  - TLS
  - rate limits
  - request validation
  - public routes only
      │
      ▼
Application Services
  - PWCScan
  - Indexer API
  - public RPC backends
      │
      ▼
Blockchain RPC
  - read-only for indexer
  - controlled write path for keeper
      │
      ▼
Validators
  - private administration
  - restricted P2P
```

### 14.2 Operator administration boundary

```text
Operators
      │
      ▼
Secure administration path
  - authenticated
  - allowlisted
  - audited
      │
      ├──► Validators
      ├──► Keeper
      ├──► Indexer/PostgreSQL
      ├──► PWCScan
      └──► Monitoring
```

### 14.3 Governance signing boundary

```text
Governance keys
      │
      ▼
Multisig / Timelock
      │
      ▼
Protocol administration
      ├──► ValidatorRegistry
      ├──► RewardVault
      ├──► FeeDistributor
      ├──► Treasury
      └──► StakingManager
```

### 14.4 Trust boundaries

[SECURITY REVIEW REQUIRED]

- Public users are untrusted.
- Public RPC callers are untrusted.
- PWCScan browser clients are untrusted.
- Indexer API consumers are untrusted.
- Indexer database writes are service-trusted but not governance-trusted.
- Keeper transactions are operationally trusted only for permissionless actions.
- Validator operators are infrastructure-trusted but must not automatically receive treasury or governance authority.
- Governance signers are protocol-control trusted within their approved roles.
- Emergency signers are trusted only for the approved emergency action list.
- Backup custodians are recovery-trusted and must not automatically be signing-trusted.

### 14.5 Signing boundaries

[SECURITY REVIEW REQUIRED]

Separate:

- Validator signing keys.
- Deployer key.
- Governance/multisig keys.
- Treasury keys.
- Keeper key.
- Any monetary or token-specific authority.

No key should be reused across these domains without explicit owner approval and security review.

### 14.6 Read-only boundaries

[IMPLEMENTATION REQUIRED]

- PWCScan reads the indexer API.
- The indexer reads blockchain RPC.
- Monitoring reads health and metrics.
- Database consumers read through approved API or read-only roles.
- Public RPC access must not imply node administration.

### 14.7 Failure domains

[MAINNET DECISION]

The owner must approve the acceptable separation between:

- Validator failures.
- RPC edge failures.
- Indexer failures.
- PostgreSQL failures.
- Keeper failures.
- PWCScan failures.
- Monitoring failures.
- Backup storage failures.
- Governance key loss or compromise.

## 15. Mainnet Decision Register

This register contains only decisions required for architecture freeze.

### 1. Validator count

- **Decision:** [MAINNET DECISION] Initial and target mainnet validator count.
- **Why it matters:** Determines consensus resilience, infrastructure cost, governance complexity, and recovery assumptions.
- **Current evidence:** [TESTNET VERIFIED] Four validators are currently live on Chain 77. [ESTABLISHED] Older documentation describes a five-validator testnet target.
- **Options:** Four; more than four; phased validator expansion; another owner-approved model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Select count based on failure tolerance and independent operator capacity, not by copying testnet.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes; validator design and genesis depend on it.

### 2. Validator geographic distribution

- **Decision:** [MAINNET DECISION] Required geographic separation.
- **Why it matters:** Reduces correlated regional and network failure.
- **Current evidence:** [ESTABLISHED] Testnet geography is not a mainnet resilience approval.
- **Options:** Single region; multiple regions; minimum-region policy; another owner-approved model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Require geographic separation sufficient for the approved failure model.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes.

### 3. Provider diversity

- **Decision:** [MAINNET DECISION] Whether validators must span independent providers or failure domains.
- **Why it matters:** A single provider outage could affect consensus.
- **Current evidence:** [ESTABLISHED] Provider concentration is a known operational risk.
- **Options:** Single provider; multiple providers; provider diversity for a subset of validators; another model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Use more than one failure domain where operationally feasible.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes.

### 4. Public RPC topology

- **Decision:** [MAINNET DECISION] Number and placement of public RPC backends and edge routing.
- **Why it matters:** Determines availability, capacity, abuse resistance, and client access.
- **Current evidence:** [TESTNET VERIFIED] External RPC and nginx proxying work as the reference model.
- **Options:** One RPC backend; multiple RPC backends; managed provider plus self-operated fallback; another model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Avoid a single public RPC failure domain.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes.

### 5. Private RPC topology

- **Decision:** [MAINNET DECISION] Private RPC access for indexer, keeper, monitoring, and operators.
- **Why it matters:** Prevents public traffic from starving operational services and protects privileged methods.
- **Current evidence:** [ESTABLISHED] Indexer and keeper have distinct access needs.
- **Options:** Dedicated private endpoint; allowlisted shared endpoint; separate endpoint per service; another model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Separate or strongly isolate operational RPC traffic from public traffic.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes.

### 6. Indexer hosting model

- **Decision:** [MAINNET DECISION] External hosting model for the indexer.
- **Why it matters:** Determines availability, maintenance, and replay/rebuild responsibility.
- **Current evidence:** [ESTABLISHED] The repository provides a co-located indexer/API architecture.
- **Options:** Dedicated external service; shared explorer host; managed compute; redundant instances; another model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Keep indexer runtime external and isolate it from validators.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Partial; required before production service design.

### 7. PostgreSQL hosting model

- **Decision:** [MAINNET DECISION] External PostgreSQL hosting model.
- **Why it matters:** Determines backup, failover, security, and operational burden.
- **Current evidence:** [ESTABLISHED] The indexer requires PostgreSQL; production database recovery has not been approved.
- **Options:** Managed PostgreSQL; self-operated PostgreSQL; primary/standby; another owner-approved model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Choose the model with tested restore and replay capability.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Partial.

### 8. Keeper redundancy

- **Decision:** [MAINNET DECISION] Single, active/passive, or multi-active keeper operation.
- **Why it matters:** Determines synchronization availability and nonce/duplicate execution behavior.
- **Current evidence:** [TESTNET VERIFIED] Keeper operations are retryable and intended to be idempotent.
- **Options:** Single keeper with rebuild; active/passive; multi-active; another model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Use a recovery-tested design rather than adding active instances without coordination.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes for operational design.

### 9. Keeper custody model

- **Decision:** [MAINNET DECISION] Custody of the keeper transaction signer.
- **Why it matters:** The keeper needs gas and transaction authority but must not gain governance power.
- **Current evidence:** [TESTNET VERIFIED] Keeper actions are permissionless; the keeper is not intended to hold admin authority.
- **Options:** Dedicated hot key; hardware-backed signer; policy-controlled signer; another model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Keep the signer dedicated, separately custodied, and limited to operational gas.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes for production keeper design.

### 10. PWCScan hosting model

- **Decision:** [MAINNET DECISION] External hosting and failover for PWCScan.
- **Why it matters:** Determines public availability and separation from internal services.
- **Current evidence:** [ESTABLISHED] PWCScan is a web application consuming indexer/API data.
- **Options:** Dedicated host; edge/static hosting plus API service; redundant hosts; another model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Keep PWCScan separate from validator and database administration.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Partial.

### 11. Monitoring ownership

- **Decision:** [MAINNET DECISION] Who owns monitoring, alerts, and first response.
- **Why it matters:** An unowned alert is not an operational control.
- **Current evidence:** [ESTABLISHED] Monitoring domains are defined, but owner assignment is not final.
- **Options:** Project operations; infrastructure provider; managed monitoring; shared responsibility; another model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Assign one accountable owner per domain and one escalation path.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes for launch readiness.

### 12. Backup ownership

- **Decision:** [MAINNET DECISION] Who owns backup creation, encryption, retention, and verification.
- **Why it matters:** Backups without an accountable custodian may be unusable.
- **Current evidence:** [ESTABLISHED] Procedures exist conceptually; mainnet ownership and live drills are pending.
- **Options:** Project operations; infrastructure provider; managed backup service; shared responsibility.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Separate backup storage from the primary failure domain and test restoration.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes for recovery design.

### 13. Recovery ownership

- **Decision:** [MAINNET DECISION] Who can rebuild or replace validators and production services.
- **Why it matters:** Recovery requires authority, access, and a documented sequence.
- **Current evidence:** [ESTABLISHED] Recovery procedures are designed but ownership is unresolved.
- **Options:** Project operations; provider operations; named external operator; shared model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Assign one accountable recovery lead with tested delegation.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes.

### 14. Governance/control boundary

- **Decision:** [MAINNET DECISION] Final separation between emergency, protocol, treasury, validator, and staking controls.
- **Why it matters:** Prevents privilege concentration and ambiguous incident authority.
- **Current evidence:** [TESTNET VERIFIED] Testnet governance reference separates emergency pause powers from routine timelocked governance. [TESTNET VERIFIED] Reference values include 3-of-5 emergency control and 48-hour timelock.
- **Options:** Adopt testnet reference; modify role separation; add or remove control domains; another model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Preserve least privilege and keep emergency controls narrower than routine governance.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes.

### 15. StakingManager launch requirement

- **Decision:** [MAINNET DECISION] Whether StakingManager functionality is required for initial mainnet launch.
- **Why it matters:** It affects rewards, validator registration, claims, indexer events, governance, and security review.
- **Current evidence:** [TESTNET VERIFIED] Dynamic claims and validator registration were deferred pending StakingManager. [IMPLEMENTATION REQUIRED] The final StakingManager is not implemented in this phase.
- **Options:** Required at launch; explicitly excluded from an initial PoA-only launch; phased launch with approved disabled functionality; another model.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Treat it as a blocker for any staking-dependent launch scope.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes for staking-dependent implementation; conditional for a deliberately narrowed launch.

### 16. Launch authority

- **Decision:** [MAINNET DECISION] Who has final go/no-go authority.
- **Why it matters:** Launch is irreversible at the chain and contract level.
- **Current evidence:** [ESTABLISHED] Ceremony procedures require human confirmation, but final owner authority is not recorded here.
- **Options:** Project owner; governance multisig; launch committee; another owner-approved authority.
- **Recommendation:** [TECHNICAL RECOMMENDATION] Require explicit written approval after security, recovery, dry-run, and final readiness sign-off.
- **Final owner decision:** `TBD — owner approval required`.
- **Blocks next phase?:** Yes.

## 16. Architecture Freeze Exit Criteria

MAINNET-1 is complete only when all of the following are approved or explicitly recorded.

### Responsibility and boundaries

- [MAINNET DECISION] Replit versus external responsibility boundaries approved.
- [MAINNET DECISION] Operational owners assigned for validators, RPC, indexer/PostgreSQL, keeper, PWCScan, monitoring, backups, and recovery.
- [SECURITY REVIEW REQUIRED] Public, private, read-only, write, and signing boundaries documented.

### Validator architecture

- [MAINNET DECISION] Validator count approved or intentionally deferred with a documented dependency.
- [MAINNET DECISION] Geographic distribution approved.
- [MAINNET DECISION] Provider diversity approved.
- [IMPLEMENTATION REQUIRED] Hardware, storage, networking, recovery, replacement, and upgrade design documented.
- [SECURITY REVIEW REQUIRED] Validator key custody boundary documented without generating keys.

### RPC architecture

- [MAINNET DECISION] Public RPC topology approved.
- [MAINNET DECISION] Private RPC topology approved.
- [MAINNET DECISION] WebSocket and archive requirements decided.
- [IMPLEMENTATION REQUIRED] Edge, TLS, rate-limit, health-check, and failover requirements documented.
- [SECURITY REVIEW REQUIRED] Validator administration is excluded from public access.

### Indexer and database architecture

- [MAINNET DECISION] Indexer hosting model approved.
- [MAINNET DECISION] PostgreSQL hosting model approved.
- [IMPLEMENTATION REQUIRED] Read-only RPC, database write, replay, backup, restore, and failover boundaries documented.
- [MAINNET DECISION] Database backup and recovery ownership assigned.

### Keeper architecture

- [MAINNET DECISION] Keeper redundancy approved.
- [MAINNET DECISION] Keeper custody model approved.
- [IMPLEMENTATION REQUIRED] State file, transaction authority, duplicate execution, failure recovery, and monitoring design documented.
- [SECURITY REVIEW REQUIRED] Keeper authority is separated from governance and treasury authority.

### Explorer architecture

- [IMPLEMENTATION REQUIRED] PWCScan network identity, API, RPC, synchronization, outage, TLS, and public/private boundaries documented.
- [SECURITY REVIEW REQUIRED] No silent local `73571` fallback.
- [SECURITY REVIEW REQUIRED] No testnet address fallback.

### Governance architecture

- [MAINNET DECISION] Emergency, routine, validator, treasury, reward, fee, and staking control boundaries approved.
- [MAINNET DECISION] Signer counts, thresholds, delays, and role ownership explicitly approved or recorded as unresolved.
- [SECURITY REVIEW REQUIRED] Key separation and recovery boundaries documented without generating keys.

### StakingManager

- [MAINNET DECISION] Initial launch requirement explicitly decided.
- [IMPLEMENTATION REQUIRED] Dependent components and interfaces listed.
- [SECURITY REVIEW REQUIRED] Pause, upgrade, claim, and validator-control implications identified.

### Monitoring and recovery

- [MAINNET DECISION] Monitoring ownership and escalation assigned.
- [MAINNET DECISION] Backup ownership assigned.
- [MAINNET DECISION] Recovery ownership assigned.
- [IMPLEMENTATION REQUIRED] Recovery domains and restore dependencies documented.
- [SECURITY REVIEW REQUIRED] Backup custody is separated from signing authority.

### Explicit non-actions

- [ESTABLISHED] No production infrastructure provisioned.
- [ESTABLISHED] No Chain 77 infrastructure modified.
- [ESTABLISHED] No mainnet infrastructure modified.
- [ESTABLISHED] No mainnet keys generated.
- [ESTABLISHED] No secrets accessed.
- [ESTABLISHED] No wallets created.
- [ESTABLISHED] No genesis created.
- [ESTABLISHED] No contracts deployed.
- [ESTABLISHED] No blockchain transactions made.

## 17. Exact Decisions That Require Owner Approval

The owner must provide decisions for:

1. [MAINNET DECISION] Initial and target validator count.
2. [MAINNET DECISION] Required validator geographic distribution.
3. [MAINNET DECISION] Required provider diversity.
4. [MAINNET DECISION] Public RPC topology.
5. [MAINNET DECISION] Private RPC topology.
6. [MAINNET DECISION] WebSocket requirement.
7. [MAINNET DECISION] Archive-state requirement.
8. [MAINNET DECISION] Indexer hosting model.
9. [MAINNET DECISION] PostgreSQL hosting model.
10. [MAINNET DECISION] Keeper redundancy.
11. [MAINNET DECISION] Keeper custody model.
12. [MAINNET DECISION] PWCScan hosting model.
13. [MAINNET DECISION] Monitoring ownership and escalation.
14. [MAINNET DECISION] Backup ownership and retention.
15. [MAINNET DECISION] Recovery ownership and targets.
16. [MAINNET DECISION] Governance/control boundary.
17. [MAINNET DECISION] Whether the testnet governance reference is adopted or changed.
18. [MAINNET DECISION] Whether StakingManager is required for initial launch.
19. [MAINNET DECISION] Whether an intentionally narrowed PoA-only launch is acceptable if staking is deferred.
20. [MAINNET DECISION] Final launch authority.

No final owner decision is filled in this package.

MIGRATION CLOSED.

MAINNET-1 ARCHITECTURE PACKAGE PREPARED.

NO MAINNET INFRASTRUCTURE OR BLOCKCHAIN STATE WAS MODIFIED.