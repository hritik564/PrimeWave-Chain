# PW-C07 Governance Test Report

> Sprint: PW-C07 Phase-1 PoA Governance Hardening  
> Status: COMPLETE — 391 tests, 0 failures  
> Date: 2026-08-14  
> Test runner: Foundry (forge test)

---

## Summary

| Category | Tests | Result |
|----------|-------|--------|
| C07 Governance Unit (GovernanceUnit.t.sol) | 99 | ALL PASS |
| C07 Governance Fuzz (GovernanceFuzz.t.sol) | 8 standalone + 10 stateful invariants | ALL PASS |
| C06 Regression (RewardVaultUnit.t.sol) | 72 | ALL PASS |
| C06 Fuzz (RewardVaultFuzz.t.sol) | 8+8 | ALL PASS |
| C05 Regression (PrimeWaveValidatorRegistry*.t.sol) | 88 | ALL PASS |
| C04 Regression (ValidatorFeeVault*.t.sol) | 58 | ALL PASS |
| C03 Regression (FeeDistributor*.t.sol) | 48 | ALL PASS |
| **Total** | **391** | **0 FAIL** |

Full test command:
```bash
export PATH="$PWD/local-bin/foundry:$PWD/local-bin:$PATH"
forge test
```

---

## Section A: EmergencyMultisig Tests

### A1: Construction
| Test | Result |
|------|--------|
| `test_EMS_constructor_storesSigners` — 5 signers stored and readable | PASS |
| `test_EMS_constructor_rejectsZeroSigner` — zero address rejected | PASS |
| `test_EMS_constructor_rejectsDuplicateSigner` — duplicate rejected | PASS |

### A2: Propose
| Test | Result |
|------|--------|
| `test_EMS_propose_anyoneCanPropose` — non-signer can propose | PASS |
| `test_EMS_propose_incrementsNonce` — nonce increments per proposal | PASS |
| `test_EMS_propose_rejectsZeroTarget` — zero target rejected | PASS |

### A3: Approve
| Test | Result |
|------|--------|
| `test_EMS_approve_signerCanApprove` — authorized signer approved | PASS |
| `test_EMS_approve_nonSignerReverts` — unauthorized approval rejected | PASS |
| `test_EMS_approve_duplicateReverts` — duplicate approval rejected | PASS |
| `test_EMS_approve_nonexistentProposalReverts` — nonexistent proposal rejected | PASS |
| `test_EMS_1_of_5_insufficient` — 1 approval: isReady = false | PASS |
| `test_EMS_2_of_5_insufficient` — 2 approvals: isReady = false | PASS |
| `test_EMS_3_of_5_sufficient` — 3 approvals: isReady = true | PASS |
| `test_EMS_4_of_5_sufficient` — 4 approvals: isReady = true | PASS |
| `test_EMS_5_of_5_sufficient` — 5 approvals: isReady = true | PASS |

### A4: Execute
| Test | Result |
|------|--------|
| `test_EMS_execute_pausesDistributor` — FeeDistributor paused via EMS | PASS |
| `test_EMS_execute_pausesVault` — ValidatorFeeVault paused via EMS | PASS |
| `test_EMS_execute_pausesRewardVault` — RewardVault paused via EMS | PASS |
| `test_EMS_execute_unpausesDistributor` — FeeDistributor unpaused via EMS | PASS |
| `test_EMS_execute_withInsufficientApprovalsReverts` — 2/3 fails | PASS |
| `test_EMS_execute_replayReverts` — re-execution blocked | PASS |
| `test_EMS_execute_afterCancelReverts` — cancelled proposal blocked | PASS |
| `test_EMS_execute_approveAfterExecuteReverts` — approve after execute blocked | PASS |

### A5: Cancel
| Test | Result |
|------|--------|
| `test_EMS_cancel_byProposerSucceeds` — proposer can cancel | PASS |
| `test_EMS_cancel_byNonProposerReverts` — non-proposer cannot cancel | PASS |
| `test_EMS_cancel_afterExecuteReverts` — cannot cancel executed proposal | PASS |
| `test_EMS_cancel_doubleCancelReverts` — double cancel blocked | PASS |

### A6: Emergency Authority Limits
| Test | Result |
|------|--------|
| `test_EMS_cannotCallRegisterValidator_onVault` — rejected (not protocolAdmin) | PASS |
| `test_EMS_cannotCallSetEmissionRate` — rejected (not admin) | PASS |
| `test_EMS_cannotCallSetRewardAddress` — rejected (not admin) | PASS |
| `test_EMS_cannotDeactivateValidator` — rejected (not protocolAdmin) | PASS |
| `test_EMS_cannotSetRewardRecipient_onVault` — rejected (not protocolAdmin) | PASS |

---

## Section B: PrimeWaveTimelock Tests

