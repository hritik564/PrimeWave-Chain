# PW-C15 — TESTNET BATTLE TEST

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** PENDING EXTERNAL EXECUTION
**Environment:** TESTNET ONLY — Chain ID 77 (EVM) / hex 0x4d
**Document scope:** Genesis ceremony → Fuji P-Chain → network launch → full battle test

> **Infrastructure requirement:** Every section in this document that touches live
> nodes, validators, or on-chain state requires external cloud/Fuji infrastructure.
> Where a result is not yet available, the expected outcome, acceptance criteria,
> and actual-value field are clearly marked.

---

## 1. PRE-LAUNCH CHECKLIST

Before executing the genesis ceremony, verify every item below is complete from C14:

| # | Item | Status |
|---|---|---|
| 1 | `config/testnet/genesis-template.json` present | ✅ C14 |
| 2 | All `__REPLACE_*__` placeholders identified | ✅ C14 |
| 3 | `scripts/testnet/validate-testnet-genesis.sh` present | ✅ C14 |
| 4 | `contracts/script/DeployTestnet.s.sol` enforces Chain ID 77 | ✅ C14 |
| 5 | `scripts/testnet/deploy-contracts.sh` enforces Chain ID 77 | ✅ C14 |
| 6 | `scripts/testnet/testnet-health-check.sh` checks `eth_chainId == 0x4d` | ✅ C14 |
| 7 | Systemd units present in `deploy/testnet/systemd/` | ✅ C14 |
| 8 | Nginx configs present in `deploy/testnet/nginx/` | ✅ C14 |
| 9 | Prometheus + alert rules present | ✅ C14 |
| 10 | Forge 792/792 | ✅ C15 regression |
| 11 | Keeper 20/20 | ✅ C15 regression |
| 12 | Indexer 57/57 | ✅ C15 regression |
| 13 | Cloud server infrastructure provisioned | 🔵 PENDING external |
| 14 | Fuji AVAX available for P-Chain transactions | 🔵 PENDING external |
| 15 | DNS entries configured (testnet.primewave.xyz or equivalent) | 🔵 PENDING external |
| 16 | TLS certificates issued | 🔵 PENDING external |
| 17 | Key ceremony participants confirmed | 🔵 PENDING external |

---

## 2. TESTNET GENESIS CEREMONY

### 2.1 Placeholder Resolution

Fill every `__REPLACE_*__` field in `config/testnet/genesis-template.json` with the
real testnet ceremony addresses:

| Placeholder | Description | Actual Value |
|---|---|---|
| `__REPLACE_DEPLOYER__` | Deployer/bootstrap address | TBD — ceremony |
| `__REPLACE_TREASURY__` | Treasury multisig | TBD — ceremony |
| `__REPLACE_TEAM__` | Team vesting contract/multisig | TBD — ceremony |
| `__REPLACE_COMMUNITY__` | Community allocation address | TBD — ceremony |
| `__REPLACE_ECOSYSTEM__` | Ecosystem fund address | TBD — ceremony |
| `__REPLACE_RESERVE__` | Reserve address | TBD — ceremony |
| `__REPLACE_FEE_DISTRIBUTOR__` | FeeDistributor deploy address | TBD — predicted pre-deploy |
| `__REPLACE_REWARD_MANAGER__` | RewardManager (subnet-evm precompile) | TBD |
| `__REPLACE_VALIDATOR_MANAGER__` | ACP-99 ValidatorManager | TBD — predicted pre-deploy |

Do NOT guess any address. Use pre-computed addresses from the deployer account nonce.

### 2.2 Genesis Generation

```bash
# After filling all placeholders:
cp config/testnet/genesis-template.json config/testnet/genesis.json
# Remove all _label / _chain_id_history metadata keys
python3 scripts/testnet/strip-genesis-metadata.py \
  config/testnet/genesis-template.json \
  config/testnet/genesis.json
```

### 2.3 Genesis Invariant Verification

Run the validate script and verify all invariants:

```bash
bash scripts/testnet/validate-testnet-genesis.sh config/testnet/genesis.json
```

