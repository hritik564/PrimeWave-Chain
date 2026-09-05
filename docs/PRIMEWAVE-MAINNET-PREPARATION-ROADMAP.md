# PRIMEWAVE CHAIN — MAINNET PREPARATION ROADMAP

## 1. Migration Closure

[ESTABLISHED] The Replit migration is closed.

The supplied closure record establishes:

- Phase 5 completed.
- Phase 6A completed.
- Phase 6B GREEN.
- Phase 6C GREEN, documentation/metadata only.
- Migration checkpoint: `90e8f194a01496862e780916e134b672f588d438`
- Recorded repository HEAD at closure: `90a3f267349acd0d7cdd7c3ac0d9f07652b36d72`
- The migration checkpoint is an ancestor of the recorded HEAD.
- Existing Chain 77 infrastructure remains external.
- No Chain 77 blockchain state, Netcup infrastructure, DNS, firewall, nginx, PostgreSQL, validator, keeper, indexer, or PWCScan runtime was modified by the migration.

This document does not reopen the migration audit and does not propose another migration.

### Current responsibility boundary

| Responsibility | Replit | External infrastructure |
|---|---:|---:|
| Source code and documentation | Yes | No |
| Builds and typechecking | Yes | No |
| Local chain and test simulations | Yes | No |
| Mainnet preparation documents | Yes | No |
| Chain 77 validators | No | Yes |
| Chain 77 RPC | No | Yes |
| Chain 77 indexer/PostgreSQL | No | Yes |
| Chain 77 keeper | No | Yes |
| Chain 77 PWCScan serving | No | Yes |
| Mainnet production runtime | No | Future external infrastructure |

## 2. What Is Already Established

### 2.1 Established project boundaries

[ESTABLISHED]

- Replit is the development, source, testing, documentation, and deployment-preparation environment.
- Production blockchain runtime should remain outside Replit unless explicitly approved later.
- Chain 77 is the existing testnet and must remain separate from mainnet.
- Mainnet must have a new network identity, genesis, validator configuration, deployment addresses, treasury controls, and operational procedures.
- The local development network uses Chain ID `73571` and must not be treated as testnet or mainnet.

### 2.2 Existing Chain 77 testnet baseline

[TESTNET VERIFIED]

- Network: PrimeWave sovereign Avalanche L1 on Fuji.
- Chain ID: `77`.
- Blockchain ID: `22iFu...LQVjLni`.
- Subnet ID: `ovXT...trLbv`.
- Conversion ID: `3wDX...ECW4`.
- Native token symbol: `PW`.
- Existing validator architecture: four validators.
- Public RPC is exposed through external validator infrastructure.
- Nginx is used as the external RPC proxy.
- The testnet uses AvalancheGo and a compatible patched subnet-EVM binary.
- The testnet has produced blocks and was independently checked through multiple RPC endpoints.
- The testnet has seven deployed protocol contracts.
- Fee distribution was functionally verified.
- The testnet has an external indexer, PostgreSQL database, keeper, and PWCScan runtime.

These values are testnet facts. They are not automatically mainnet decisions.

### 2.3 Existing protocol components

[ESTABLISHED] The current protocol architecture includes:

- `EmergencyMultisig`
- `PrimeWaveTimelock`
- `ValidatorFeeVault`
- `DevTreasury`
- `FeeDistributor`
- `ValidatorRegistry`
- `RewardVault`
- Native Avalanche PoA/validator-manager integration
- Planned or incomplete `StakingManager`

[TESTNET VERIFIED]

- The testnet `FeeDistributor` routes fees through the validator, treasury, and burn destinations.
- The testnet RewardVault has been funded and its accounting invariants were verified.
- Emergency pause controls exist across key protocol components.
- Timelock and multisig controls exist in the testnet design.
- Dynamic reward claiming and validator registration remain incomplete until the StakingManager design is resolved.

### 2.4 Still a mainnet decision

[MAINNET DECISION]

The following are not approved for mainnet merely because they exist on testnet:

- Chain ID.
- Token supply.
- Token allocation.
- Reward rate.
- Validator count.
- Fee split.
- Treasury allocation.
- Multisig signer policy.
- Timelock delay.
- StakingManager behavior.
- RPC topology.
- Infrastructure provider selection.
- Mainnet launch date.

## 3. Mainnet Architecture

### 3.1 Target boundary

[ESTABLISHED] Replit should remain responsible for:

- Source code.
- Architecture and runbooks.
- Contract build and test workflows.
- Genesis preparation tooling.
- Deployment scripts.
- Static validation.
- Testnet read-only checks.
- Mainnet dry-run preparation.
- Documentation and release artifacts.

[IMPLEMENTATION REQUIRED] External infrastructure should be responsible for:

- Mainnet validators.
- Public and private RPC endpoints.
- Indexer runtime.
- PostgreSQL.
- Keeper runtime.
- Explorer serving.
- Nginx and TLS.
- Monitoring and alerting.
- Operational backups.
- Production key custody.

### 3.2 Validator layer

[MAINNET DECISION]

The mainnet validator layer requires decisions on:

- Validator count.
- Minimum validator diversity.
- Geographic distribution.
- Provider diversity.
- Validator admission and removal policy.
- Hardware baseline.
- Storage and backup requirements.
- Validator key custody.
- Validator replacement and recovery.

[IMPLEMENTATION REQUIRED] Each validator should run:

- The approved AvalancheGo version.
- The exact mainnet-compatible subnet-EVM binary.
- The mainnet chain configuration.
- The approved validator and node keys.
- Restricted administrative APIs.
- P2P networking on the required ports.
- Local health and telemetry exporters.

