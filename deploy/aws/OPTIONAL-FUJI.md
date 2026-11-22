# Optional Fuji tooling

This is not a Mainnet readiness prerequisite. Use fresh test-only identities,
a distinct Chain ID and separate approvals. Never reuse production custody.
The historical create-l1 bundle remains review-only.

## Optional temporary Fuji rehearsal

1. Complete both host preflights. Owner authorizes **Fuji-only** identity creation
   and startup separately. The pinned fresh-identity tool is already compiled
   by CI; run only under the approved operator's custody. Store Fuji identity/DB
   beneath `primewave/fuji-rehearsal`, never `pw-demo-04` or production directories.
   Owner records public NodeID, BLS public key/PoP and certificate SHA only.
2. Select/approve a collision-checked Fuji EVM ID distinct from development73571
   and the production candidate73571001. Use fresh disposable Fuji governance,
   custody and transaction wallets. Do not require or generate production keys
   to rehearse. Owner obtains faucet test AVAX on the Fuji P-Chain and approves
   exact creation fees, both validator initial balances, renewal/fee runway and
   change/refund ownership. A controller can share one validator host; validators
   and an owner-operated local signature aggregator must remain reachable through
   explicit loopback SSM tunnels. No paid/public aggregator fallback is authorized.
3. With approved host-start only, synchronize public Fuji P-Chain (network 5),
   check health/P-chain bootstrap and public 9651 peers. Mainnet later uses network 1,
   fresh production-only TLS/BLS identities and fresh approved custody addresses.
   Never run the two environments simultaneously on a shared 9651 listener.
4. **Staged signing approvals:** owner first approves CreateSubnetTx parameters,
   P-chain control owners/thresholds, fee/change budget and signer. Record accepted
   receipt/SubnetID. Bind the reviewed manager initialization to that actual ID;
   finalize constructor-executed proxy/library/manager and C00 genesis state.
   A publicly callable uninitialized manager proxy is forbidden. If choosing an
   owner-controlled atomic upgrade+initialize bootstrap instead, review and test
   that exact artifact first; merely setting a review flag is insufficient.
5. Owner approves the exact final genesis hash and CreateChainTx/VM parameters,
   then signs/broadcasts CreateChainTx. Preserve the receipt, BlockchainID and VMID.
   Install the existing plugin/chain configuration under those actual IDs. Do not
   rerun creation commands after a timeout: inspect saved transaction status first.
6. Owner approves ConvertSubnetToL1Tx containing the actual manager chain/address,
   two fresh public NodeIDs/BLS PoPs, weights, validation balances and return owners.
   Preserve accepted conversion receipt/data. Initialize/activate the manager
   through reviewed ownership and verify `initializeValidatorSet` with the actual
   conversion Warp message using the local aggregator. Do not treat a CLI exit 0
   as proof of ownership or validator-set correctness. The existing all-in-one
   create-l1 argv is review-only; do not use it to bypass the staged subnet-binding
   or protected-bootstrap requirement.
7. Verify both nodes' expected identities, registration/weights and peers, health,
   advancing accepted blocks and matching genesis/block/receipt hashes. Open each
   RPC using `AWS-StartPortForwardingSession` to remote 9650 and the manifest's local
   tunnel port; no inbound RPC/SSH. Reuse the four-method verifier:
   `python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/sydney.existing-runtime.review.json --host validator-1 --environment fuji --rpc-check`
   (repeat validator-2; later use `--environment mainnet`). It requires an explicit
   non-demo Chain ID and actual BlockchainID, always calls loopback, never signs.
8. Owner authorizes a bounded native PW smoke transfer between the manifest's
   disposable wallets, funded by an approved spend from an existing C00 allocation
   (no additional genesis grant). Record amount/gas ceiling before signing. Check
   status 1, canonical accepted receipt on both nodes and balances at fixed blocks:
   sender decrease = value + gasUsed*effectiveGasPrice; recipient increase = value.
9. Separately approve permissionless `FeeDistributor.distribute()` transaction and
   its gas budget. Verify event/cumulative-accounting deltas: validators=floor(A*70%),
   treasury=floor(A*20%), burn=A-minus-both; sum exactlyA. Verify actual destination
   contracts/custody and resulting balances; account for this call's own gas fees
   arriving after execution and any other concurrent transactions. Check vault
   funding/counters/no NativeMinter and that no extra PW allocation was introduced.
10. Approve a maintenance/recovery drill. With two validators, stopping either
    halts the chain: this is an accepted non-resilient pilot, not HA. Stop one cleanly,
    preserve the EBS/identity/DB and an encrypted off-host backup, fence the old host,
    then restore/reattach to a replacement in the **same AZ**. Across AZs or later
    Netcup migration use an authorized consistent snapshot/restore or encrypted
    stopped-node backup; EBS cannot simply move between AZs. Preserve UID/GID and
    NodeID/BLS/certificate/DB/registration; never run two active copies of one identity.
    Missing/wrong mount must fail startup, not initialize a replacement database.
11. Retain optional Fuji evidence and obtain separate teardown authorization.
    Optional Fuji completion never authorizes Mainnet and is not a prerequisite
    for DIRECT_MAINNET. Use EXECUTION.md for the production procedure.
