# DIRECT_MAINNET software validation

Implementation:PASS. Deployment readiness:BLOCKED. Source change only; no AWS
API calls/mutations, guest sessions, identity generation, signing, transfers,
installation or node/blockchain startup performed. Main/PWUSD untouched.

- Full Python suite:151 passed,2 skipped,0 failures (153 total). Skips: verified
  native/Linux archives not supplied in this run; prior binary tests not repeated.
-17 direct-strategy/security tests also PASS under Python -O; production gates
  use explicit exceptions and cannot be optimized away.
-8 shared integration combinations PASS:2 regions ×2 profiles ×Fuji/Mainnet.
- JSON Schema Draft2020-12: schema valid; all3 deployment manifests valid.
  Structural validity permits null planning fields; readiness still blocks them.
- mypy1.18.2, check-untyped-defs/follow-imports=skip/ignore-missing-imports:
  all3 deployment Python source files PASS. Isolated checker environment in/tmp;
  no repository dependency changes. jsonschema4.25.1 used for schema checks.
- Ansible2.19.4/Python3.13 syntax PASS:4 region/profile AWS inventories plus
  offline Netcup adapter. No controller connections were opened.
- Both real direct readiness stages return BLOCKED; signing/broadcast/AWS
  mutation fields remain false. No fabricated Fuji or commissioning evidence.
- Validator1 canonical request digest remains
  d585f3f6eb699f4c02def92de290533d5fb9588e56332420217d3e023c1fbce4.
  Historical local launch/stop files match sydney-history.index.json unchanged.
  Original requests, approvals, ClientToken and actual-state records preserved.
- Existing stopped Validator1 reconciliation is a NEW public review manifest,
  not a rewrite of historical evidence. Its recorded IDs prevent initial relaunch
  even with copied old approval. Explicit Validator2 dry preparation still works;
  its real launch and all committed host/transaction approvals remain false.

Strategy-specific removals:mandatory Fuji ceremony result before Mainnet and
mandatory Fuji workload before small-profile production review. Fuji tooling
remains optional and cannot authorize Mainnet. Smaller-profile actual workload
criteria are retained for POST_MAINNET_ACCEPTANCE using Mainnet-bound evidence.
Host/storage/identity checks before creation remain mandatory; no thresholds or
C00 economics changed. Initial creation does not require future chain receipts;
later operation gates enforce accepted predecessor evidence and actual IDs.

Evidence contract (public JSON only):hostEvidence references cloud/local facts
plus operational instance/volume/UUID/public-identity/certificate/alert-event
records. Registry and exact constructor/genesis/artifact/VM files are checked
against their digests. Security review must bind code, protected proxy bootstrap,
ownership/timelock and weights. Recovery and incident reports require actual
procedure tests/fencing. Each transaction request is a single reviewed operation
with network/genesis/parameters/signer/budgets; its approval binds operation,
account,region,canonical request SHA256 and <=24h timestamps. Post evidence
contains both-node raw matching receipts, fixed-block balances, gas/fee deltas,
progress, registration, resources, alert delivery, separately digest-bound actual
production restoration evidence and final owner acceptance. Operator provenance
and genuine source observations remain essential: hashes alone authenticate
integrity, not truth. No deployment collector or reviewer may label fixtures real.

Current blockers:Validator2 absent; Validator1 last observed stopped, IPv4
released; fresh raw host/UUID/performance/identity/alerts evidence absent;
production identity/custody ceremony not authorized; ChainID not approved;
final constructor/genesis/manager/VM reviews missing; funding/signers and exact
operation approvals missing; tested recovery/incident evidence missing. Actual
production receipts/commissioning/recovery/final acceptance are intentionally
post-launch blockers only. No current Mainnet readiness is claimed.

Next owner decision:separate Validator2-only EC2 spending/creation approval after
fresh read-only resource and duplicate-instance checks. This does not authorize
Validator1 restart, provisioning, identities or any blockchain operation.