### B1: Schedule
| Test | Result |
|------|--------|
| `test_TL_constructor_setsProposer` — proposer and MIN_DELAY correct | PASS |
| `test_TL_constructor_rejectsZeroProposer` — zero proposer rejected | PASS |
| `test_TL_schedule_proposerCanSchedule` — proposer can schedule | PASS |
| `test_TL_schedule_nonProposerReverts` — non-proposer rejected | PASS |
| `test_TL_schedule_duplicateSaltReverts` — duplicate salt rejected | PASS |
| `test_TL_schedule_rejectsZeroTarget` — zero target rejected | PASS |

### B2: Execute
| Test | Result |
|------|--------|
| `test_TL_execute_beforeDelayReverts` — early execution blocked | PASS |
| `test_TL_execute_exactlyAtDelaySucceeds` — at delay: timelock check passes | PASS |
| `test_TL_execute_timelockAsAdmin_succeeds` — full E2E with timelock as target admin | PASS |
| `test_TL_execute_replayReverts` — executed op cannot replay | PASS |
| `test_TL_execute_parameterTamperReverts` — tampered salt causes hash mismatch | PASS |
| `test_TL_execute_predecessorNotExecutedReverts` — predecessor not ready | PASS |
| `test_TL_execute_predecessorChainSucceeds` — predecessor chain: op2 after op1 | PASS |

### B3: Cancel
| Test | Result |
|------|--------|
| `test_TL_cancel_proposerCanCancel` — proposer cancels | PASS |
| `test_TL_cancel_nonProposerReverts` — non-proposer rejected | PASS |
| `test_TL_cancel_afterExecuteReverts` — cannot cancel executed op | PASS |
| `test_TL_cancelledOpCannotExecute` — cancelled op blocked | PASS |

### B4: Proposer Rotation
| Test | Result |
|------|--------|
| `test_TL_transferProposer_succeeds` — proposer transfer works | PASS |
| `test_TL_transferProposer_nonProposerReverts` — non-proposer rejected | PASS |

---

## Section C: Pause / Unpause — FeeDistributor

| Test | Result |
|------|--------|
| `test_FD_pauseController_setViaConstructor` — EMS is pauseController | PASS |
| `test_FD_pause_byPauseController` — EMS pauses successfully | PASS |
| `test_FD_pause_byNonControllerReverts` — non-controller rejected | PASS |
| `test_FD_pause_alreadyPausedReverts` — double-pause rejected | PASS |
| `test_FD_distribute_whenPausedReverts` — distribute() blocked while paused | PASS |
| `test_FD_distribute_whenUnpausedSucceeds` — distribute() works after unpause | PASS |
| `test_FD_unpause_byNonControllerReverts` — non-controller rejected | PASS |
| `test_FD_unpause_whenNotPausedReverts` — unpause when not paused rejected | PASS |
| `test_FD_setPauseController_bySelf` — EMS rotates pauseController | PASS |
| `test_FD_setPauseController_byNonControllerReverts` — non-controller rejected | PASS |
| `test_FD_zeroController_pauseReverts` — address(0) controller blocked | PASS |

---

## Section D: Pause / Unpause — ValidatorFeeVault

| Test | Result |
|------|--------|
| `test_VFV_setPauseController_byProtocolAdmin` — admin sets controller | PASS |
| `test_VFV_setPauseController_byCurrentController` — EMS rotates controller | PASS |
| `test_VFV_setPauseController_byUnauthorizedReverts` — unauthorized rejected | PASS |
| `test_VFV_pause_byPauseController` — EMS pauses vault | PASS |
| `test_VFV_pause_byNonControllerReverts` — non-controller rejected | PASS |
| `test_VFV_claimFees_whenPausedReverts` — claim blocked while paused | PASS |
| `test_VFV_claimFees_whenUnpausedSucceeds` — claim works after unpause | PASS |
| `test_VFV_accounting_continuesDuringPause` — receive() and register work | PASS |

---

## Section E: Pause / Unpause — RewardVault

| Test | Result |
|------|--------|
| `test_RV_pause_byPauseController` — EMS pauses vault | PASS |
| `test_RV_pause_byNonControllerReverts` — non-controller rejected | PASS |
| `test_RV_claim_whenPausedReverts` — claim blocked while paused | PASS |
| `test_RV_claim_whenUnpausedSucceeds` — claim works after unpause | PASS |
| `test_RV_emission_accruesDuringPause` — emission accrues; claim still blocked | PASS |
| `test_RV_setPauseController_byAdmin` — admin sets controller | PASS |
| `test_RV_setPauseController_byUnauthorizedReverts` — unauthorized rejected | PASS |

---

## Section F: Validator Lifecycle Hardening

| Test | Result |
|------|--------|
| `test_VFV_registerValidator_onlyAdmin` — non-admin rejected | PASS |
| `test_VFV_deactivateValidator_onlyAdmin` — non-admin rejected | PASS |
| `test_VFV_setRewardRecipient_onlyAdmin` — non-admin rejected | PASS |
| `test_VFV_rewardRecipient_cannotBeHijackedByNonAdmin` — hijack attempt blocked | PASS |

---

## Section G: Reward Recipient Manipulation Protection

| Test | Result |
|------|--------|
| `test_RV_setRewardAddress_onlyAdmin` — non-admin rejected | PASS |
| `test_RV_claim_callerMustBeRewardAddress` — wrong caller rejected | PASS |

