# PW-C08 Test Report

> Sprint: PW-C08 Protocol Integration + Production Configuration Hardening
> Date: 2026-08-14
> Test Files: IntegrationC08.t.sol, IntegrationC08Fuzz.t.sol
> Baseline: 391/391 from C07 GovernanceUnit.t.sol + GovernanceFuzz.t.sol

---

## 1. Test Summary

| Suite | File | Tests | Result |
|-------|------|-------|--------|
| C08 Integration Unit | IntegrationC08.t.sol | ~110 tests, 14 sections | PASS |
| C08 Stateful Invariants | IntegrationC08Fuzz.t.sol | 10 invariants + 8 fuzz units | PASS |
| C07 Governance Unit (regression) | GovernanceUnit.t.sol | 99 tests | PASS |
| C07 Governance Fuzz (regression) | GovernanceFuzz.t.sol | 10 invariants | PASS |
| C06 RewardVault Unit | RewardVaultUnit.t.sol | (from C06) | PASS |
| C05 Registry Unit | ValidatorRegistryUnit.t.sol | (from C05) | PASS |
| C04 DevTreasury | DevTreasuryUnit.t.sol | (from C04) | PASS |
| C03 FeeDistributor + VFV | FeeSplitUnit.t.sol | (from C03) | PASS |

**Total: 500+ tests across all suites. 0 failures. 0 regressions.**

---

## 2. C08 Integration Test Sections

### SECTION A: Architecture Reconciliation (11 tests)

Verifies that the deployed contract configuration matches the locked architecture specification.

| Test | What It Proves |
|------|---------------|
| test_ARCH_ems_threshold | EMS.THRESHOLD() == 3 (3-of-5, immutable) |
| test_ARCH_ems_signers_correct | All 5 signers registered, RANDO excluded |
| test_ARCH_timelock_minDelay | MIN_DELAY == 172_800 (48h, compile-time constant) |
| test_ARCH_timelock_proposer | Proposer == ADMIN at construction |
| test_ARCH_vfv_protocolAdmin | VFV.protocolAdmin() == ADMIN |
| test_ARCH_fd_split_constants | VALIDATOR_BPS==7000, TREASURY_BPS==2000, BASIS_POINTS==10000 |
| test_ARCH_fd_burn_address | BURN_ADDRESS == 0x000...dEaD |
| test_ARCH_rv_maxRate | MAX_RATE_PER_SECOND == 3M PW/year |
| test_ARCH_rv_maxAnnual | MAX_ANNUAL_EMISSION == 3_000_000 ether |
| test_ARCH_no_nativeMinter | No contract has mintNativeCoin() function |
| test_ARCH_nonUpgradeable | No proxy/delegatecall/upgradeTo on any contract |

### SECTION B: Fee Flow End-to-End (9 tests)

Verifies the complete fee split path including rounding, large amounts, and pause behavior.

| Test | What It Proves |
|------|---------------|
| test_FEE_basicDistribution_split | 70/20/10 split correct on 1 ETH |
| test_FEE_rounding_dust | 1001 wei: dust goes to burn, conservation holds |
| test_FEE_largeAmount | 1000 ETH: no overflow, split exact |
| test_FEE_accumulatesBeforeDistribute | Pending grows correctly |
| test_FEE_pausedDistributor_blocksDistribute | distribute() reverts when paused |
| test_FEE_pausedVault_blocksClaim | claimFees() reverts when VFV paused |
| test_FEE_pausedVault_feesStillAccrue | receive() not blocked by pause |
| test_FEE_conservation_multipleDistributions | validatorShare+treasuryShare+burnShare == total over 10 txns |
| test_FEE_burnAddressAccumulates | 0x000...dEaD balance grows monotonically |

### SECTION C: ValidatorRegistry <-> ValidatorFeeVault Integration (10 tests)

Verifies the registry adapter correctly bridges ACP-99 validator data to VFV fee accounting.

| Test | What It Proves |
|------|---------------|
| test_INTEG_registry_syncValidator_activates | Registry.registerValidator -> VFV active |
| test_INTEG_registry_claimFees_e2e | Register via registry, receive fees, claim |
| test_INTEG_registry_deactivate_stopsAccrual | syncValidator after Completed -> VFV inactive |
| test_INTEG_registry_rewardRecipientUpdate | registry.setRewardRecipient -> VFV updated |
| test_INTEG_registry_nonAdmin_cannotRegister | RANDO cannot call registerValidator |
| test_INTEG_registry_nonAdmin_cannotDeactivate | RANDO cannot call setRewardRecipient |
| test_INTEG_registry_managedCount | Count increments correctly |
| test_INTEG_registry_validatorManagerIsSourceOfTruth | validatorWeight reads from MockVM, not internal state |
| test_INTEG_registry_cannotBypassVMForRegistration | Unregistered validator rejected by VM check |
| test_INTEG_twoValidators_weightedClaim | 3:1 weight -> proportional fee split |

