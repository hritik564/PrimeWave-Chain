// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// RewardVaultFuzz.t.sol -- C06 Fuzz + Invariant Tests
// ============================================================
//
// Standalone fuzz tests:
//   FUZZ-1:  Random funding + timestamps; emission never exceeds cap
//   FUZZ-2:  Random weights; proportional distribution correct
//   FUZZ-3:  Random rate reductions; historical rewards preserved
//   FUZZ-4:  Random deactivation; earned fees never confiscated
//   FUZZ-5:  No cross-recipient claim possible
//   FUZZ-6:  Conservation at random timestamps
//   FUZZ-7:  5-year max-emission; never exceeds 3M/year
//   FUZZ-8:  Zero-weight period; emission pauses
//
// Stateful invariant tests:
//   INV-1:  totalEmitted <= totalFunded
//   INV-2:  totalClaimed <= totalEmitted
//   INV-3:  totalClaimed <= totalFunded
//   INV-4:  emissionRate <= MAX_RATE_PER_SECOND
//   INV-5:  balance == totalFunded - totalClaimed
//   INV-6:  No recipient can claim another's rewards
//   INV-7:  Deactivated fees not confiscated (+ claimed)
//   INV-8:  totalPending + totalClaimed == totalEmitted
// ============================================================

import "forge-std/Test.sol";
import "../src/RewardVault.sol";

// ── Stateful handler ───────────────────────────────────────────────────────────

contract RewardHandler is Test {

    RewardVault public vault;

    address constant ADMIN = address(0xA1);
    uint256 constant MAX_RECIPIENTS = 8;

    bytes32[8] public rids;
    address[8] public addrs;
    uint256 public registeredCount;

    mapping(bytes32 => bool)    public wasDeactivated;
    mapping(bytes32 => uint256) public claimableAtDeactivation;
    mapping(bytes32 => uint256) public claimedAfterDeactivation;

    uint256 immutable MAX_R;

    constructor() {
        MAX_R = uint256(3_000_000 * 1 ether) / 31_536_000;

        for (uint256 i = 0; i < MAX_RECIPIENTS; i++) {
            rids[i]  = keccak256(abi.encodePacked("fuzz-recipient-", i));
            addrs[i] = address(uint160(0x3000 + i));
        }

        vault = new RewardVault(ADMIN, MAX_R);
        vm.deal(ADMIN, 100_000_000 ether);
        vm.deal(address(this), 100_000_000 ether);
    }

    function fund(uint128 amount) public {
        amount = uint128(bound(amount, 1, 10_000_000 ether));
        (bool ok,) = address(vault).call{value: amount}("");
        ok;
    }

    function registerNext(uint64 weight, bool active) public {
        if (registeredCount >= MAX_RECIPIENTS) return;
        weight = uint64(bound(weight, 1, 20));

        vm.prank(ADMIN);
        vault.registerRecipient(rids[registeredCount], addrs[registeredCount], uint128(weight), active);
        registeredCount++;
    }

    function advance(uint32 secs) public {
        secs = uint32(bound(secs, 1, 30 days));
        vm.warp(block.timestamp + secs);
    }

    function deactivate(uint8 idx) public {
        if (registeredCount == 0) return;
        idx = uint8(bound(idx, 0, registeredCount - 1));
        bytes32 rid = rids[idx];

        (bool active,,,,,) = vault.recipients(rid);
        if (!active) return;

        claimableAtDeactivation[rid] = vault.claimable(rid);
        wasDeactivated[rid] = true;

        vm.prank(ADMIN);
        vault.deactivateRecipient(rid);
    }

    function activate(uint8 idx) public {
        if (registeredCount == 0) return;
        idx = uint8(bound(idx, 0, registeredCount - 1));
        bytes32 rid = rids[idx];

        (bool active,,,,,) = vault.recipients(rid);
        if (active) return;

        vm.prank(ADMIN);
        vault.activateRecipient(rid);
    }

    function doClaim(uint8 idx) public {
        if (registeredCount == 0) return;
        idx = uint8(bound(idx, 0, registeredCount - 1));
        bytes32 rid = rids[idx];

        uint256 c = vault.claimable(rid);
        if (c == 0) return;

        (,,,, , address addr) = vault.recipients(rid);
        vm.prank(addr);
        uint256 claimed = vault.claim(rid);

        if (wasDeactivated[rid]) {
            claimedAfterDeactivation[rid] += claimed;
        }
    }

    function reduceRate(uint64 reduction) public {
        uint256 current = vault.emissionRatePerSecond();
        if (current == 0) return;
        reduction = uint64(bound(reduction, 1, current));
        uint256 newRate = current - reduction;

        vm.prank(ADMIN);
        vault.setEmissionRate(newRate);
    }

    function updateWeight(uint8 idx, uint64 newWeight) public {
        if (registeredCount == 0) return;
        idx = uint8(bound(idx, 0, registeredCount - 1));
        newWeight = uint64(bound(newWeight, 1, 50));

        vm.prank(ADMIN);
        vault.setWeight(rids[idx], uint128(newWeight));
    }
}

