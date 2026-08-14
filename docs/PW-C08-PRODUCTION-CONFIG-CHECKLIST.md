# PW-C08 Production Configuration Checklist

> Sprint: PW-C08 Protocol Integration + Production Configuration Hardening
> Status: REFERENCE DOCUMENT
> Date: 2026-08-14

This checklist MUST be completed before mainnet or public testnet launch. All items are binary PASS/FAIL. Do not launch with any FAIL.

---

## PHASE 0 — Pre-Deployment Prerequisites

### Key Infrastructure

| # | Check | Method | Status |
|---|-------|--------|--------|
| P-01 | 5 EMS signer keys are hardware wallets (Ledger/Trezor/YubiKey HSM) | Physical verification with each signer | [ ] |
| P-02 | EMS signers are geographically distributed (no 2 share a location) | Signer declaration | [ ] |
| P-03 | Protocol Admin multisig (3-of-N) created and tested | On-chain test transaction | [ ] |
| P-04 | Protocol Admin multisig has been used for at least 1 real transaction | Transaction receipt | [ ] |
| P-05 | Timelock proposer multisig is separate from the EMS multisig | Address comparison | [ ] |
| P-06 | Cold-storage emergency recovery plan documented and tested | Dry-run exercise | [ ] |

### Network Infrastructure

| # | Check | Method | Status |
|---|-------|--------|--------|
| P-07 | AvalancheGo node version >= 1.14.2 on all validators | `avalanchego --version` | [ ] |
| P-08 | Subnet-EVM binary compiled from source at pinned commit | Build verification | [ ] |
| P-09 | 15 initial validator nodes provisioned and reachable | Node liveness check | [ ] |
| P-10 | All validators have 99th-percentile uptime SLA guarantees | SLA agreement | [ ] |
| P-11 | P-Chain ConvertSubnetToL1Tx is prepared but NOT submitted | Transaction draft | [ ] |

---

## PHASE 1 — Genesis Construction

### Supply Allocation

| # | Check | Method | Status |
|---|-------|--------|--------|
| G-01 | Total genesis alloc exactly 100,000,000 PW | Sum all alloc entries | [ ] |
| G-02 | NativeMinter is NOT in `allowList` of any precompile config | `grep -i nativeminter genesis.json` | [ ] |
| G-03 | NativeMinter is NOT in `precompiles` section | `jq '.config.precompiles' genesis.json` | [ ] |
| G-04 | RewardManagerConfig.rewardAddress is FeeDistributor address | `jq '.config.rewardManagerConfig' genesis.json` | [ ] |
| G-05 | Chain ID in genesis matches production value (NOT 73571 which is devnet) | `jq '.config.chainId' genesis.json` | [ ] |
| G-06 | Genesis timestamp is set to planned launch epoch | `jq '.timestamp' genesis.json` | [ ] |
| G-07 | All allocation addresses are multisig/contract addresses, NOT bare EOAs | Address audit | [ ] |
| G-08 | PWSwap liquidity 40M PW allocation is to audited lock contract | Lock contract audit | [ ] |
| G-09 | RewardVault allocation is exactly 15,000,000 PW | `jq '.alloc["RV_ADDR"].balance' genesis.json` | [ ] |
| G-10 | genesis.json has been independently reviewed by 2+ engineers | Dual review signatures | [ ] |

---

## PHASE 2 — Contract Deployment

### Deployment Sequence

| # | Check | Method | Status |
|---|-------|--------|--------|
| D-01 | EmergencyMultisig deployed FIRST (before FeeDistributor) | Deployment tx order | [ ] |
| D-02 | EmergencyMultisig address used as FeeDistributor.pauseController | Constructor event / storage read | [ ] |
| D-03 | FeeDistributor deployed with correct vault, treasury, EMS addresses | Constructor args | [ ] |
| D-04 | ValidatorFeeVault protocolAdmin set to PrimeWaveValidatorRegistry (NOT DEV0 EOA) | Storage read | [ ] |
| D-05 | ValidatorFeeVault pauseController set to EmergencyMultisig | Storage read | [ ] |
| D-06 | RewardVault admin set to production multisig (NOT DEV0 EOA) | Storage read | [ ] |
| D-07 | RewardVault pauseController set to EmergencyMultisig | Storage read | [ ] |
| D-08 | PrimeWaveTimelock proposer set to production multisig | Storage read | [ ] |
| D-09 | PrimeWaveTimelock MIN_DELAY == 172800 | Contract read | [ ] |
| D-10 | PrimeWaveValidatorRegistry deployed pointing to ValidatorFeeVault | Constructor args | [ ] |
| D-11 | No DEV0 EOA appears as admin/owner of any protocol contract | `ValidateGenesis.s.sol` output | [ ] |