### 3.3 RPC layer

[IMPLEMENTATION REQUIRED]

The production RPC layer should be separated from validator administration:

- Public RPC endpoints behind nginx or an equivalent edge proxy.
- TLS termination.
- Rate limiting.
- Request-size and timeout controls.
- Health checks and failover.
- Separate public, indexing, keeper, and administrative access paths.
- No unrestricted validator admin API exposure.

[MAINNET DECISION] The project must choose:

- Number of public RPC endpoints.
- Whether RPC is operated by the project, a provider, or both.
- Geographic distribution.
- WebSocket support requirements.
- Archive-state requirements.
- Public rate limits and usage policy.

### 3.4 Indexer and PostgreSQL

[IMPLEMENTATION REQUIRED]

The mainnet indexer should run externally and connect to:

- The approved mainnet RPC endpoint set.
- A dedicated PostgreSQL database.
- The final mainnet contract address manifest.
- Mainnet start block and confirmation policy.
- Monitoring for chain head versus indexed head.

[SECURITY REVIEW REQUIRED]

- PostgreSQL credentials must be stored outside source control.
- Database access must be private or allowlisted.
- Backups must be encrypted and tested through restoration.
- Indexer write access must not imply blockchain signing authority.

### 3.5 Keeper

[IMPLEMENTATION REQUIRED]

The keeper should run externally with:

- Mainnet RPC.
- Final Chain ID.
- Final ValidatorRegistry address.
- Final PoAManager address.
- Final keeper key.
- Persistent state file.
- Restart and duplicate-execution protection.
- Alerting when keeper actions fail or state becomes stale.

[MAINNET DECISION] The project must decide:

- Whether one keeper or multiple failover keepers are used.
- How keeper actions are authorized.
- Whether the keeper key is hot, hardware-backed, or policy-controlled.
- Which actions are permissionless versus keeper-only.

### 3.6 PWCScan

[IMPLEMENTATION REQUIRED]

PWCScan should be externally served and configured with:

- Mainnet network label.
- Mainnet Chain ID.
- Mainnet indexer API URL.
- Mainnet contract addresses.
- Mainnet explorer metadata.
- No local Chain ID fallback.
- No testnet address fallback.

The structural explorer architecture can remain similar to testnet, but all network-specific values must be replaced through an approved mainnet configuration process.

### 3.7 Nginx and TLS

[IMPLEMENTATION REQUIRED]

External edge infrastructure should provide:

- TLS certificates.
- HTTPS redirect.
- RPC reverse proxying.
- Explorer reverse proxying.
- Indexer API routing.
- Security headers.
- Request limits.
- Access logging.
- Health-check routing.

[SECURITY REVIEW REQUIRED] The public-facing nginx configuration must be reviewed before launch.

### 3.8 Monitoring

[IMPLEMENTATION REQUIRED]

Monitoring should cover:

- Validator process health.
- Validator peer count.
- Block production.
- Chain head progression.
- RPC latency and error rates.
- Indexer lag.
- PostgreSQL health and storage.
- Keeper success/failure state.
- Explorer availability.
- Disk, memory, CPU, and network usage.
- Certificate expiration.
- Backup freshness.

[MAINNET DECISION] Alert ownership, escalation, on-call coverage, and incident response time must be defined.

### 3.9 Treasury and governance layer

[MAINNET DECISION]

Treasury and governance require explicit policy for:

- Multisig signer count.
- Signing threshold.
- Signer independence.
- Treasury spending limits.
- Timelock delay.
- Emergency authority.
- Upgrade authority.
- Validator governance.
- Key rotation.
- Emergency pause and resume procedures.

## 4. Mainnet Decisions Required

| Decision | Current Status | Existing Evidence | Decision Required From Project Owner | Blocks Implementation? |
|---|---|---|---|---:|
| Mainnet network name | [MAINNET DECISION] | Testnet uses a separate CLI/network name | Approve the mainnet name | Yes |
| Mainnet Chain ID | [MAINNET DECISION] | Testnet uses Chain ID 77; local uses 73571 | Select and reserve a non-testnet Chain ID | Yes |
| Blockchain ID | [MAINNET DECISION] | Generated by the Avalanche network creation process | Approve the creation process and identity record | Yes |
| Subnet ID | [MAINNET DECISION] | Generated during subnet/network creation | Approve the identity ceremony and recordkeeping | Yes |
| Conversion ID | [MAINNET DECISION] | Generated during L1 conversion | Approve the conversion process and verification | Yes |
| Token symbol and name | [MAINNET DECISION] | Testnet uses PW / PrimeWave | Confirm whether the testnet branding carries to mainnet | Yes |
| Total supply | [MAINNET DECISION] | Testnet total supply was verified at 100,000,000 PW | Approve the mainnet supply | Yes |
| Token allocation | [MAINNET DECISION] | Testnet allocation is not a mainnet approval | Approve treasury, rewards, ecosystem, and other allocations | Yes |
| Validator count | [MAINNET DECISION] | Testnet currently has four validators | Approve initial and target validator count | Yes |
| Validator selection/governance | [MAINNET DECISION] | ValidatorRegistry and PoA integration exist technically | Approve admission, removal, and replacement policy | Yes |
| Block timing | [MAINNET DECISION] | Testnet timing is an implementation reference only | Approve mainnet block timing and liveness targets | Yes |
| Gas configuration | [MAINNET DECISION] | Existing genesis and subnet-EVM configuration provide references | Approve gas limit, pricing, and fee policy | Yes |
| Reward economics | [MAINNET DECISION] | Testnet RewardVault behavior is verified | Approve emission model, rate, duration, and recipients | Yes |
| Fee distribution | [MAINNET DECISION] | Testnet used 70% validator / 20% treasury / 10% burn | Approve or change the mainnet split | Yes |
| Treasury | [MAINNET DECISION] | DevTreasury exists in the protocol design | Approve treasury ownership, custody, and spending policy | Yes |
| Emergency multisig | [MAINNET DECISION] | Testnet EMS and threshold behavior were verified | Approve signer count, threshold, custody, and emergency powers | Yes |
| Timelock | [MAINNET DECISION] | Testnet timelock exists and has a configured delay | Approve delay, admin, proposer, executor, and cancellation policy | Yes |
| Emergency controls | [MAINNET DECISION] | Pause controls exist technically | Approve who can pause, unpause, and under which conditions | Yes |
| StakingManager | [MAINNET DECISION] | StakingManager is not yet part of the completed testnet flow | Approve its scope, interfaces, reward relationship, and launch requirement | Yes |
| Keeper architecture | [MAINNET DECISION] | Keeper design exists but mainnet custody and redundancy are unresolved | Approve signer model, redundancy, and action policy | Yes |
| Indexer and explorer | [MAINNET DECISION] | Testnet indexer and PWCScan architecture exists | Approve mainnet hosting, availability, and API policy | Partial |
| Monitoring | [MAINNET DECISION] | Testnet operational checks exist | Approve monitoring ownership and alert escalation | Yes |
| Backup and recovery | [MAINNET DECISION] | Recovery procedures are not yet mainnet-approved | Approve backup scope, retention, restoration tests, and RTO/RPO | Yes |
| Mainnet launch authority | [MAINNET DECISION] | No launch authority has been defined in the supplied record | Identify who can approve genesis and launch | Yes |