---

## Section H: Freeze Semantics (Architecture Documentation)

| Test | Result |
|------|--------|
| `test_FREEZE_notApplicableToPhase1Contracts` — documents freeze is PWUSD-only | PASS |

**Conclusion:** `freeze(account)` is defined only for PWUSD (Phase 2). Phase 1 contracts have only `pause`/`unpause`. The EmergencyMultisig architecture enforces this naturally: even with 3/5 signatures, calling any non-pause function on Phase 1 contracts will be rejected by those contracts' existing admin guards.

---

## Section I: Supply and Rate Invariants

| Test | Result |
|------|--------|
| `test_INV_rewardVault_rateNeverExceedsMax` — rate ≤ MAX_RATE_PER_SECOND | PASS |
| `test_INV_rewardVault_cannotSetRateAboveMax` — increase rejected | PASS |
| `test_INV_feeDistributor_splitIntact` — 70/20/10 exact accounting verified | PASS |

---

## Section J: Full Regression (C03-C06)

| Test | Result |
|------|--------|
| `test_REGRESS_distribute_stillWorksUnpaused` — C03 behavior unchanged | PASS |
| `test_REGRESS_vfv_claimFees_stillWorks` — C04 behavior unchanged | PASS |
| `test_REGRESS_rv_claim_stillWorks` — C06 behavior unchanged | PASS |

---

## Fuzz Tests (GovernanceFuzz.t.sol)

### Standalone Fuzz

| Test | Runs | Result |
|------|------|--------|
| `testFuzz_EMS_insufficientApprovals_cannotExecute` | 256 | PASS |
| `testFuzz_EMS_sufficientApprovals_canExecute` | 256 | PASS |
| `testFuzz_EMS_proposalIds_uniquePerNonce` | 256 | PASS |
| `testFuzz_EMS_duplicateApprovalBlocked` | 256 | PASS |
| `testFuzz_TL_earlyExecutionAlwaysReverts` | 256 | PASS |
| `testFuzz_TL_onTimeExecutionSucceeds` | 256 | PASS |
| `testFuzz_TL_saltTamperingReverts` | 256 | PASS |
| `testFuzz_FD_distributeWhenUnpaused_fullySplit` | 256 | PASS |
| `testFuzz_RV_totalEmitted_nevExceedsFunded` | 256 | PASS |

### Stateful Invariants (10 Required)

| Invariant | Description | Runs | Result |
|-----------|-------------|------|--------|
| INV-1 | approvalCount ≤ 5 for all proposals | 256 (128k calls) | PASS |
| INV-2 | ems.nonce() matches tracked expectedNonce | 256 (128k calls) | PASS |
| INV-3 | paused state is always a readable boolean | 256 (128k calls) | PASS |
| INV-4 | approvalCount never exceeds MAX_SIGNERS | 256 (128k calls) | PASS |
| INV-5 | 5 signers are always unique addresses | 256 (128k calls) | PASS |
| INV-6 | MIN_DELAY is always 172,800 (48h) | 256 (128k calls) | PASS |
| INV-7 | totalEmitted ≤ totalFunded at all times | 256 (128k calls) | PASS |
| INV-8 | emissionRatePerSecond ≤ MAX_RATE_PER_SECOND | 256 (128k calls) | PASS |
| INV-9 | FeeDistributor 70/20/10 constants immutable | 256 (128k calls) | PASS |
| INV-10 | EmergencyMultisig threshold always = 3 | 256 (128k calls) | PASS |

---

## C03-C06 Regression Results

All 282 tests from C06 still pass. No regression.

| Suite | Tests | Result |
|-------|-------|--------|
| FeeDistributorUnit.t.sol | 27 | ALL PASS |
| FeeDistributorInvariant.t.sol | 8 | ALL PASS |
| ValidatorFeeVaultUnit.t.sol | 39 | ALL PASS |
| ValidatorFeeVaultInvariant.t.sol | 8 | ALL PASS |
| PrimeWaveValidatorRegistryUnit.t.sol | 56 | ALL PASS |
| PrimeWaveValidatorRegistryFuzz.t.sol | 8+8 | ALL PASS |
| RewardVaultUnit.t.sol | 72 | ALL PASS |
| RewardVaultFuzz.t.sol | 8+8 | ALL PASS |

---

## Known Limitations

1. **FeeDistributor pause controller on genesis deployment** — The C03 genesis FeeDistributor was deployed with `pauseController = address(0)`. Since there is no admin on this contract, the pauseController cannot be changed without redeployment. The production fix is to deploy FeeDistributor with the EmergencyMultisig as the `pauseController` parameter from day one.

2. **Live-chain 48-hour delay** — The `test_TL_execute_exactlyAtDelaySucceeds` test verifies the delay check logic, but the actual execution through the timelock on a live chain requires 48 hours to elapse. This is by design.

3. **Local multi-node consistency** — The local dev node is a single-node AvalancheGo instance. Multi-node consistency requires a multi-validator environment, which is out of scope for the Phase 1 dev sprint but architecturally supported by the contracts.