### Address Verification

| # | Check | Method | Status |
|---|-------|--------|--------|
| A-01 | FeeDistributor.validatorFeeVault() == ValidatorFeeVault address | Contract read | [ ] |
| A-02 | FeeDistributor.treasury() == DevTreasury address | Contract read | [ ] |
| A-03 | FeeDistributor.BURN_ADDRESS() == 0x000000000000000000000000000000000000dEaD | Contract read | [ ] |
| A-04 | DevTreasury.feeDistributor() == FeeDistributor address | Contract read | [ ] |
| A-05 | genesis.rewardManagerConfig.rewardAddress == FeeDistributor address | Genesis comparison | [ ] |
| A-06 | All 5 EmergencyMultisig.isSigner(addr) return true for correct addresses | Contract read x5 | [ ] |
| A-07 | EmergencyMultisig.THRESHOLD() == 3 | Contract read | [ ] |
| A-08 | All contract bytecodes match expected hashes from audit | `cast codehash <addr>` comparison | [ ] |

---

## PHASE 3 — Automated Validation

### ValidateGenesis.s.sol Output

Run the following command and verify ALL lines show [PASS]:

```bash
export DIST_ADDRESS=<FeeDistributor>
export VAULT_ADDRESS=<ValidatorFeeVault>
export TREASURY_ADDRESS=<DevTreasury>
export RV_ADDRESS=<RewardVault>
export EMS_ADDRESS=<EmergencyMultisig>
export TIMELOCK_ADDRESS=<PrimeWaveTimelock>

forge script contracts/script/ValidateGenesis.s.sol \
  --rpc-url <production-rpc> \
  --sig "run()" -vv 2>&1 | tee genesis-validation.log

grep -c "\[PASS\]" genesis-validation.log
grep "\[FAIL\]" genesis-validation.log
grep "\[WARN\]" genesis-validation.log
```

Expected: 0 FAILs. All WARNs reviewed and acknowledged.

| # | Check | Method | Status |
|---|-------|--------|--------|
| V-01 | ValidateGenesis.s.sol exits with 0 FAILs | Script output | [ ] |
| V-02 | All WARN items documented and acknowledged | Written acknowledgement | [ ] |
| V-03 | Script output archived in `docs/validation/genesis-validation-[date].log` | File present | [ ] |

---

## PHASE 4 — Pre-Launch Tests

### Integration Smoke Tests

| # | Check | Method | Status |
|---|-------|--------|--------|
| T-01 | End-to-end fee test: send tx, call distribute(), verify VFV.totalReceived increments | On-chain test | [ ] |
| T-02 | End-to-end claim test: register validator, receive fees, claimFees() succeeds | On-chain test | [ ] |
| T-03 | Pause test: EMS.propose() + 3x approve() + execute() pauses FeeDistributor | On-chain test | [ ] |
| T-04 | Unpause test: EMS pauses then unpauses, distribute() succeeds after | On-chain test | [ ] |
| T-05 | Timelock test: schedule() + 48h wait + execute() updates validator weight | On-chain test (staging) | [ ] |
| T-06 | RewardVault test: setEmissionRate(), advance time, claim() | On-chain test | [ ] |
| T-07 | Supply audit: totalSupply() (if available) == 100,000,000 PW | Balance sum | [ ] |
| T-08 | Burn audit: 0x000...dEaD balance increases after distribute() | Balance before/after | [ ] |

### Edge Case Checks

| # | Check | Method | Status |
|---|-------|--------|--------|
| E-01 | distribute() with 0 balance is a no-op (no revert) | On-chain test | [ ] |
| E-02 | claimFees() with 0 claimable is a no-op (no revert) | On-chain test | [ ] |
| E-03 | setEmissionRate(higherRate) reverts | On-chain test | [ ] |
| E-04 | Non-EMS address cannot call pause() | On-chain test | [ ] |
| E-05 | EMS cannot call registerValidator() | On-chain test | [ ] |
| E-06 | Timelock cannot call pause() directly | On-chain test | [ ] |