No unresolved value should be filled by copying a testnet value.

## 5. Tokenomics

### 5.1 Testnet verified

[TESTNET VERIFIED]

- Total supply: `100,000,000 PW`.
- RewardVault funding: `15,000,000 PW`.
- FeeDistributor routing:
  - 70% to ValidatorFeeVault.
  - 20% to DevTreasury.
  - 10% to the burn address.
- Fee distribution was functionally exercised.
- The burn destination was verified.
- RewardVault accounting invariants were tested.
- Dynamic reward claiming remained deferred because the StakingManager flow was not complete.

These are testnet facts, not mainnet approvals.

### 5.2 Mainnet parameters requiring approval

[MAINNET DECISION]

Before mainnet implementation, the project must finalize:

- Total supply.
- Initial circulating supply.
- Treasury allocation.
- Validator reward allocation.
- Ecosystem allocation.
- Team or contributor allocation, if any.
- RewardVault funding method.
- Emission rate.
- Emission duration or cap.
- Validator weighting model.
- Fee distribution percentages.
- Burn policy.
- Treasury spending restrictions.
- Whether unused rewards are recoverable or permanently locked.
- Whether the mainnet starts with active validator rewards immediately.

[SECURITY REVIEW REQUIRED]

The approved tokenomics must be checked against:

- Genesis balances.
- Contract funding.
- Total-supply invariants.
- FeeDistributor destinations.
- RewardVault limits.
- Multisig and timelock control.
- Deployment and post-deployment verification scripts.

No arbitrary mainnet economic value is recommended at this stage.

## 6. Validator Architecture

### What can remain conceptually similar

[ESTABLISHED]

The following concepts can remain structurally similar to testnet:

- Sovereign Avalanche L1 architecture.
- Validator nodes running AvalancheGo and the compatible subnet-EVM.
- Separate public RPC access.
- ValidatorRegistry integration.
- Native PoA/validator-manager integration.
- External operational hosting.
- P2P validator communication.
- Monitoring of peer and block-production health.

### What must be reconsidered

[MAINNET DECISION]

Mainnet must reconsider:

- Whether four validators provide sufficient resilience.
- Whether all validators may use the same infrastructure provider.
- Minimum geographic separation.
- Validator admission and removal governance.
- Validator key custody.
- Replacement time.
- Disaster recovery.
- Upgrade coordination.
- Expected transaction load.
- Public RPC and validator network separation.

### Validator count and distribution

[MAINNET DECISION]

The project must approve:

- Initial validator count.
- Long-term target validator count.
- Minimum number required for safe operation.
- Geographic regions.
- Provider diversity.
- Network failure assumptions.
- Whether validators may be operated by related entities.
- How validator weight is determined.

No mainnet count should be inferred automatically from the four-validator testnet.

### Hardware and storage

[IMPLEMENTATION REQUIRED]

A mainnet hardware baseline should define:

- CPU capacity.
- Memory.
- Fast storage capacity and endurance.
- Operating system and kernel baseline.
- Swap policy.
- Database or log storage separation.
- Retention for node logs.
- Backup and restore requirements.

[MAINNET DECISION] The final baseline must be based on expected mainnet traffic and operational service-level targets.

### Networking

[IMPLEMENTATION REQUIRED]

- P2P ports must be reachable only as required.
- Public RPC must not expose validator administration.
- Firewall rules must be reviewed before node deployment.
- Node-to-node connectivity must be tested from every planned region.
- DNS and TLS records must be prepared only after identities and ownership are approved.

### Custody, monitoring, and recovery

[SECURITY REVIEW REQUIRED]

- Validator keys must be generated and stored through an approved ceremony.
- Key backups must be encrypted and access-controlled.
- Validator replacement must have a documented procedure.
- Monitoring must detect missed blocks, peer loss, disk exhaustion, and process failure.
- Recovery must be tested without exposing private key material.

## 7. Genesis Design

### Parameters known from current architecture

[ESTABLISHED]