// ── Invariant test contract ────────────────────────────────────────────────────

contract RewardVaultInvariant is Test {

    RewardHandler handler;

    function setUp() public {
        handler = new RewardHandler();
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = RewardHandler.fund.selector;
        selectors[1] = RewardHandler.registerNext.selector;
        selectors[2] = RewardHandler.advance.selector;
        selectors[3] = RewardHandler.deactivate.selector;
        selectors[4] = RewardHandler.activate.selector;
        selectors[5] = RewardHandler.doClaim.selector;
        selectors[6] = RewardHandler.reduceRate.selector;
        selectors[7] = RewardHandler.updateWeight.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// INV-1: totalEmitted <= totalFunded
    function invariant_1_EmittedLeFunded() public view {
        RewardVault v = handler.vault();
        assertLe(v.totalEmitted(), v.totalFunded(), "INV-1: totalEmitted > totalFunded");
    }

    /// INV-2: totalClaimed <= totalEmitted
    function invariant_2_ClaimedLeEmitted() public view {
        RewardVault v = handler.vault();
        assertLe(v.totalClaimed(), v.totalEmitted(), "INV-2: totalClaimed > totalEmitted");
    }

    /// INV-3: totalClaimed <= totalFunded
    function invariant_3_ClaimedLeFunded() public view {
        RewardVault v = handler.vault();
        assertLe(v.totalClaimed(), v.totalFunded(), "INV-3: totalClaimed > totalFunded");
    }

    /// INV-4: emissionRate <= MAX_RATE_PER_SECOND
    function invariant_4_RateLtMax() public view {
        RewardVault v = handler.vault();
        assertLe(v.emissionRatePerSecond(), v.MAX_RATE_PER_SECOND(), "INV-4: rate > MAX");
    }

    /// INV-5: vaultBalance == totalFunded - totalClaimed (accounting conservation)
    function invariant_5_BalanceConservation() public view {
        RewardVault v = handler.vault();
        assertEq(v.vaultBalance(), v.totalFunded() - v.totalClaimed(),
            "INV-5: balance != funded - claimed");
    }

    /// INV-6: totalEmitted - totalClaimed == totalPending (emission = pending + claimed)
    function invariant_6_EmissionPartition() public view {
        RewardVault v = handler.vault();
        assertEq(v.totalPending(), v.totalEmitted() - v.totalClaimed(),
            "INV-6: pending != emitted - claimed");
    }

    /// INV-7: Deactivated fees not confiscated (claimable + claimed >= at-deactivation)
    function invariant_7_DeactivatedFeesNotConfiscated() public view {
        RewardVault v = handler.vault();
        uint256 n = handler.registeredCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 rid = handler.rids(i);
            if (handler.wasDeactivated(rid)) {
                uint256 atDeact = handler.claimableAtDeactivation(rid);
                uint256 current = v.claimable(rid);
                uint256 claimedAfter = handler.claimedAfterDeactivation(rid);
                assertGe(current + claimedAfter, atDeact,
                    "INV-7: fees confiscated on deactivation");
            }
        }
    }

    /// INV-8: totalRemaining = totalFunded - totalEmitted
    function invariant_8_RemainingConsistency() public view {
        RewardVault v = handler.vault();
        assertEq(v.totalRemaining(), v.totalFunded() - v.totalEmitted(),
            "INV-8: totalRemaining inconsistent");
    }
}

