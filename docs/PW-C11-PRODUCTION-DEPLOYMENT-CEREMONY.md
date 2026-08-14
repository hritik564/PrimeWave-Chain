# PW-C11: Production Deployment Ceremony

**Sprint:** C11 — Production Infrastructure + Validator Keeper + Genesis Finalization
**Status:** COMPLETE (procedure finalized — ceremony date TBD)
**Date:** 2026-08-14

---

## Overview

The production deployment ceremony is the irreversible step that launches PrimeWave Chain on mainnet. It MUST be preceded by a successful rehearsal (`PW-C11-DEPLOYMENT-REHEARSAL.md`).

**This document is a PROCEDURE, not a script.** Every step requires human confirmation.

---

## Pre-Ceremony Checklist

All of the following must be complete before the ceremony begins:

### Technical
- [ ] Rehearsal completed with 30/30 PASS (`PW-C11-DEPLOYMENT-REHEARSAL.md`)
- [ ] `forge test` passing (≥ 745 tests)
- [ ] C10 audit findings all resolved or accepted-as-designed
- [ ] Keeper service built and tested (20/20 keeper tests pass)
- [ ] All 5 validator nodes provisioned and passing health check
- [ ] All 2 RPC nodes provisioned and passing health check
- [ ] Sentinel node provisioned with keeper + monitoring stack
- [ ] Monitoring dashboards configured and receiving test metrics
- [ ] Alert escalation tested end-to-end (PagerDuty/Slack)

### Security
- [ ] All 5 EMS signers have confirmed key availability
- [ ] Protocol admin hardware wallet confirmed operational
- [ ] Validator staking keys generated on offline machines
- [ ] All staking keys backed up per `PRIMEWAVE_KEY_SECURITY_PROCEDURE.md`
- [ ] Funding key (for 15M RewardVault) confirmed operational
- [ ] `PRIMEWAVE_ENV=production` set on deployment machine
- [ ] Deployment machine air-gapped or in secure environment

### Governance
- [ ] All genesis allocation addresses confirmed (hardware wallets)
- [ ] Genesis JSON approved and hash recorded
- [ ] Team multisig key holders confirmed present
- [ ] EMS signers briefed on emergency pause procedure

---

## Ceremony Participants

| Role | Responsibility | Required |
|------|---------------|----------|
| Ceremony Lead | Coordinates all steps, reads checklist | Yes |
| Protocol Admin | Signs deployment transactions | Yes |
| Funding Signer | Signs 15M PW RewardVault transfer | Yes |
| EMS Signers (3 of 5) | Available for emergency | Yes |
| Infrastructure Lead | Validates nodes are healthy | Yes |
| Security Observer | Verifies no deviations from procedure | Yes |

---

## Ceremony Steps

### Phase 1: Final Pre-Flight (T - 30 minutes)

**1.1** All participants confirm presence and hardware wallet accessibility.

**1.2** Run final health check on all nodes:
```bash
for host in validator-{1,2,3,4,5} rpc-{1,2} sentinel; do
  echo "=== $host ===" && ssh $host ./scripts/health-check.sh
done
```
**Must pass all nodes.**

**1.3** Confirm deployment environment:
```bash
echo "PRIMEWAVE_ENV=$PRIMEWAVE_ENV"           # must be "production"
echo "Chain ID will be: 73571"
forge --version                                # must be v1.7.1
```

**1.4** Record ceremony start time and participant list in the incident log.

---

### Phase 2: Subnet and Blockchain Creation (T + 0)

**2.1** Create subnet on Avalanche mainnet using AvalancheCLI or Avalanche Wallet.

**2.2** Record **Subnet ID** (irreversible after this point for subnet configuration).

**2.3** Create blockchain on the subnet using the approved genesis JSON.

**2.4** Record **Blockchain ID** (used in all subsequent configuration).

**2.5** Distribute Blockchain ID and Subnet ID to all participants.

---

### Phase 3: Contract Deployment (T + 30 minutes)

**3.1** Set environment variables on deployment machine:
```bash
export PRIMEWAVE_ENV=production
export PRIMEWAVE_CHAIN_ID=73571
export CHAIN_RPC_URL="http://[RPC_NODE_IP]:9650/ext/bc/$BLOCKCHAIN_ID/rpc"
export DEPLOYER_PRIVATE_KEY="[hardware wallet key — enter at runtime]"
export FUNDING_PRIVATE_KEY="[funding key — enter at runtime]"
export EMS_SIGNER_1="0x..."  # through EMS_SIGNER_5
export VALIDATOR_MANAGER_ADDRESS="0x..."
```

**3.2** Run production deployment script (dry-run first):
```bash
cd contracts/
forge script script/DeployProduction.s.sol:DeployProductionScript \
  --rpc-url $CHAIN_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --sig "run()" \
  -vvv
  # NO --broadcast yet
```