- The target network is expected to be a separate sovereign Avalanche L1.
- The network will use the compatible PrimeWave subnet-EVM implementation.
- The protocol includes native validator-manager integration.
- The protocol requires contract allocations and role configuration.
- Genesis must be treated as immutable after the ceremony.

### Parameters requiring mainnet decisions

[MAINNET DECISION]

- Mainnet Chain ID.
- Network name.
- Token name and symbol.
- Total supply.
- Genesis timestamp.
- Block timing.
- Gas limit and fee configuration.
- Initial validator set.
- Validator weights.
- Treasury balances.
- RewardVault funding.
- Initial allocations.
- FeeDistributor reward address.
- Native validator-manager settings.
- Any predeploy or reserved-address configuration.

### Parameters requiring implementation

[IMPLEMENTATION REQUIRED]

- Mainnet-specific genesis template.
- Mainnet sidecar configuration.
- Mainnet validator bootstrap configuration.
- Deterministic genesis allocation manifest.
- Chain identity extraction and validation.
- Genesis hash recording.
- Reproducible build and archive process.
- Post-genesis RPC and block-production verification.
- Mainnet-specific deployment scripts.
- Mainnet-specific configuration templates.

### Parameters requiring security review

[SECURITY REVIEW REQUIRED]

- Genesis allocation correctness.
- Total-supply invariants.
- Role and ownership assignment.
- Validator identities.
- Native validator-manager configuration.
- Reward and treasury addresses.
- FeeDistributor routing.
- Emergency authority.
- Genesis reproducibility and hash ceremony.
- Independent review of the final artifact.

No final mainnet genesis file should be generated before MAINNET-5.

## 8. Protocol Deployment Plan

The exact deployment order must be finalized against constructor dependencies and the approved governance model.

### 1. EmergencyMultisig

[IMPLEMENTATION REQUIRED]

Deploy or establish the emergency authority first so pause controllers and emergency actions have an approved destination.

Dependencies:

- Approved signer set.
- Approved threshold.
- Key custody and ceremony.
- Emergency policy.

Control considerations:

- Must not remain controlled by an individual deployer after launch.
- Must have documented pause and recovery powers.

### 2. PrimeWaveTimelock

[IMPLEMENTATION REQUIRED]

Establish the timelock after the emergency authority.

Dependencies:

- Approved delay.
- Proposer and executor policy.
- Multisig relationship.
- Deployment authority.

Control considerations:

- Long-term administrative ownership should move to the approved timelock/multisig structure.
- Emergency powers must remain distinct from routine governance.

### 3. ValidatorRegistry

[IMPLEMENTATION REQUIRED]

Deploy ValidatorRegistry with the final mainnet native validator-manager address.

Dependencies:

- Mainnet validator-manager or PoA integration.
- Final validator governance model.
- Protocol admin address.
- Final chain identity.

Control considerations:

- The validator-manager relationship is constructor-sensitive and must be correct at deployment.
- The registry must not use a testnet placeholder or temporary manager.

### 4. ValidatorFeeVault

[IMPLEMENTATION REQUIRED]

Deploy the ValidatorFeeVault with the final ValidatorRegistry relationship.

Dependencies:

- ValidatorRegistry address.
- Approved fee and reward policy.
- Emergency pause controller.

Control considerations:

- The protocol administrator should be the approved registry/governance authority, not an unprotected deployer.

### 5. DevTreasury

[IMPLEMENTATION REQUIRED]

Deploy the treasury contract or establish the approved treasury destination.

Dependencies:

- Treasury policy.
- Multisig and timelock.
- FeeDistributor constructor dependencies.

Control considerations:

- Treasury ownership must not remain with the deployment wallet.
- Spending and upgrade authority must be separately documented.

### 6. FeeDistributor

[IMPLEMENTATION REQUIRED]

Deploy FeeDistributor with final ValidatorFeeVault, treasury, and burn destinations.

Dependencies:

- ValidatorFeeVault.
- DevTreasury.
- Approved fee split.
- Approved burn policy.
- Mainnet genesis reward-routing decision.

Control considerations:

- Fee percentages must be independently verified.
- Genesis reward-address handling must be reconciled with deployment timing.
- Deterministic address planning may be required because related contracts reference one another.

### 7. RewardVault

[IMPLEMENTATION REQUIRED]

Deploy and fund RewardVault according to approved mainnet economics.

Dependencies:

- Final emission policy.
- Approved funding allocation.
- Timelock administration.
- Emergency pause controller.
- StakingManager interface decision.

Control considerations:

- The funding amount must match approved tokenomics.
- `totalEmitted` and funding invariants must be independently checked.
- No dynamic claim path should be considered complete without the final StakingManager design.

### 8. PoAManager integration

[ESTABLISHED / IMPLEMENTATION REQUIRED]

Use the final native validator-manager integration required by the mainnet L1.

Dependencies:

- Final mainnet validator architecture.
- Final genesis and chain identity.
- ValidatorRegistry constructor configuration.

Control considerations:

- The manager address must be verified as the intended native/precompile or protocol address.
- The mainnet deployment must not reuse a testnet-specific placeholder without explicit approval.

### 9. StakingManager

[MAINNET DECISION / IMPLEMENTATION REQUIRED]

Resolve the StakingManager before finalizing staking-dependent mainnet functionality.

Required decisions:

- Staking interface.
- Validator identity relationship.
- Reward accrual and claim model.
- Deposit and withdrawal behavior.
- Validator registration relationship.
- Slashing or penalty model, if applicable.
- Emergency and upgrade authority.
- Interaction with RewardVault and ValidatorRegistry.

Control considerations:

- Do not launch staking-dependent mainnet behavior with an unresolved StakingManager.
- Complete unit, integration, failure, and recovery testing before deployment.

### Post-deployment verification

[IMPLEMENTATION REQUIRED]

Every mainnet deployment must verify:

- Code exists at each expected address.
- Constructor relationships are correct.
- Ownership and admin roles are correct.
- Timelock and multisig roles are correct.
- Pause controllers are correct.
- Fee split is correct.
- RewardVault funding is correct.
- ValidatorRegistry points to the correct manager.
- No testnet address or development key remains in production configuration.

## 9. Governance & Key Management

### Deployer

[SECURITY REVIEW REQUIRED]

The deployer should be treated as a temporary ceremony role.

Requirements:

- Dedicated mainnet deployment wallet.
- No reuse of local or testnet keys.
- Transaction signing through an approved secure process.
- Deployment transaction archive.
- Ownership transfer after deployment.
- No long-term treasury authority.

### Multisig

[MAINNET DECISION]

The owner must approve:

- Signer count.
- Signing threshold.
- Signer independence.
- Geographic and device separation.
- Emergency versus routine signing policy.
- Signer replacement.
- Key backup and recovery.

[SECURITY REVIEW REQUIRED] No single signer should be able to unilaterally control treasury or protocol administration unless explicitly approved.

### Timelock

[MAINNET DECISION]

The owner must approve:

- Minimum delay.
- Proposer authority.
- Executor authority.
- Cancellation authority.
- Emergency bypass policy.
- Upgrade process.
- Public announcement period.

### Treasury

[SECURITY REVIEW REQUIRED]

- Treasury funds should be governed by approved multisig and timelock policy.
- Spending limits and approval classes must be documented.
- Treasury and operational wallets should be separated.
- Treasury recovery must not depend on a single operator.

### Validator keys

[SECURITY REVIEW REQUIRED]

- Validator keys must be generated in a controlled ceremony.
- Keys must not enter source control.
- Backups must be encrypted.
- Access must be limited to designated operators.
- Replacement and revocation procedures must be documented.
- Validator key compromise must have an incident response path.

### Keeper key

[MAINNET DECISION / SECURITY REVIEW REQUIRED]

The project must decide:

- Whether the keeper uses a dedicated hot key.
- Whether keeper actions require multisig or policy approval.
- Whether multiple keepers can run safely.
- How duplicate execution is prevented.
- How the keeper key is rotated.
- How keeper state is backed up and restored.

### Emergency authority

[MAINNET DECISION]

The project must define:

- Who can pause each component.
- When emergency pause is justified.
- Who can unpause.
- Whether unpause requires multisig or timelock.
- How emergency actions are announced and audited.

No keys should be generated during this planning phase.

## 10. Indexer / Keeper / PWCScan

### Indexer

[ESTABLISHED] The testnet indexer architecture includes:

- RPC configuration.
- Chain ID verification.
- PostgreSQL migrations.
- Contract address configuration.
- Block and transaction synchronization.
- REST API.
- Indexer lag and RPC checks.

[IMPLEMENTATION REQUIRED] Mainnet changes will include:

- Mainnet RPC URL.
- Mainnet Chain ID.
- Mainnet contract addresses.
- Mainnet start block.
- Confirmation policy.
- Database endpoint.
- Database credentials.
- Backup and retention.
- Production logging and monitoring.

[MAINNET DECISION]

- Whether indexing starts at genesis or a later approved block.
- Confirmation depth.
- Archive requirements.
- Public API availability.
- Data retention policy.
- Indexer failover design.

### Keeper

[ESTABLISHED] The keeper architecture is externally runnable and stateful.

[IMPLEMENTATION REQUIRED]

- Replace testnet RPC and Chain ID.
- Replace ValidatorRegistry and PoAManager addresses.
- Provide a mainnet keeper key through secure external secret custody.
- Create a mainnet state file.
- Configure monitoring and restart behavior.
- Verify idempotence and failure recovery.

[MAINNET DECISION]

- Keeper redundancy.
- Action authorization.
- Alert ownership.
- Recovery operator.
- Operational transaction limits.

### PWCScan

[IMPLEMENTATION REQUIRED]

Mainnet PWCScan configuration must replace:

- Network label.
- Chain ID.
- Indexer API URL.
- Contract address manifest.
- RPC links.
- Explorer metadata.
- Any testnet branding or testnet-specific navigation.

The following structural behavior should remain:

- Relative API routing where appropriate.
- Explicit network configuration.
- No unsafe local development fallback.
- Visible network identity.
- Clear API offline and synchronization states.

[SECURITY REVIEW REQUIRED] Production PWCScan must not expose internal management endpoints or development credentials.

## 11. Security & Recovery

### Key custody

[SECURITY REVIEW REQUIRED]

- No private keys in source control.
- No keys in tracked environment templates.
- Separate validator, deployer, treasury, multisig, timelock, and keeper custody.
- Encrypted backups.
- Documented access and recovery procedures.
- Key rotation plan.

### Multisig and timelock

[SECURITY REVIEW REQUIRED]

- Verify signer threshold.
- Verify signer independence.
- Verify timelock delay.
- Verify proposer and executor roles.
- Verify emergency pause authority.
- Verify ownership transfer from deployer.

### Contract ownership

[IMPLEMENTATION REQUIRED]

After deployment, verify:

- Every admin role.
- Every pause controller.
- Every treasury destination.
- Every timelock relationship.
- ValidatorRegistry manager.
- RewardVault administrator.
- FeeDistributor destinations.

### Validator compromise

[SECURITY REVIEW REQUIRED]

Prepare procedures for:

- Isolating a compromised validator.
- Removing or replacing its validator identity.
- Preserving chain safety.
- Rotating credentials.
- Rejoining with a clean node.
- Auditing affected blocks and operations.

### Keeper compromise

[SECURITY REVIEW REQUIRED]

Prepare procedures for:

- Revoking or rotating the keeper key.
- Disabling unsafe actions.
- Preserving idempotence.
- Reviewing keeper state.
- Restoring from a known-good backup.

### RPC compromise

[SECURITY REVIEW REQUIRED]

- Separate public RPC from validator administration.
- Rate-limit public access.
- Detect abnormal request patterns.
- Maintain alternate RPC endpoints.
- Protect private keeper and indexer routes.

### Database failure

[IMPLEMENTATION REQUIRED]

- Encrypted backups.
- Restore testing.
- Migration version tracking.
- Indexer replay procedure.
- Chain-head versus indexed-head reconciliation.
- Defined recovery time and recovery point objectives.

### Server failure

[IMPLEMENTATION REQUIRED]

- Rebuild procedure from clean images.
- Validator rejoin procedure.
- RPC failover.
- Indexer failover.
- Keeper failover.
- Monitoring reassignment.

### Emergency shutdown and recovery

[MAINNET DECISION]

Define:

- Pause authority.
- Validator shutdown authority.
- Chain halt criteria.
- Communication procedure.
- Recovery approval.
- Resumption criteria.
- Post-incident review.

### Upgrades and incident response

[SECURITY REVIEW REQUIRED]

- Version pinning.
- Upgrade rehearsal.
- Binary provenance.
- Rollout sequencing.
- Rollback limitations.
- Emergency patch authority.
- Incident communication.
- Independent review.

## 12. Testnet Exit Criteria

Before mainnet implementation is approved, Chain 77 should demonstrate:

### Protocol behavior

[TESTNET VERIFIED / IMPLEMENTATION REQUIRED]

- FeeDistributor distribution and burn routing.
- ValidatorFeeVault accounting.
- RewardVault funding and emission invariants.
- Emergency pause and recovery.
- Timelock-controlled operations.
- ValidatorRegistry behavior.
- StakingManager behavior once implemented.
- Validator registration, removal, and replacement.
- Reward claim behavior with real registered validators.

### Validator and network behavior

[IMPLEMENTATION REQUIRED]

- Sustained block production over an agreed observation period.
- Four-validator operation under normal conditions.
- Validator restart and rejoin.
- Peer loss and recovery.
- RPC failover.
- Chain liveness after infrastructure interruption.
- Upgrade and rollback rehearsal.

### Keeper behavior

[IMPLEMENTATION REQUIRED]

- Correct keeper actions.
- Duplicate-execution safety.
- Keeper restart.
- State restoration.
- Key rotation rehearsal.
- Failure alerting.

### Indexer and explorer

[IMPLEMENTATION REQUIRED]

- Full synchronization from the approved start point.
- Indexer restart and replay.
- Database restore.
- Chain reset or reorganization handling.
- API pagination and detail endpoints.
- PWCScan synchronization state.
- Explorer behavior after API outage.

### Governance and controls

[SECURITY REVIEW REQUIRED]

- Ownership and admin role review.
- Multisig threshold confirmation.
- Timelock delay confirmation.
- Emergency pause exercise.
- Recovery authority review.
- Deployment and configuration artifact review.

### Operational stability

[MAINNET DECISION]

The project owner must define the required duration and pass criteria for long-running testnet stability. No specific duration is assumed here.

## 13. Mainnet Dry Run

The future dry run should use an isolated environment and should not touch Chain 77 or production infrastructure.

### Sequence

1. **Clean infrastructure**
   - Provision only approved isolated dry-run infrastructure.
   - Verify OS, binary, firewall, storage, and monitoring baselines.

2. **Identity and genesis ceremony**
   - Use separately approved mainnet identities.
   - Generate and review the mainnet genesis artifact.
   - Record hashes and approvals.
   - Do not reuse Chain 77 state.

3. **Validator formation**
   - Bring up the approved validator set.
   - Verify peer connectivity and block production.
   - Validate the validator-manager relationship.

4. **Protocol deployment**
   - Deploy contracts in the approved order.
   - Verify constructor relationships and roles.
   - Transfer administration to the approved controls.

5. **Treasury setup**
   - Verify treasury balances and ownership.
   - Verify multisig and timelock paths.
   - Confirm emergency authority.

6. **Validator registration**
   - Register approved validators.
   - Verify ValidatorRegistry state.
   - Verify any StakingManager relationships.

7. **Keeper activation**
   - Configure keeper RPC, Chain ID, addresses, and state.
   - Verify successful and idempotent operations.
   - Test keeper failure and recovery.

8. **Indexer synchronization**
   - Apply migrations.
   - Index the approved start block.
   - Verify chain head and indexed head.
   - Test restart and replay.

9. **PWCScan verification**
   - Point the explorer to the dry-run indexer.
   - Verify network identity, blocks, transactions, validators, and protocol pages.
   - Verify API outage behavior.

10. **Monitoring**
    - Test alerts for node failure, indexer lag, RPC errors, keeper failures, storage, and certificates.

11. **Backup and recovery**
    - Restore PostgreSQL.
    - Restore keeper state.
    - Rebuild an indexer.
    - Rejoin or replace a validator.

12. **Emergency procedures**
    - Exercise approved pause, governance, and recovery paths.
    - Record results.
    - Require independent sign-off before proceeding.

The dry run must be completed before genesis ceremony and launch readiness.

## 14. Mainnet Roadmap

### MAINNET-1 — Architecture Freeze

