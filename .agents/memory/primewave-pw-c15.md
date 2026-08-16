---
name: PrimeWave Chain PW-C15
description: Testnet pre-launch sprint; arch docs + key ceremony + all blocker fixes; NO-GO (external gates)
---

# PW-C15 — Testnet Pre-Launch Sprint

## State
COMPLETE (all Replit-side work). External gates remain — operator must act.

## Critical Findings (architectural, persist forever)

### PoAManager predeploy address
`0x0Feedc0de0000000000000000000000000000000` — Avalanche CLI standard predeploy for ALL L1 chains.
Confirmed from `~/.avalanche-cli/subnets/primewavedev/sidecar.json`.
EIP-55 checksum form (required by Solidity): `0x0Feedc0de0000000000000000000000000000000`
Human-readable form used in docs: `0x0FEEDC0DE0000000000000000000000000000000`

### PWVR.validatorManager is IMMUTABLE
`PrimeWaveValidatorRegistry.validatorManager` is `public immutable` — no setter exists.
It must receive `0x0Feedc0de0000000000000000000000000000000` (POA_MANAGER_ADDR) at constructor time.
Old code passed `deployer` as placeholder — permanently broken. Fixed in DeployTestnet.s.sol.

### CLI flag: --num-bootstrap-validators (not --num-validators)
All prior docs said `--num-validators`. Correct flag is `--num-bootstrap-validators`.
`--bootstrap-filepath <json>` for non-interactive validator input.
`--balance 0.375` = AVAX per validator for continuous P-Chain fee; 4 × 0.375 = 1.5 AVAX total.
`--change-owner-address P-fuji1...` = required; P-Chain addr when validator exits.
Do NOT use `--convert-only` — it skips PoAManager initialization.

### bootstrap-validators.json format (from sidecar.json BootstrapValidators)
```json
[{"NodeID":"NodeID-...","Weight":100,"Balance":0.375,
  "BLSPublicKey":"0x<48-byte>","BLSProofOfPossession":"0x<96-byte>",
  "ChangeOwnerAddr":"P-fuji1..."}]
```

### DeployTestnet.s.sol must run AFTER L1 is live (PoAManager predeploy exists from block 0)
The script references `POA_MANAGER_ADDR` — this address is live as genesis alloc from block 0.
The script cannot run before the L1 chain exists (chainid 77 guard will fail anyway).

### cast wallet new --json outputs an ARRAY
Format: `[{"address":"0x...","private_key":"0x..."}]` — use `d[0]['address']`, not `d['address']`.
Fixed in generate-validator-keys.sh.

## Key Ceremony (PW-C15, 2026-08-16)
Keys stored at: `~/.primewave-keys/` (NOT in git; mode 700; each file mode 600)
Private key files format: JSON array from `cast wallet new --json`

Public addresses:
- testnet-deployer:     0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f
- testnet-keeper-signer:0x56A717F87A8Cdb6e855f44a947B5941f6ba3FfA1
- testnet-ems-signer-1: 0xb24F3FAF5B9ab7aFb625F105C791d5231b094853
- testnet-ems-signer-2: 0x508367082eF7A3A8567fa10D92c98524EE2F3d30
- testnet-ems-signer-3: 0xFa21258c9e5faa7aECbFD13f635863C5da0b8EC3
- testnet-ems-signer-4: 0xB1346A22773B853552aF028b767bD6cC0171006a
- testnet-ems-signer-5: 0x2D2d07AB95636Da735BAcBDC018420ca621C3448

FeeDistributor predicted: 0xFd069eE048bB748EE60ce53f99D8c2E6ec1D7f99
(deployer nonce=4; `cast compute-address 0x44A37aF5... --nonce 4`)

Saved to: local-data/testnet-key-addresses.env

## Blockers Fixed in Code
1. node-config.json: removed bootstrap-ids/ips placeholders; added partial-sync-primary-network:true
2. setup-testnet-node.sh: now copies canonical service file (deploy/testnet/systemd/); fixes specs to 4/8/200
3. preflight-testnet.sh: version check fixed to 1.15.0-fuji
4. generate-validator-keys.sh: version + JSON parse fixed
5. check-external-prerequisites.sh: deployer address updated
6. DeployTestnet.s.sol: POA_MANAGER_ADDR constant; EMS signers filled; registry constructor fixed
7. Checklist: 7 placeholders (was 6); --num-bootstrap-validators 4 (was --num-validators 3)
8. bootstrap-validators.json: template created at config/testnet/

## V6–V9 Provisioning (2026-08-16)
4 fresh Debian 13 (trixie) VPS nodes provisioned as testnet validators.
- V6 (152.53.66.93):   NodeID-144dTzcL2vgpbKzX943xy5pEF3M8oGyiQ
- V7 (152.53.66.201):  NodeID-cwX3HFmaR5QmbxuZaDJCXAueJeyewjni
- V8 (159.195.44.104): NodeID-7DLuPUaMiDbyVoZ6P92RQdNRFS81cpYb5
- V9 (159.195.47.126): NodeID-9TiHzx7DZgtCjB9pqyY6db55pZgVZELvJ
All 9 nodes (V2-V9) have unique NodeIDs. BLS keys in bootstrap-validators.json.
Partial-sync confirmed: "skipping primary network chain creation" in logs on all 4.
Staking keys at /home/avalanche/.avalanchego/staking/ (not /data/avalanchego/staking/).
AvalancheGo uses nodePOP.publicKey / nodePOP.proofOfPossession (not top-level) in info.getNodeID.
bootstrap-validators.json: filled except ChangeOwnerAddr (needs deployer P-Chain addr).
Report: docs/PW-C15-V6-V9-PROVISIONING-REPORT.md

## External Gates Still Blocking
- 4 VPS servers not provisioned
- Fuji AVAX: deployer 0x44A37aF5... has 0 AVAX (fund via faucet.avax.network)
- bootstrap-validators.json: needs NodeID+BLS from all 4 nodes after provisioning
- 5 genesis wallet addresses not yet provided by operator
- `avalanche blockchain create primewave-testnet` not yet run (depends on genesis being final)

**Why:** These require physical server provisioning and external wallet decisions outside Replit scope.

## Files Created This Sprint
- docs/PW-C15-VALIDATOR-MANAGER-FLOW.md (PoAManager architecture; 12 Q&A; deployment order)
- docs/PW-C15-FUJI-CEREMONY-RUNBOOK.md (operator runbook; exact CLI commands; error recovery)
- docs/PW-C15-EOD-LAUNCH-READINESS.md (GO/NO-GO report; 5 external gates)
- local-data/testnet-key-addresses.env (public addresses only)
- config/testnet/bootstrap-validators.json (template; needs node identities)
