# Allocation reconciliation — owner decision required

C00 `PRIMEWAVE_TOKENOMICS.md` is the recorded approved baseline; C11 is conflicting
later documentation, not evidence of an approved change. No addresses or new PW
grants are introduced. Amounts below are millions of PW unless stated otherwise.

| Allocation | C00 approved baseline | C11 finalization | Resolution in this branch |
|---|---:|---:|---|
| Fixed total / decimals | 100M / 18 | 100M / 18 | Preserved |
| Validator/staking rewards | 15 | 15 | Preserved; genesis versus post-deploy custody unresolved |
| Liquidity | 40 | Absent | Retain C00 baseline; do not silently remove |
| Treasury | 15 | 25 | No increase approved here |
| Team | 10 | 20 | No increase approved here |
| Presale P1/P2/P3 | 5 / 7.5 / 7.5 | Community20, stages unspecified | Preserve C00 stages unless explicit superseding approval |
| Ecosystem / reserve | No separate allocation | 10 / 9.999999 | No new buckets invented |
| Deployer gas | No separate grant | 1 PW | Funding source within100M requires approval |
| Native minting / fee split | Disabled /70:20:10 | Disabled /70:20:10 | Preserved |

Choose **A:** confirm C00 remains authoritative (review manifest already carries
those amounts), or **B:** provide explicit superseding approval for the complete
C11 distribution. Do not combine rows from both tables. Supply production-only
addresses and decide whether RewardVault is predeployed/initialized at genesis or
funded after deployment from an explicitly approved custody arrangement. Both
paths must account for the same15M exactly once and preserve total100M.

No deployable genesis is generated while approval, addresses, deterministic fee
routing, deployment gas custody and VM-compatible fork configuration are missing.