**Objective**

[MAINNET DECISION] Freeze the target mainnet architecture and responsibility boundaries.

**Decisions required**

- External versus Replit responsibilities.
- Validator and RPC topology.
- Indexer, PostgreSQL, keeper, and explorer topology.
- Governance and control-layer boundaries.
- Monitoring and recovery ownership.
- Required interfaces between components.

**Implementation required**

- Architecture document.
- Component boundary diagram.
- Interface and dependency map.
- Responsibility matrix.
- Draft operational ownership model.

**Dependencies**

- Existing repository architecture.
- Chain 77 operational lessons.
- Owner decisions on production boundaries.

**Exit criteria**

- Architecture approved.
- No unresolved boundary that would change the genesis or contract plan.
- Mainnet responsibility matrix signed off.

### MAINNET-2 — Economic / Tokenomics Freeze

**Objective**

[MAINNET DECISION] Approve mainnet economics.

**Decisions required**

- Supply.
- Allocation.
- Rewards.
- Emission.
- Fee split.
- Burn.
- Treasury.
- Validator economics.

**Implementation required**

- Approved tokenomics specification.
- Invariant checklist.
- Economic test cases.
- Allocation manifest design.

**Dependencies**

- Architecture Freeze.
- Governance policy.
- Validator model.

**Exit criteria**

- All economic parameters approved.
- No testnet value is being used merely by default.
- Contract and genesis implications are documented.

### MAINNET-3 — Chain Identity

**Objective**

[MAINNET DECISION] Define and approve the mainnet identity.

**Decisions required**

- Network name.
- Chain ID.
- Token name and symbol.
- Identity-generation process.
- Blockchain, subnet, and conversion recording process.

**Implementation required**

- Identity reservation or generation procedure.
- Identity manifest format.
- Validation scripts.
- Documentation template.

**Dependencies**

- Architecture Freeze.
- Tokenomics Freeze.

**Exit criteria**

- Mainnet identity approved.
- Testnet and local identities are clearly separated.
- No genesis work proceeds with unresolved identity.

### MAINNET-4 — Validator & Infrastructure Design

**Objective**

[IMPLEMENTATION REQUIRED] Produce the approved infrastructure design without provisioning it.

**Decisions required**

- Validator count.
- Regions and providers.
- Hardware.
- RPC topology.
- Database and keeper hosting.
- Monitoring ownership.
- Backup infrastructure.

**Implementation required**

- Infrastructure plan.
- Firewall matrix.
- Node configuration plan.
- RPC and TLS plan.
- Recovery and replacement runbook.

**Dependencies**

- Architecture Freeze.
- Chain Identity.

**Exit criteria**

- Infrastructure design reviewed.
- Security review completed for the proposed topology.
- No server has been provisioned.

### MAINNET-5 — Genesis Design

**Objective**

[IMPLEMENTATION REQUIRED] Prepare the mainnet genesis specification.

**Decisions required**

- Genesis timestamp.
- Block timing.
- Gas configuration.
- Validator set.
- Allocations.
- Reward configuration.
- Native manager configuration.

**Implementation required**

- Genesis specification.
- Sidecar configuration.
- Allocation manifest.
- Reproducibility process.
- Genesis validation suite.

**Dependencies**

- Tokenomics Freeze.
- Chain Identity.
- Validator design.

**Exit criteria**

- Genesis specification approved.
- Genesis artifact has not yet been generated for launch.
- Independent review requirements are defined.

### MAINNET-6 — Protocol Deployment Design

**Objective**

[IMPLEMENTATION REQUIRED] Finalize contract deployment and control transfer.

**Decisions required**

- Deployment order.
- Deterministic address strategy.
- Ownership transfers.
- Multisig and timelock roles.
- StakingManager launch requirement.

**Implementation required**

- Mainnet deployment script design.
- Post-deployment verification plan.
- Role and ownership manifest.
- StakingManager implementation plan.

**Dependencies**

- Tokenomics.
- Governance.
- Genesis design.
- Native validator-manager design.

**Exit criteria**

- Deployment order is dependency-complete.
- StakingManager status is resolved.
- All post-deployment checks are specified.

### MAINNET-7 — Governance & Key Management

**Objective**

[SECURITY REVIEW REQUIRED] Approve the governance and custody model.

**Decisions required**

- Multisig signers and threshold.
- Timelock delay and roles.
- Treasury custody.
- Validator key custody.
- Keeper key custody.
- Emergency authority.

**Implementation required**

- Key ceremony procedure.
- Custody and backup policy.
- Rotation policy.
- Recovery policy.
- Approval matrix.

**Dependencies**

- Protocol deployment design.
- Validator design.
- Security review.

**Exit criteria**

- Policies approved.
- No production keys generated yet unless the next approved phase explicitly authorizes it.
- Recovery responsibility is assigned.

### MAINNET-8 — Indexer / Keeper / Explorer

**Objective**

[IMPLEMENTATION REQUIRED] Finalize production service requirements.

**Decisions required**

- Hosting topology.
- Failover.
- Indexer start block.
- Confirmation depth.
- Keeper redundancy.
- Explorer availability.
- API exposure.

**Implementation required**

- Mainnet configuration schema.
- Migration and backup plan.
- Keeper state and monitoring plan.
- PWCScan release configuration design.

**Dependencies**

- Chain identity.
- Contract deployment plan.
- Infrastructure design.

**Exit criteria**

- No testnet or local values remain in the planned mainnet configuration.
- Service ownership and recovery paths are approved.

### MAINNET-9 — Security & Recovery

**Objective**

[SECURITY REVIEW REQUIRED] Complete the security model.