| Invariant | Check | Expected | Actual |
|---|---|---|---|
| INV-G1 | Chain ID | 77 | TBD |
| INV-G2 | Total supply | 100,000,000 PW | TBD |
| INV-G3 | NativeMinter disabled | contractAddress absent or allowList empty | TBD |
| INV-G4 | No hidden minting path | No additional precompile allowList | TBD |
| INV-G5 | RewardVault funded | 15,000,000 PW at vault address | TBD |
| INV-G6 | RewardManager → FeeDistributor | `rewardManager.rewardAddress == FeeDistributor` | TBD |
| INV-G7 | 70/20/10 FeeDistributor split | `feeConfig` fields match | TBD |
| INV-G8 | No production addresses | All alloc keys are testnet-ceremony keys | TBD |
| INV-G9 | No dev addresses | 0x... dev addresses absent | TBD |

**STOP CONDITION:** Any failed invariant halts the launch.

### 2.4 Genesis Record

| Field | Value |
|---|---|
| Chain ID (EVM) | 77 |
| Chain ID (hex) | 0x4d |
| Genesis hash | TBD — `sha256sum genesis.json` |
| Genesis file hash (SHA-256) | TBD |
| Total supply at genesis | 100,000,000 PW |
| NativeMinter status | DISABLED |
| Subnet ID | TBD — Fuji P-Chain |
| Blockchain ID | TBD — Fuji P-Chain |

---

## 3. FUJI P-CHAIN DEPLOYMENT

### 3.1 Transaction Sequence

Execute in order using Avalanche CLI v1.9.5+ with AvalancheGo v1.14.2:

```bash
# Step 1: Create subnet
avalanche blockchain create primewave-testnet \
  --genesis config/testnet/genesis.json \
  --vm subnet-evm \
  --testnet

# Step 2: Deploy to Fuji
avalanche blockchain deploy primewave-testnet \
  --testnet \
  --key testnet-deployer

# Step 3: Record subnet ID and blockchain ID from output
```

### 3.2 Transaction Record

| Transaction | Type | TX ID | Status |
|---|---|---|---|
| CreateSubnetTx | P-Chain | TBD | 🔵 PENDING |
| CreateChainTx | P-Chain | TBD | 🔵 PENDING |
| ConvertSubnetToL1Tx | P-Chain | TBD | 🔵 PENDING |

### 3.3 Network Identity Record

| Field | Value |
|---|---|
| Subnet ID | TBD |
| Blockchain ID | TBD |
| AvalancheGo version | v1.14.2 (pinned) |
| subnet-evm version | matching C14 pin |

> **NOTE:** Chain ID 77 (EVM application layer) is distinct from Blockchain ID
> (P-Chain 32-byte hash) and Subnet ID (P-Chain 32-byte hash).

---

## 4. CONTRACT DEPLOYMENT

### 4.1 Pre-deployment Safety Checks

```bash
# Must succeed before any deployment
cast chain-id --rpc-url $TESTNET_RPC_URL  # Must return 77
```

### 4.2 Deployment Execution

```bash
export TESTNET_RPC_URL=https://rpc.testnet.primewave.xyz
export TESTNET_CHAIN_ID=77

bash scripts/testnet/deploy-contracts.sh
# OR
forge script contracts/script/DeployTestnet.s.sol \
  --via-ir \
  --rpc-url $TESTNET_RPC_URL \
  --broadcast \
  --slow
```

### 4.3 Deployed Address Record

| Contract | Expected Address | Actual Address | Deployment TX |
|---|---|---|---|
| FeeDistributor | TBD — pre-computed | TBD | TBD |
| ValidatorFeeVault | TBD — pre-computed | TBD | TBD |
| PrimeWaveValidatorRegistry | TBD — pre-computed | TBD | TBD |
| PrimeWaveStakingManager | TBD — pre-computed | TBD | TBD |
| RewardVault | TBD — pre-computed | TBD | TBD |
| DevTreasury | TBD — pre-computed | TBD | TBD |
| EmergencyMultisig | TBD — pre-computed | TBD | TBD |
| PrimeWaveTimelock | TBD — pre-computed | TBD | TBD |