---

## PHASE 5 — Validator Onboarding

### Validator Registration

| # | Check | Method | Status |
|---|-------|--------|--------|
| R-01 | All 15 Phase-1 validators registered in PrimeWaveValidatorRegistry | Registry.validatorCount() == 15 | [ ] |
| R-02 | All validators have non-zero effectiveWeight | VFV.getValidator(id).effectiveWeight > 0 | [ ] |
| R-03 | All validators have correct rewardRecipient set | VFV.getValidator(id).rewardRecipient != address(0) | [ ] |
| R-04 | totalEffectiveWeight > 0 (distribution will not divide by zero) | VFV.totalEffectiveWeight() > 0 | [ ] |
| R-05 | accFeePerWeight starts at 0 (fresh deployment) | VFV.accFeePerWeight() == 0 | [ ] |
| R-06 | Each validator's rewardRecipient tested with small claimFees() call | Receipt verification | [ ] |

---

## PHASE 6 — Monitoring Setup

### Alert Infrastructure

| # | Check | Method | Status |
|---|-------|--------|--------|
| M-01 | Event monitor running for `FeeDistributor.Distributed` | Monitor output | [ ] |
| M-02 | Alert if pending FD balance > 10 ETH for > 1 hour | Alert test | [ ] |
| M-03 | Immediate alert on `ValidatorFeeVault.Paused` | Alert test | [ ] |
| M-04 | Immediate alert on `RewardVault.Paused` | Alert test | [ ] |
| M-05 | Immediate alert on `EmergencyMultisig.ProposalCreated` | Alert test | [ ] |
| M-06 | 24/7 on-call rotation for EMS signers | Rotation schedule | [ ] |
| M-07 | Block explorer configured for PrimeWave L1 | Explorer URL documented | [ ] |
| M-08 | RPC endpoint documented and rate-limit tested | Load test | [ ] |

---

## PHASE 7 — Post-Launch First 24 Hours

### Verification Window

| # | Check | Method | Status |
|---|-------|--------|--------|
| L-01 | First 100 blocks produce correct fee events | Log review | [ ] |
| L-02 | VFV.totalReceived growing proportionally to gas usage | Chart | [ ] |
| L-03 | Treasury balance growing at ~20% rate of VFV | Balance monitor | [ ] |
| L-04 | Burn address receiving ~10% of fees | Balance monitor | [ ] |
| L-05 | No unexpected revert events in any protocol contract | Log scan | [ ] |
| L-06 | Block finality time within spec (< 2s) | Prometheus metric | [ ] |

---

## Quick Reference: Production Deployment Order

```
1. Deploy EmergencyMultisig(signer1, signer2, signer3, signer4, signer5)
2. Deploy PrimeWaveTimelock(protocolAdminMultisig)
3. Deploy PrimeWaveValidatorRegistry(validatorManager, address(0)) -- placeholder FD
4. Deploy ValidatorFeeVault(registryAddress)
5. Deploy DevTreasury(address(0)) -- placeholder FD
6. Deploy FeeDistributor(vaultAddress, treasuryAddress, emsAddress) -- THIS SETS FD ADDR
7. Call registry.setFeeDistributor(fdAddress) [if registry supports this]
8. Call devTreasury.setFeeDistributor(fdAddress) [if treasury supports this]
9. Call vault.setPauseController(emsAddress)
10. Deploy RewardVault(protocolAdminMultisig, maxRate)
11. Call rv.setPauseController(emsAddress)
12. Fund RewardVault with 15,000,000 PW
13. Register 15 validators via registry.registerValidator()
14. Run ValidateGenesis.s.sol ---> ALL PASS
15. Schedule timelock.transferProposer(productionMultisig) -- 48h wait
16. Execute timelock.transferProposer(productionMultisig)
17. Go live
```

**Critical ordering constraint:** EMS must be deployed before FD so EMS address can be passed to FD constructor. There is no `setPauseController()` on FeeDistributor.