**3.3** Review dry-run output. Ceremony Lead confirms all addresses and parameters.

**3.4** Broadcast (irreversible):
```bash
forge script script/DeployProduction.s.sol:DeployProductionScript \
  --rpc-url $CHAIN_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --sig "run()" \
  -vvv 2>&1 | tee /tmp/deployment-output.txt
```

**3.5** Record all deployed contract addresses from output.

---

### Phase 4: Genesis Validation (T + 60 minutes)

**4.1** Set contract addresses from Phase 3 output:
```bash
export DIST_ADDRESS="0x..."
export VAULT_ADDRESS="0x..."
export TREASURY_ADDRESS="0x..."
export RV_ADDRESS="0x..."
export EMS_ADDRESS="0x..."
export TIMELOCK_ADDRESS="0x..."
```

**4.2** Run genesis validation:
```bash
./scripts/validate-production-genesis.sh
# Must show: STATUS: ALL CHECKS PASSED
```

**4.3** Run Forge genesis validator:
```bash
forge script contracts/script/ValidateGenesis.s.sol \
  --rpc-url $CHAIN_RPC_URL \
  --sig "run()" -vvv
# Must complete with 0 FAIL
```

**4.4** If any check fails: **ABORT** (see Phase 7: Abort Conditions).

---

### Phase 5: Validator Bootstrap (T + 90 minutes)

**5.1** Distribute updated node configuration (with real Blockchain ID and Subnet ID) to all validator nodes.

**5.2** Start validator nodes one at a time, verifying each before starting the next:
```bash
ssh validator-1 ./scripts/start-validator.sh
# Wait 60s
ssh validator-1 ./scripts/health-check.sh
# Must be healthy before starting next
```

**5.3** Repeat for validators 2–5.

**5.4** Verify consensus: all 5 validators must be in peer with each other.

---

### Phase 6: Keeper + Monitoring Activation (T + 120 minutes)

**6.1** Configure keeper on sentinel node with production addresses.

**6.2** Start keeper:
```bash
ssh sentinel 'systemctl start primewave-keeper'
# Wait 60s
curl http://sentinel:8080/health  # must be healthy
```

**6.3** Verify first keeper poll completes successfully (check logs).

**6.4** Enable monitoring dashboards and confirm metrics flowing.

**6.5** Test alert routing: trigger a test alert, confirm PagerDuty/Slack receives it.

---

### Phase 7: Final Verification

**7.1** Run complete health check against all nodes:
```bash
./scripts/health-check.sh
```

**7.2** Verify block production on production chain.

**7.3** Record in docs:
- All deployed contract addresses → `docs/PRIMEWAVE_INFRASTRUCTURE.md`
- Real Subnet ID and Blockchain ID → `docs/PRIMEWAVE_GENESIS_SPEC.md`
- Ceremony completion timestamp

**7.4** All participants sign off (confirm in incident log).

---

### Phase 8: Abort Conditions

Abort immediately and halt deployment if any of the following occur:

- [ ] ValidateGenesis shows 1+ FAIL
- [ ] `DeployProduction.s.sol` reverts
- [ ] Funding transaction fails (15M PW not transferred exactly)
- [ ] Any validator node fails health check after startup
- [ ] Keeper health endpoint returns `unhealthy`
- [ ] Security observer raises a concern
- [ ] Any participant requests abort

**On abort:**
1. Do NOT attempt to continue
2. Do NOT attempt partial recovery without full team review
3. Log the failure point and all contract addresses deployed so far
4. Schedule post-mortem within 24 hours
5. If contracts are already deployed: contact has no admin backdoor — contracts cannot be recovered
6. If chain is not yet bootstrapped with validators: the subnet can be abandoned and a new one created after fixing the issue

---

## Post-Ceremony Documentation

Within 24 hours of successful ceremony:
- [ ] Update `docs/PRIMEWAVE_INFRASTRUCTURE.md` with all deployed addresses
- [ ] Update `docs/PRIMEWAVE_GENESIS_SPEC.md` with real Blockchain ID and Subnet ID
- [ ] Update `docs/PW-C11-TEST-REPORT.md` with production deployment record
- [ ] Archive ceremony log with all transaction hashes
- [ ] Brief EMS signers with production contract addresses
- [ ] Announce chain launch to community

---

## References

- `docs/PW-C11-DEPLOYMENT-REHEARSAL.md` — Run this first
- `contracts/script/DeployProduction.s.sol` — Deployment script
- `contracts/script/IntegrationC11.s.sol` — Rehearsal script
- `docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md` — Key security
- `docs/PRIMEWAVE_GOVERNANCE_POLICY.md` — Governance policy