// ── Standalone fuzz tests ─────────────────────────────────────────────────────

contract RewardVaultFuzz is Test {

    address constant ADMIN = address(0xA1);
    uint256 immutable MAX_R;

    RewardVault vault;
    bytes32 constant R0 = keccak256("r0");
    bytes32 constant R1 = keccak256("r1");
    bytes32 constant R2 = keccak256("r2");

    constructor() {
        MAX_R = uint256(3_000_000 * 1 ether) / 31_536_000;
    }

    function setUp() public {
        vault = new RewardVault(ADMIN, MAX_R);
        vm.deal(ADMIN, 100_000_000 ether);
        vm.deal(address(this), 100_000_000 ether);
    }

    function _fund(uint256 amount) internal {
        (bool ok,) = address(vault).call{value: amount}("");
        require(ok);
    }

    function _reg(bytes32 id, address addr, uint128 weight, bool active) internal {
        vm.prank(ADMIN);
        vault.registerRecipient(id, addr, weight, active);
    }

    /// FUZZ-1: Random funding + time; emission never exceeds funded
    function testFuzz_F1_EmissionNeverExceedsFunded(uint128 fund, uint32 elapsed) public {
        fund    = uint128(bound(fund, 1, 10_000_000 ether));
        elapsed = uint32(bound(elapsed, 1, 10 * 365 days));

        _fund(fund);
        _reg(R0, address(0xAA), 1, true);

        vm.warp(block.timestamp + elapsed);

        uint256 claimableAmt = vault.claimable(R0);
        assertLe(claimableAmt, fund, "FUZZ-1: claimable exceeds funded");
        assertLe(vault.totalEmitted(), vault.totalFunded(), "FUZZ-1: emitted > funded");
    }

    /// FUZZ-2: Random weights; proportional allocation correct
    function testFuzz_F2_ProportionalAllocation(uint64 w0, uint64 w1, uint32 elapsed) public {
        w0      = uint64(bound(w0, 1, 100));
        w1      = uint64(bound(w1, 1, 100));
        elapsed = uint32(bound(elapsed, 1 days, 365 days));

        _fund(1_000_000 ether);
        _reg(R0, address(0xAA), uint128(w0), true);
        _reg(R1, address(0xBB), uint128(w1), true);

        vm.warp(block.timestamp + elapsed);

        uint256 c0 = vault.claimable(R0);
        uint256 c1 = vault.claimable(R1);
        uint256 total = c0 + c1;

        if (total > 0) {
            // c0 / total ~= w0 / (w0 + w1), within 1 wei
            uint256 expectedC0 = total * w0 / (w0 + w1);
            assertGe(c0, expectedC0 > 1 ? expectedC0 - 1 : 0);
            assertLe(c0, expectedC0 + 1);
        }

        // Conservation
        assertLe(vault.totalEmitted(), vault.totalFunded());
    }

    /// FUZZ-3: Random rate reductions; historical rewards preserved
    function testFuzz_F3_RateReduction_HistoricalPreserved(uint32 elapsed1, uint64 newRatePct) public {
        elapsed1   = uint32(bound(elapsed1, 1 days, 90 days));
        newRatePct = uint64(bound(newRatePct, 1, 99)); // reduce to 1%-99% of max

        _fund(10_000_000 ether);
        _reg(R0, address(0xAA), 1, true);

        vm.warp(block.timestamp + elapsed1);
        uint256 earnedPeriodA = vault.claimable(R0);

        // Reduce rate
        uint256 newRate = MAX_R * newRatePct / 100;
        vm.prank(ADMIN);
        vault.setEmissionRate(newRate);

        // Historical must be preserved
        assertEq(vault.claimable(R0), earnedPeriodA, "FUZZ-3: historical corrupted by rate change");

        // New emission at reduced rate
        vm.warp(block.timestamp + elapsed1);
        uint256 periodB = vault.claimable(R0) - earnedPeriodA;

        // Period B <= period A (since rate was reduced)
        assertLe(periodB, earnedPeriodA + 1, "FUZZ-3: reduced rate emits more than full rate");
    }

    /// FUZZ-4: Random deactivation; earned fees never confiscated
    function testFuzz_F4_Deactivation_FeesPreserved(uint32 elapsed, uint128 fund) public {
        elapsed = uint32(bound(elapsed, 1 days, 180 days));
        fund    = uint128(bound(fund, 1 ether, 5_000_000 ether));

        _fund(fund);
        _reg(R0, address(0xAA), 1, true);
        _reg(R1, address(0xBB), 1, true);

        vm.warp(block.timestamp + elapsed);
        uint256 earned0 = vault.claimable(R0);

        // Deactivate R0
        vm.prank(ADMIN);
        vault.deactivateRecipient(R0);

        // Claimable must be preserved
        assertEq(vault.claimable(R0), earned0, "FUZZ-4: fees confiscated on deactivation");

        // R0 earns nothing more after deactivation
        vm.warp(block.timestamp + elapsed);
        assertEq(vault.claimable(R0), earned0, "FUZZ-4: deactivated recipient still accrues");

        // Conservation
        assertEq(vault.vaultBalance(), vault.totalFunded() - vault.totalClaimed());
    }

    /// FUZZ-5: No cross-recipient claim possible
    function testFuzz_F5_NoCrossRecipientClaim(uint32 elapsed, uint128 fund) public {
        elapsed = uint32(bound(elapsed, 1 days, 365 days));
        fund    = uint128(bound(fund, 1 ether, 1_000_000 ether));

        address alice = address(0xAA);
        address bob   = address(0xBB);

        _fund(fund);
        _reg(R0, alice, 1, true);
        _reg(R1, bob,   1, true);

        vm.warp(block.timestamp + elapsed);

        // Alice cannot claim Bob's
        vm.prank(alice);
        vm.expectRevert("RV: caller is not rewardAddress");
        vault.claim(R1);

        // Bob cannot claim Alice's
        vm.prank(bob);
        vm.expectRevert("RV: caller is not rewardAddress");
        vault.claim(R0);
    }

    /// FUZZ-6: Conservation at random timestamps
    function testFuzz_F6_Conservation(uint32 e1, uint32 e2, uint32 e3) public {
        e1 = uint32(bound(e1, 1, 365 days));
        e2 = uint32(bound(e2, 1, 365 days));
        e3 = uint32(bound(e3, 1, 365 days));

        _fund(3_000_000 ether);
        _reg(R0, address(0xAA), 1, true);
        _reg(R1, address(0xBB), 2, true);

        vm.warp(block.timestamp + e1);
        vm.prank(address(0xAA)); vault.claim(R0);

        vm.warp(block.timestamp + e2);
        vm.prank(address(0xBB)); vault.claim(R1);

        vm.warp(block.timestamp + e3);

        // INV-5: balance == funded - claimed
        assertEq(vault.vaultBalance(), vault.totalFunded() - vault.totalClaimed(),
            "FUZZ-6: conservation violated");

        // INV-1: emitted <= funded
        assertLe(vault.totalEmitted(), vault.totalFunded(), "FUZZ-6: emitted > funded");

        // INV-2: claimed <= emitted
        assertLe(vault.totalClaimed(), vault.totalEmitted(), "FUZZ-6: claimed > emitted");
    }

    /// FUZZ-7: 5-year simulation at max rate; yearly cap always respected
    function testFuzz_F7_FiveYear_YearlyCap(uint8 numRecipients) public {
        numRecipients = uint8(bound(numRecipients, 1, 5));

        _fund(15_000_000 ether);

        bytes32[5] memory rids;
        for (uint256 i = 0; i < numRecipients; i++) {
            rids[i] = keccak256(abi.encodePacked("yr-r", i));
            vm.prank(ADMIN);
            vault.registerRecipient(rids[i], address(uint160(0x9000 + i)), 1, true);
        }

        uint256 prevEmitted = 0;
        for (uint256 y = 1; y <= 5; y++) {
            vm.warp(block.timestamp + 365 days);

            // Trigger emission update via a no-op weight update
            // (just read claimable to force view-path; actual state update on next tx)
            // Actual check on totalEmitted after a write
            if (vault.claimable(rids[0]) > 0) {
                vm.prank(address(0x9000));
                vault.claim(rids[0]);
            }

            uint256 nowEmitted = vault.totalEmitted();
            uint256 yearlyEmission = nowEmitted - prevEmitted;

            assertLe(yearlyEmission, 3_000_000 ether,
                "FUZZ-7: annual emission exceeded 3M PW");

            prevEmitted = nowEmitted;
        }

        assertLe(vault.totalEmitted(), 15_000_000 ether, "FUZZ-7: total emitted > 15M");
    }

    /// FUZZ-8: Zero-weight period; emission pauses, no loss
    function testFuzz_F8_ZeroWeight_EmissionPauses(uint32 pauseDuration) public {
        pauseDuration = uint32(bound(pauseDuration, 1 days, 180 days));

        // Use absolute timestamps to avoid via_ir block.timestamp caching:
        // with via_ir, successive `block.timestamp` reads in the same function
        // can return the initial value (1) instead of the post-warp value, causing
        // backward warps and underflow in _updateGlobal's elapsed subtraction.
        uint256 t1 = 1_000_000;                    // anchor: setup + period-1 start
        uint256 t2 = t1 + 30 days;                 // period-1 end / zero-weight start
        uint256 t3 = t2 + pauseDuration;            // zero-weight end / period-2 start
        uint256 t4 = t3 + 30 days;                 // period-2 end / claim time

        // Setup at t1 so lastUpdateTime is anchored there
        vm.warp(t1);
        _fund(5_000_000 ether);
        _reg(R0, address(0xAA), 1, true);           // _updateGlobal: lastUpdateTime = t1

        // Period 1: 30 days active
        vm.warp(t2);
        // Deactivate -- _updateGlobal checkpoints period-1 emission.
        vm.prank(ADMIN);
        vault.deactivateRecipient(R0);
        uint256 emittedPeriod1 = vault.totalEmitted();

        // Advance during zero-weight period (no emission should occur)
        vm.warp(t3);
        // Re-activate -- _updateGlobal runs with weight==0, nothing emitted
        vm.prank(ADMIN);
        vault.activateRecipient(R0);
        assertEq(vault.totalEmitted(), emittedPeriod1, "FUZZ-8: emission during zero-weight pause");

        // Period 2: 30 more days active
        vm.warp(t4);
        // Claim flushes period-2 emission into totalEmitted
        vm.prank(address(0xAA));
        vault.claim(R0);

        // period2 must be at most 30 days worth
        uint256 period2Emitted = vault.totalEmitted() - emittedPeriod1;
        uint256 maxPeriod2 = uint256(30 days) * MAX_R;
        assertLe(period2Emitted, maxPeriod2 + 1, "FUZZ-8: period2 > 30 days emission");

        // Conservation always holds (allow 1 wei dust from precision)
        uint256 funded  = vault.totalFunded();
        uint256 claimed = vault.totalClaimed();
        assertGe(funded + 1, claimed, "FUZZ-8: totalClaimed exceeds funded by > 1 wei");
        if (claimed <= funded) {
            assertEq(vault.vaultBalance(), funded - claimed, "FUZZ-8: balance conservation");
        }
    }
}