### SECTION D: RewardVault Separation (5 tests)

Verifies RewardVault is completely isolated from the fee flow path.

| Test | What It Proves |
|------|---------------|
| test_RV_noDirectConnectionToFD | dist.validatorFeeVault() != RV address |
| test_RV_noDirectConnectionToVFV | VFV.receive() does not affect RV |
| test_RV_emitThenClaim | Emission accrues by time; claim transfers correctly |
| test_RV_setEmissionRate_cannotIncrease | setEmissionRate(higher) reverts |
| test_RV_fundingIsAdditive | Multiple fund() calls accumulate totalFunded |

### SECTION E: Supply Conservation (5 tests)

Verifies 100M PW fixed supply properties and burn monotonicity.

| Test | What It Proves |
|------|---------------|
| test_SUPPLY_burnNeverDecreases | 0x000...dEaD balance is monotone-increasing |
| test_SUPPLY_rvSolvency | totalEmitted <= totalFunded always |
| test_SUPPLY_rvClaimBound | totalClaimed <= totalEmitted always |
| test_SUPPLY_rvNoMintPath | RV.fund() only moves existing PW, no creation |
| test_SUPPLY_fdConservation | validatorShare+treasury+burn == totalDistributed |

### SECTION F: Authority Isolation (9 tests)

Verifies cross-authority domain isolation — EMS cannot do TL things, TL cannot do EMS things, etc.

| Test | What It Proves |
|------|---------------|
| test_AUTH_ems_cannotCallRegisterValidator | EMS cannot register a validator (not protocolAdmin) |
| test_AUTH_ems_cannotSetEmissionRate | EMS cannot change emission (not RV admin) |
| test_AUTH_ems_cannotCallSetRewardRecipient | EMS cannot change recipient |
| test_AUTH_tl_cannotCallPause | Timelock is not pauseController, pause reverts |
| test_AUTH_tl_cannotCallPauseOnRV | Same for RewardVault |
| test_AUTH_onlyAdmin_vfv | Non-protocolAdmin cannot registerValidator on VFV |
| test_AUTH_onlyAdmin_rv | Non-admin cannot setEmissionRate on RV |
| test_AUTH_onlyPauseController_fd | Non-EMS cannot pause FD |
| test_AUTH_crossContract_noSharedState | VFV and RV share no ETH paths |

### SECTION G: Zero-Address Audit (8 tests)

Verifies that all constructors have correct zero-address guards.

| Test | What It Proves |
|------|---------------|
| test_ZEROADDR_fd_vault | FD reverts on zero vault address |
| test_ZEROADDR_fd_treasury | FD reverts on zero treasury address |
| test_ZEROADDR_fd_pauseController_allowed | FD allows zero pauseController (disables pause) |
| test_ZEROADDR_vfv_admin | VFV reverts on zero protocolAdmin |
| test_ZEROADDR_rv_admin | RV reverts on zero admin |
| test_ZEROADDR_ems_signer | EMS reverts on zero signer |
| test_ZEROADDR_tl_proposer | TL reverts on zero proposer |
| test_ZEROADDR_treasury_distributor | DevTreasury reverts on zero distributor |

### SECTION H: Initialization Security (6 tests)

Verifies constructors execute atomically with no re-entrancy or front-running window.

| Test | What It Proves |
|------|---------------|
| test_INIT_fd_immutableDestinations | validatorFeeVault/treasury/burn cannot change post-deploy |
| test_INIT_vfv_immutableAdmin | protocolAdmin cannot change post-deploy |
| test_INIT_rv_immutableAdmin | admin cannot change post-deploy |
| test_INIT_ems_immutableSigners | EMS signers immutable (isSigner cannot change) |
| test_INIT_tl_minDelay_immutable | MIN_DELAY cannot change |
| test_INIT_noReinitialize | No initialize() function exists on any contract |

### SECTION I: NativeMinter Audit (4 tests)

Verifies the NativeMinter precompile interface is absent from the entire codebase.

| Test | What It Proves |
|------|---------------|
| test_NM_fd_noMintInterface | FD has no mintNativeCoin() selector |
| test_NM_vfv_noMintInterface | VFV has no mintNativeCoin() selector |
| test_NM_rv_noMintInterface | RV has no mintNativeCoin() selector |
| test_NM_noContractHasMintSelector | All 6 contracts have no 0x4abfb40b selector |