---

## 5. ACP-99 REAL VALIDATOR FLOW

Do NOT use MockValidatorManager, devActivate, or any test-only shortcut.

### 5.1 Real Validator Lifecycle

```
register validator on P-Chain
        ↓
ValidatorManager.completeValidatorRegistration() via Warp
        ↓
PrimeWaveValidatorRegistry receives sync via Keeper
        ↓
validator becomes eligible for fees and rewards
        ↓
participates in block production
```

### 5.2 Acceptance Criteria

| Step | Test | Expected | Actual |
|---|---|---|---|
| Registration | P-Chain registration confirmed | Subnet validator active | TBD |
| Warp delivery | ICM message received by ValidatorManager | Registration completed | TBD |
| Registry sync | Keeper calls syncValidator() | Registry entry created | TBD |
| Fee eligibility | ValidatorFeeVault.weight(validator) > 0 | Non-zero weight | TBD |
| Block production | Validator signs blocks | Blocks appear on chain | TBD |

---

## 6. ICM / WARP PATH VERIFICATION

### 6.1 Message Flow

```
Fuji P-Chain validator change
        ↓
Warp aggregate signature
        ↓
ICM relayer picks up
        ↓
ACP-99 ValidatorManager.completeValidatorRegistration()
        ↓
PrimeWaveValidatorRegistry.syncValidator()
        ↓
ValidatorFeeVault weight update
```

### 6.2 Test Cases

| Test | Scenario | Expected | Actual |
|---|---|---|---|
| ICM-01 | Normal message delivery | Delivered within 3 blocks | TBD |
| ICM-02 | ICM relayer restart during delivery | Message re-delivered on recovery | TBD |
| ICM-03 | Duplicate Warp message | Deduplicated — no double registration | TBD |
| ICM-04 | Delayed message (relayer 5m lag) | Eventually delivered | TBD |
| ICM-05 | Failed delivery (no quorum) | Retry triggered; no state corruption | TBD |
| ICM-06 | Message order permutation | Final state consistent | TBD |

### 6.3 Message Record

| Event | Warp Message ID | Block | Status |
|---|---|---|---|
| Validator 1 registration | TBD | TBD | 🔵 PENDING |
| Validator 1 weight update | TBD | TBD | 🔵 PENDING |
| Validator 1 removal | TBD | TBD | 🔵 PENDING |

---

## 7. FEE DISTRIBUTION BATTLE TEST

### 7.1 Protocol

```
tx fee paid by user
        ↓
FeeDistributor (precompile → FeeDistributor contract)
        ├── 70% → ValidatorFeeVault
        ├── 20% → Treasury
        └── 10% → burned / inaccessible address
```

### 7.2 Test Matrix

| Test | Scenario | Expected | Actual |
|---|---|---|---|
| FD-01 | Normal transfer, 21000 gas | 70/20/10 split verified | TBD |
| FD-02 | Contract interaction, higher gas | 70/20/10 split verified | TBD |
| FD-03 | Very small fee (1 gwei base) | Rounding goes to burn (10%) | TBD |
| FD-04 | Large fee (ERC-20 deploy) | Split correct at scale | TBD |
| FD-05 | 1000 sequential txs | Conservation holds for entire batch | TBD |
| FD-06 | Validator churn mid-batch | Historical fees preserved | TBD |
| FD-07 | Multiple validators | Weight-proportional distribution | TBD |
| FD-08 | Conservation check | sum(in) == sum(validator + treasury + burn) | TBD |

**Acceptance:** No conservation violation in any scenario.

---

## 8. REWARDVAULT BATTLE TEST

### 8.1 Protocol

- 15,000,000 PW locked in RewardVault at genesis
- Maximum emission: 3,000,000 PW/year
- totalEmitted is write-only (accumulator, never decremented)
- No minting path — vault can only pay out what it holds

### 8.2 Test Matrix

