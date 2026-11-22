# Future isolated final-genesis VM validation specification

**Specification only. NOT executed or authorized by this document.** No node,
identity generation, signing, RPC server or public-network operation is started
by the integration tooling. Neither committed synthetic candidate is a production
artifact. Independent reviewer and owner must approve the test plan before work
outside the present software-only scope.

## Required inputs and isolation

- Freeze source commit, original locks, independently reviewed custody/Safe
  runtimes, pinned AvalancheGo/Subnet-EVM1.15.1/protocol46 binaries and their hashes.
- Obtain accepted real SubnetID evidence (CreateSubnetTx separately approved), final
  approved EVM ChainID, timestamp/fork/fee/Warp configuration, full predeploy map,
  public signer/owner lists, actual library link addresses and exact final genesis
  hash. No test may invent these or accept synthetic bytes32(123) as a substitute.
- Build/export the combined **actual-address** manager implementation/library/
  transparent proxy/child ProxyAdmin/PoA state and custody state. Check runtime
  immutables, ERC1967 admin versus actual immutable admin and all nonces. The
  production author must independently account for constructor-created children;
  this task supplies synthetic integration, not a general production approval tool.
- Check every code/account/signer/precompile address for overlaps, retaining only
  explicit treasury/reward allocation aliases. Match all seven C00 allocations,
  exact100M supply, no native minter, fee route and no extra gas allocation.
- Choose a fresh isolated ephemeral database/work directory, local-only APIs,
  no public P2P/bootstrapping, no real RPC/signing provider, AWS resources or
  historical pw-demo-04 paths. Fail if isolation cannot be established. Never
  modify an existing validator database to run this test.
- Evidence must bind commit, binaries, exact genesis bytes/hash, config, actual
  public SubnetID/address inputs, timestamps, commands and complete results.
  Store no secrets. Do not set production approval flags as part of a test.

## Pass/fail assertions against the actual VM state

1. VM handshake protocol46 and acceptance of **the exact final genesis**, with no
   config substitution/fresh-network fallback. Record VM/build logs and any rejected
   fork/timestamp/state. Missing artifact or unavailable VM means BLOCKED, not PASS.
2. Fetch chainId, block0/block progression policy, eth_getCode for **all** code
   accounts; compare entire runtime including metadata and patched immutables.
   Compare each exported storage slot, account nonce and native balance against
   imported genesis. Inspect relevant fresh-zero/absence slots as negative tests,
   not just the exported positive slot list. Query historical block0 explicitly.
3. Via eth_call/getStorageAt: both Safe owners exactly five/threshold3, nonce0,
   no approved hashes, modules sentinel/empty list, handler0, paired guard slot;
   singleton locked. Guard.safe/timelock, closed timelock roles/self-admin/minDelay,
   no deployer/author/EOA/emergency bypass. Enumerate all intended role-member
   mapping slots; getters alone cannot enumerate every unknown AccessControl role.
4. Implementation initializer disabled; proxy manager initializer already consumed,
   correct SubnetID/churn/owner=PoA, PoA.owner=P-TL and immutable manager=proxy,
   ProxyAdmin.owner=P-TL and actual immutable proxy-admin dispatch matches the
   exported child account. Verify exact library code/binding and no fake0x6000.
5. Registry manager/fee pointers/admin and all vault/distributor controllers,
   destinations, weights/recipients, reward funded15M/emitted0/claimed0, treasury15M,
   all remaining C00 balances and exact sum100M. Check gas reward credits that bypass
   receive and eventual70/20/10 settlement; native accounting/dust/burn semantics
   require explicit transaction-level expectations, not only constant getters.
6. Negative eth_call simulations: replay initialization, wrong Safe quorum, direct
   EOA withdrawals/upgrades/role grants, guard self-configuration/delegatecall/refund
   routes, forbidden emergency selectors/targets, early timelock execution and
   reducing delay below48h all fail as intended. Simulation does not prove real
   signatures or accepted transaction execution.
7. In a separately authorized disposable test state only: real supported signing
   path (EOA and any intended contract signer), successful schedule/cancel/execute,
   native value, malicious recipient/reentrancy, atomic migration success/revert,
   delayed proxy upgrade and PoA ownership operations. Require Safe inner
   ExecutionSuccess/true, target state, nonce, gas and balances; outer status1 alone
   fails acceptance. Never change final production genesis balances to fund tests.
8. Conversion/Warp: uninitialized validator set before conversion is expected.
   Bad message/source/chain/manager/SubnetID/validator data rejected; actual
   authenticated conversion only after separately approved P-Chain transaction and
   network test authorization. Mocked Warp cannot satisfy this criterion. Synthetic
   NodeID/BLS data do not constitute validator registration or live consensus proof.
9. Recovery/availability: separate authorized environment must demonstrate persistent
   state/restart, monitoring/cancellation windows and staged validator replacement
   acknowledgments. Two-validator liveness/correlation acceptance remains a human
   decision; a single isolated VM cannot demonstrate multi-validator consensus.

## Acceptance record and gating

Report each item PASS/FAIL/BLOCKED/NOT_EXECUTED with exact input hashes, raw sanitized
results, reviewer identity/reference and known limitations. No assumed success,
missing-account substitution, fixture approval or automatic approval mutation.
`mainnet_readiness.py` still requires genuine final-genesis custodyStateSha256,
manager initialization and accepted SubnetID proof; the synthetic integration
report cannot satisfy those production evidence gates. Keep CreateSubnet's
pre-SubnetID gate separate from CreateChain's final artifact gate. Every public
transaction, signing action, spend and deployment needs separate owner approval.