### SECTION J: Pause Architecture (7 tests)

Verifies pause independence, recovery, and EMS authority scope.

| Test | What It Proves |
|------|---------------|
| test_PAUSE_fd_emsCanPause | EMS can pause FD |
| test_PAUSE_vfv_emsCanPause | EMS can pause VFV |
| test_PAUSE_rv_emsCanPause | EMS can pause RV |
| test_PAUSE_independentContracts | Pausing VFV does not affect FD or RV |
| test_PAUSE_recoveryAfterUnpause | Fees fully claimable after unpause |
| test_PAUSE_nativeMinterNotPausable | No mint path to pause |
| test_PAUSE_emsCannotCallNonPause | EMS.execute() with non-pause data reverts |

### SECTION K: Timelock Integration (10 tests)

Verifies the 48h timelock operates correctly as governance for protocol admin functions.

| Test | What It Proves |
|------|---------------|
| test_TL_schedule_setEmissionRate | schedule() works for setEmissionRate |
| test_TL_execute_afterDelay | execute() succeeds at exactly MIN_DELAY |
| test_TL_execute_beforeDelay_reverts | execute() reverts 1 second short of delay |
| test_TL_cancelledOp_cannotExecute | Cancelled operation reverts on execute |
| test_TL_replayProtection | Executed operation cannot be re-executed |
| test_TL_nonProposer_cannotSchedule | Only proposer can schedule |
| test_TL_anyoneCanExecute | Anyone can call execute() after delay |
| test_TL_predecessorChain | Op B waits for Op A |
| test_TL_vaultWeightChange_e2e | Full e2e: schedule -> 48h -> execute -> weight changed |
| test_TL_pauseImpossible | Timelock cannot bypass EMS for pause |

### SECTION L: Economic Conservation (9 tests)

Verifies protocol-wide economic invariants under multi-event scenarios.

| Test | What It Proves |
|------|---------------|
| test_ECON_feesNeverLost | Every wei distributed is accounted: vault+treasury+burn == sent |
| test_ECON_rvEmissionMonotoneIncreasing | accRewardPerWeight never decreases |
| test_ECON_rvRateCanOnlyDecrease | setEmissionRate enforces monotone-decreasing |
| test_ECON_burnAddressNeverReceivesRV | RV claim never touches burn address |
| test_ECON_vaultBalanceEqualsAccounting | vaultBalance == totalReceived - totalClaimed |
| test_ECON_rvBalanceEqualsAccounting | vault.balance >= accountedBalance |
| test_ECON_multiDistributorSplit | 100 distributions: all conservation properties hold |
| test_ECON_uptimeBipsEffect | effectiveWeight changes proportionally to uptime |
| test_ECON_zeroWeightValidator | Zero weight validator gets no fees |

### SECTION M: Failure and Recovery (6 tests)

Verifies graceful failure modes and recovery paths.

| Test | What It Proves |
|------|---------------|
| test_RECOVER_pauseThenUnpause_feesIntact | Fees accrued during pause are fully claimable |
| test_RECOVER_rvPauseDoesntLoseEmission | Emission continues during pause; claim after unpause works |
| test_RECOVER_deactivateReactivate | Deactivated validator can be re-activated; fees stop and resume |
| test_RECOVER_cancelledEMSProposal_noExecution | Cancelled EMS proposal cannot be executed |
| test_RECOVER_unauthorizedWithdrawal_reverts | Direct ETH withdrawal attempt reverts |
| test_RECOVER_distributeAfterPauseEnds | First distribute() after FD unpause works correctly |

### SECTION N: Gas Measurements (6 tests)

Documents gas costs for key protocol operations (benchmarks, not assertions).

| Test | What It Measures |
|------|-----------------|
| test_GAS_distribute | Gas for FeeDistributor.distribute() |
| test_GAS_claimFees_singleValidator | Gas for ValidatorFeeVault.claimFees() |
| test_GAS_claimFees_15validators | Gas for distribute() + all 15 claims |
| test_GAS_emsPropose | Gas for EMS.propose() |
| test_GAS_emsApprove | Gas for EMS.approve() |
| test_GAS_timelockSchedule | Gas for PrimeWaveTimelock.schedule() |

---

## 3. C08 Fuzz Test Suite

### Stateful Invariants (C08Handler + IntegrationC08StatefulInvariant)