| Test | Scenario | Expected | Actual |
|---|---|---|---|
| RV-01 | Initial vault balance | 15,000,000 PW | TBD |
| RV-02 | Annual rate check | ≤ 3M PW/year at current rate | TBD |
| RV-03 | Multiple validators claim | Individual claims correct | TBD |
| RV-04 | Reward address change | New address receives future rewards | TBD |
| RV-05 | Weight change effect | Proportional distribution verified | TBD |
| RV-06 | Validator deactivation | Reward accrual pauses | TBD |
| RV-07 | Reactivation | Accrual resumes from deactivation point | TBD |
| RV-08 | Exhaustion scenario (simulated) | Rate reduction or emission halt | TBD |
| RV-09 | Zero-weight validator | No reward leakage | TBD |
| RV-10 | totalEmitted invariant | totalEmitted monotonically increases | TBD |
| RV-11 | Minting check | No way to call mint on token | TBD |

---

## 9. STAKING BATTLE TEST

### 9.1 Protocol

- Stake → validator eligibility → reward accrual → claim → unbond (14-day) → withdraw
- 14-day unbonding period is a protocol parameter — DO NOT reduce for testnet convenience

### 9.2 Test Matrix

| Test | Scenario | Expected | Actual |
|---|---|---|---|
| ST-01 | Stake PW on testnet | Stake confirmed on-chain | TBD |
| ST-02 | Validator eligibility threshold | Correct eligibility logic | TBD |
| ST-03 | Reward accrual after stake | Rewards accumulate | TBD |
| ST-04 | Claim rewards | Rewards transferred to recipient | TBD |
| ST-05 | Initiate unbond | 14-day timer starts | TBD |
| ST-06 | Attempt withdraw before 14 days | REVERTS correctly | TBD |
| ST-07 | Withdraw after 14 days (real-time) | Funds released | 🔵 DEFERRED — requires 14-day wait |
| ST-08 | Accelerated unbond simulation | Simulated via time-warp on isolated test chain | TBD |

> **NOTE:** A complete real-time 14-day unbond cannot be performed within a
> single sprint. ST-07 must be deferred and completed on the live testnet.
> ST-08 provides an accelerated simulation using a fresh chain with warped time,
> clearly labeled as simulation.

---

## 10. GOVERNANCE BATTLE TEST

### 10.1 EmergencyMultisig: 3-of-5

```bash
# Emergency pause (requires 3 signers)
cast send $EMERGENCY_MULTISIG "pause()" --from $SIGNER_1
cast send $EMERGENCY_MULTISIG "confirmPause(bytes32)" $TX_HASH --from $SIGNER_2
cast send $EMERGENCY_MULTISIG "confirmPause(bytes32)" $TX_HASH --from $SIGNER_3
```

### 10.2 Timelock: 48 hours

```bash
# Timelocked action
cast send $TIMELOCK "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  $TARGET 0 $CALLDATA 0x0 0x0 172800  # 172800 = 48h in seconds
# Wait 48h
cast send $TIMELOCK "execute(address,uint256,bytes,bytes32,bytes32)" ...
```

### 10.3 Test Matrix

| Test | Scenario | Expected | Actual |
|---|---|---|---|
| GOV-01 | Emergency pause with 3 signers | All contracts paused | TBD |
| GOV-02 | Emergency unpause | Contracts resume | TBD |
| GOV-03 | Pause with only 2 signers | REVERTS — insufficient approvals | TBD |
| GOV-04 | Unauthorized signer | REVERTS — not multisig member | TBD |
| GOV-05 | Timelocked action (48h) | Executes only after 48h | TBD |
| GOV-06 | Execute before 48h | REVERTS — too early | TBD |
| GOV-07 | Replay attempt | REVERTS — operation already executed | TBD |
| GOV-08 | Cancel pending action | Cancelled; no execution | TBD |
| GOV-09 | Governance exceeds authorized powers | Bounded by contract — REVERTS | TBD |

---

## 11. VALIDATOR CHURN

### 11.1 Test Sequence

```
Validator A: joins → operates → leaves
Validator B: joins mid-sequence → weight changes → remains
```

### 11.2 Test Matrix