**Decisions required**

- Incident severity.
- Emergency authority.
- Backup retention.
- Recovery targets.
- Upgrade and rollback policy.

**Implementation required**

- Threat model.
- Security checklist.
- Incident runbook.
- Backup restoration plan.
- Access review.

**Dependencies**

- All preceding architecture and governance decisions.

**Exit criteria**

- Security review completed.
- Recovery procedures are testable.
- Outstanding critical risks are accepted or resolved.

### MAINNET-10 — Testnet Exit Criteria

**Objective**

[TESTNET VERIFIED / IMPLEMENTATION REQUIRED] Define and complete the required Chain 77 evidence.

**Decisions required**

- Stability duration.
- Required failure scenarios.
- Required validator and keeper tests.
- Required StakingManager evidence.

**Implementation required**

- Test plans.
- Evidence collection.
- Failure/recovery rehearsals.
- Independent sign-off records.

**Dependencies**

- Protocol deployment design.
- Keeper and explorer requirements.
- Security criteria.

**Exit criteria**

- All approved exit tests pass.
- Open failures have explicit owner decisions.
- Mainnet is not launched solely on the basis of earlier testnet checks.

### MAINNET-11 — Mainnet Dry Run

**Objective**

[IMPLEMENTATION REQUIRED] Execute a complete isolated mainnet rehearsal.

**Decisions required**

- Dry-run environment.
- Participants.
- Acceptance criteria.
- Failure injection scope.

**Implementation required**

- Clean infrastructure.
- Genesis rehearsal.
- Validator formation.
- Protocol deployment.
- Keeper, indexer, explorer, monitoring, and recovery rehearsal.

**Dependencies**

- All preceding phases.

**Exit criteria**

- Dry run passes.
- Recovery paths work.
- Any failure produces a corrective action and repeat requirement.

### MAINNET-12 — Genesis Ceremony

**Objective**

[SECURITY REVIEW REQUIRED] Produce and approve the final mainnet genesis.

**Decisions required**

- Ceremony participants.
- Final approval authority.
- Artifact signing and archival.

**Implementation required**

- Final genesis artifact.
- Hash record.
- Validator configuration.
- Allocation verification.
- Independent review.

**Dependencies**

- Dry-run success.
- Security sign-off.
- Final identity and tokenomics.

**Exit criteria**

- Genesis is approved and archived.
- Hashes and identities are independently verified.
- No unresolved critical discrepancy remains.

### MAINNET-13 — Validator Bring-up

**Objective**

[IMPLEMENTATION REQUIRED] Form the mainnet validator network.

**Decisions required**

- Bring-up sequence.
- Go/no-go authority.
- Peer and liveness thresholds.

**Implementation required**

- Validator installation.
- Key loading through approved custody.
- Chain bootstrap.
- Peer verification.
- Block-production validation.

**Dependencies**

- Genesis ceremony.
- Approved infrastructure.
- Approved validator keys.

**Exit criteria**

- Validators are healthy.
- Peer connectivity is verified.
- Block production meets the approved criteria.

### MAINNET-14 — Final Launch Readiness

**Objective**

[SECURITY REVIEW REQUIRED] Confirm all production services and controls.

**Decisions required**

- Launch approval.
- Final rollback and incident posture.
- Public service exposure.

**Implementation required**

- RPC/TLS.
- Indexer/PostgreSQL.
- Keeper.
- PWCScan.
- Monitoring.
- Backups.
- Documentation.
- On-call handoff.

**Dependencies**

- Validator bring-up.
- All security and recovery approvals.

**Exit criteria**

- All launch checks pass.
- Production services are monitored.
- Owners and responders are assigned.
- Launch authority gives explicit approval.

### MAINNET-15 — Mainnet Launch

**Objective**

[MAINNET DECISION] Open the approved mainnet for its intended users and operators.

**Decisions required**

- Public launch time.
- Public RPC availability.
- Explorer availability.
- Initial operational limits.

**Implementation required**

- Controlled service activation.
- Public communications.
- Post-launch monitoring.
- Incident response readiness.

**Dependencies**

- Final Launch Readiness approval.

**Exit criteria**

- Mainnet is live only after explicit launch authorization.
- No launch occurs from a testnet configuration.
- Genesis, validator, contract, treasury, RPC, keeper, indexer, and explorer records are archived.

## 15. Immediate Next Step

# MAINNET-1 — ARCHITECTURE FREEZE

This is the correct immediate next phase.

Before touching implementation, the project must decide and document:

1. Which responsibilities remain in Replit.
2. Which responsibilities must run externally.
3. The target validator and RPC topology.
4. The external hosting boundary for indexer, PostgreSQL, keeper, and PWCScan.
5. The governance/control-layer boundary between multisig, timelock, treasury, emergency authority, and validator management.
6. The monitoring, backup, and recovery ownership model.
7. The required interfaces between validators, RPC, indexer, keeper, PostgreSQL, and PWCScan.
8. Which unresolved decisions are allowed to block later phases.
9. Whether StakingManager is a prerequisite for mainnet launch.
10. Who has authority to approve each subsequent mainnet phase.

### MAINNET-1 exit criteria

- Architecture document approved.
- Responsibility matrix approved.
- No production runtime assigned to Replit by assumption.
- Mainnet/testnet/local boundaries documented.
- Contract, validator, keeper, indexer, explorer, and governance dependencies mapped.
- No mainnet identifiers, keys, genesis, servers, or services created.

MIGRATION CLOSED.

PRIMEWAVE CHAIN IS NOW IN MAINNET PREPARATION.

NO MAINNET DEPLOYMENT HAS BEEN PERFORMED.