The `C08Handler` is a stateful fuzzing harness with the following callable actions:
- `sendFees(uint256 amount)` — sends 1 wei to 100 ETH, distributes
- `claimVaultFees(uint256 validatorIdx)` — claims VFV fees for one of 3 validators
- `fundRV(uint256 amount)` — funds RewardVault
- `claimRVReward(uint256 recipientIdx)` — claims RV reward for one of 2 recipients  
- `pauseVault()` — EMS pauses VFV
- `unpauseVault()` — EMS unpauses VFV
- `pauseRV()` — EMS pauses RV
- `unpauseRV()` — EMS unpauses RV
- `advanceTime(uint256 secs)` — warps time 0-1 year
- `setEmissionRate(uint256 rate)` — reduces emission rate

| Invariant | Property |
|-----------|---------|
| INV-1 | FD fee conservation: validator + treasury + burn == total distributed |
| INV-2 | VFV conservation: totalReceived >= totalClaimed always |
| INV-3 | RV solvency: totalEmitted <= totalFunded always |
| INV-4 | RV claim bound: totalClaimed <= totalEmitted always |
| INV-5 | EMS nonce strictly monotone-increasing |
| INV-6 | Pause authority: only EMS (pauseController) can pause |
| INV-7 | Emission rate cap: emissionRatePerSecond <= MAX_RATE_PER_SECOND always |
| INV-8 | RV balance: vault.balance >= accountedBalance always |
| INV-9 | FD split constants immutable: VALIDATOR_BPS + TREASURY_BPS <= BASIS_POINTS |
| INV-10 | No cross-contamination: dist.validatorFeeVault != RV address |

### Standalone Fuzz Units (IntegrationC08FuzzUnit)

| Test | Property |
|------|---------|
| test_FUZZ_feeConservation | For any amount: validatorShare + treasury + burn == amount |
| test_FUZZ_splitRatioBounds | validatorShare always in [69%, 71%] of amount |
| test_FUZZ_burnNeverZero | For amount > 9: burn share > 0 |
| test_FUZZ_rvEmission_timeBounded | For any elapsed time: emitted increase bounded by rate * time |
| test_FUZZ_rvSolvencyAfterFunding | After any fund amount: accountedBalance >= 0 |
| test_FUZZ_emsNonceMonotone | After any sequence: nonce never decreases |
| test_FUZZ_timelockDelayEnforced | execute() before MIN_DELAY always reverts |
| test_FUZZ_distributorSplit_multiRound | After N rounds: sum of all shares == totalDistributed |

---

## 4. Regression Results

### C07 GovernanceUnit.t.sol (99 tests)

All 99 tests pass after C08 changes. No regressions.

The following tests had previously been fixed in C07 and remain correct:
- `test_GOV_fund_permissionless_anyEOA` — correct: no vm.prank required for fund()
- `test_GOV_feeDistributor_split_invariant` — correct: uses dist.totalValidatorShare() not vault balance
- `test_GOV_timelock_predecessorChain` — correct: op2 uses timelocked admin action, not pause()

### C07 GovernanceFuzz.t.sol (10 invariants)

All 10 stateful invariants pass. INV-2 nonce tracking correctly updated in all EMS handler functions.

---

## 5. Test Design Decisions

### Why 3 validators in the fuzz handler (not 15)?
The 15-validator Phase-1 configuration would require 15 mockVM registrations in setUp, making fuzz traces very long. 3 validators is sufficient to expose weight distribution bugs, accrual errors, and conservation violations.

### Why test `deactivateValidator` via `syncValidator`?
The `PrimeWaveValidatorRegistry` exposes deactivation via the permissionless `syncValidator()` (which reads from ValidatorManager and calls `feeVault.deactivateValidator()` internally). There is no direct admin `deactivateValidator()` on the registry — deactivation authority flows from the ValidatorManager's ACP-99 consensus.

### Why SECTION N uses console.log for gas rather than assertLt?
Gas costs vary by EVM implementation, optimization flags, and Foundry version. Asserting a hard gas ceiling would create false failures on different environments. Gas measurements are documented as benchmarks.

### Why is the NativeMinter test done via selector matching, not interface?
The test cannot `import` an interface that doesn't exist in the codebase (that would create the very thing being tested). Instead, the 4-byte selector for `mintNativeCoin(address,uint256)` (0x4abfb40b) is hardcoded and checked against each deployed contract's bytecode response.

---

## 6. Known Test Gaps (Phase 2 Backlog)

1. **PrimeWaveStakingManager integration** — not yet deployed; RewardVault recipient tests use raw EOAs
2. **Live ACP-99 ValidatorManager** — tests use MockValidatorManager; real Warp message verification not tested on-chain
3. **Multi-node consensus tests** — require real L1 node cluster; not feasible in Foundry
4. **Cross-chain security** — Warp message spoofing out of scope (AvalancheGo security domain)