| Test | Scenario | Expected | Actual |
|---|---|---|---|
| VC-01 | New validator joins | Registry entry created; fee weight set | TBD |
| VC-02 | Validator leaves | Weight set to 0; historical fees frozen | TBD |
| VC-03 | Weight increase | New distribution starts from weight-change block | TBD |
| VC-04 | Weight decrease | Same — prospective only | TBD |
| VC-05 | Validator becomes inactive | No retroactive reward accrual | TBD |
| VC-06 | Inactive validator returns | Accrual resumes; no gap retroactively filled | TBD |
| VC-07 | Historical fee conservation | sum(all payouts) <= sum(all fees collected) | TBD |
| VC-08 | No reward leakage | No validator receives another's allocation | TBD |
| VC-09 | No duplicate accounting | Single charge per fee event | TBD |
| VC-10 | PWCScan reflects churn | Explorer shows correct validator history | TBD |

---

## 12. PUBLIC USER FLOW

Perform as an external user with no privileged access:

| Step | Action | Expected | Actual |
|---|---|---|---|
| PUF-01 | Discover testnet (PWCScan or docs) | Page loads; "🧪 Testnet" badge visible; Chain ID 77 | TBD |
| PUF-02 | Add to MetaMask (Chain ID 77, native PW) | Network added successfully | TBD |
| PUF-03 | Receive testnet PW (faucet or transfer) | Balance appears in wallet | TBD |
| PUF-04 | Send PW to another address | Transaction confirmed | TBD |
| PUF-05 | View transaction in PWCScan | TX hash links to correct data; no mocked rows | TBD |
| PUF-06 | View sender address | Correct balance, nonce, history | TBD |
| PUF-07 | View block | Correct block time, txs, miner | TBD |
| PUF-08 | Interact with protocol (stake) | On-chain state updates | TBD |
| PUF-09 | Verify result in PWCScan | Explorer data matches on-chain state | TBD |

---

## 13. WALLET CONFIGURATION

Standard EVM wallet (MetaMask, Rabby, etc.) network settings:

| Field | Value |
|---|---|
| Network Name | PrimeWave Testnet |
| RPC URL | https://rpc.testnet.primewave.xyz (or equivalent) |
| Chain ID | **77** |
| Currency Symbol | PW |
| Block Explorer URL | https://explorer.testnet.primewave.xyz |

> **IMPORTANT:** Do NOT advertise mainnet network configuration. Testnet only.

---

## 14. TESTNET FAUCET POLICY

A dedicated faucet is NOT required for testnet launch. Testnet PW distribution:

| Method | Description |
|---|---|
| Direct transfer | Team distributes testnet PW from deployer allocation |
| Validator rewards | Validators earn testnet PW via normal protocol operation |
| Test wallets | Pre-funded test wallets distributed to testnet participants |

If a faucet is later implemented, it must enforce:
- Rate limiting (1 request / address / 24h)
- Daily global cap
- Testnet-only funds (no mainnet path)
- Abuse protection (CAPTCHA or Fuji AVAX proof-of-stake)

---

## 15. BATTLE TEST STATUS SUMMARY

| Section | Status | Blocker |
|---|---|---|
| Genesis ceremony | 🔵 PENDING | Ceremony addresses + Fuji AVAX |
| Fuji P-Chain deployment | 🔵 PENDING | Fuji infrastructure |
| Contract deployment | 🔵 PENDING | Live testnet RPC |
| ACP-99 validator flow | 🔵 PENDING | Real validators |
| ICM/Warp | 🔵 PENDING | Real P-Chain + relayer |
| Fee distribution | 🔵 PENDING | Live transactions |
| RewardVault | 🔵 PENDING | Live testnet |
| Staking (partial) | 🔵 PENDING | Live testnet |
| Staking (14-day) | 🔵 DEFERRED | Requires 14-day real-time |
| Governance | 🔵 PENDING | Live testnet |
| Validator churn | 🔵 PENDING | Real validators |
| Public user flow | 🔵 PENDING | Live testnet + PWCScan |
| In-Replit regression | ✅ PASS | N/A |
| Documentation | ✅ COMPLETE | N/A |
| Config consistency | ✅ VERIFIED | N/A |
