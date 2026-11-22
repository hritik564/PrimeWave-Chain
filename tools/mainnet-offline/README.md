# Mainnet offline tools — signing/broadcast disabled

These tools do not approve production or implement an external security audit.
No wallet/private key input, identity generation, AWS operation, node deployment,
public RPC or transaction submission. Preserve existing readiness gates.

## 1. Public-input genesis candidate

```sh
python3 scripts/mainnet/export_mainnet_genesis.py \
  --public-inputs "$PUBLIC_INPUTS" --base-genesis "$BASE_GENESIS" \
  --accepted-subnet "$ACCEPTED_SUBNET" --input-review "$INPUT_REVIEW" \
  --chain-decision "$CHAIN_DECISION" --registry "$REGISTRY" \
  --archives "$PINNED_PUBLIC_ARCHIVES" --output genesis-build/NEW-ceremony \
  --forge /path/to/forge --cast /path/to/cast
```

All paths are explicit; no examples substitute production addresses or IDs.
PUBLIC_INPUTS uses the existing public-genesis schema plus `manager` containing
`library,implementation,proxy,poa,proxyAdmin,validatorWeights,churnPeriodSeconds,
maximumChurnPercentage`; managerAddress=proxy. Add managerSubnetId (real CB58).
Optional validationPublicIdentity contains existing public nodeId/blsPublicKey.
Require reviewed publicAddressesReviewed/custodyProposalApproved input records;
INPUT_REVIEW requires ownerReviewed/reference and raw-file publicSha256,
baseSha256,acceptedSubnetSha256. These are address/policy input reviews, **not**
final-state or transaction approvals. No approval record is generated/modified.
ACCEPTED_SUBNET requires networkId1, accepted=true, subnetId=transactionId and a
reference; independent owner-reviewed provenance is required. Offline code cannot
prove a supplied receipt is authentic or currently accepted. Chain decision must
pass the existing fresh-registry/exact-owner gate. No accepted real inputs exist
in this checkout; tests do not fabricate such evidence for an export run.

Three separate authoring EVMs build pinned custody, linked manager/PoA/proxy/admin,
then restore the entire combined state and verify getters. New output only;
partial output after failure is NOT successful evidence. No existing files are
replaced. Runtime bytes/AST immutable ranges, proxy/admin nonce, ownership,
collisions, repeated manager export and100M supply are checked. Output genesis.json
has a raw-file hash and separate canonical hash; construction.review.json clears
review flags for the NEW state, export.json retains productionApproved=false and
finalVmAccepted=false. Artifacts remain in that new directory; old locks untouched.

## 2. Exact-byte local VM import

```sh
python3 scripts/mainnet/validate_exact_genesis.py \
  --genesis genesis-build/NEW-ceremony/genesis.json \
  --expectations genesis-build/NEW-ceremony/vm-expectations.json \
  --vm-binary "$PINNED_VM_BINARY" --binary-archive "$PINNED_RELEASE_ARCHIVE" \
  --go /path/to/go
```

Go1.26.8, cached checksum-verified module dependencies and supported native binary
required. Module is AvalancheGo1.15.1/fdb2c1b9 (go.sum and runtime module checksum);
plugin archive/binary must match existing lock. GOPROXY/GOSUMDB are disabled during
validation. No download, genesis reconstruction, key generation, signing, block
building or transfer occurs. Context uses provided public BLS/NodeID and a
hash-derived **local context** chain identifier, not a future production BlockchainID;
Warp signing always errors. Only plugin processes, fresh memdb and loopback RPC.
Checks complete code/storage/balance/nonce and explicit role/owner getters at block0.
No skipped test is accepted. PASS proves exact supplied-byte local import only,
not authenticated conversion, validator operation, live consensus or deployment
approval. Synthetic test input is separately labeled by its fixture builder.

## 3. One unsigned P-Chain transaction

```sh
cd tools/mainnet-offline
GOTOOLCHAIN=local GOPROXY=off go run -mod=readonly ./cmd/pchain \
  --plan "$PUBLIC_TRANSACTION_PLAN" --state-evidence "$PUBLIC_STATE_SNAPSHOT"
# Same command plus --verify-envelope "$EXPORTED_UNSIGNED_ENVELOPE" revalidates.
```

Exact public JSON fields are the `Plan`, `Owners`, `StateSnapshot` and validator
structs in pchain.go. Operations: createSubnet / createChain / convertSubnet.
No auto-sorting, default weight/owner/budget or all-in-one tool. Supply sorted
UTXOs/outputs/owners/validator NodeIDs and explicit signature indices/thresholds,
canonical Mainnet AVAX/network1, accepted predecessor IDs, raw genesis hex/hash,
evmChainId, manager/churn/weights/return/deactivation owners and public BLS PoPs.
All amounts are uint64 **nanoAVAX**, not floating AVAX. Outputs support exact
funding-owner change only. Snapshot file hash must match; observedAt/expiresAt are
RFC3339, <=15min. Snapshot provenance/authenticity, unspent UTXOs, actual subnet
ownership, accepted receipts and live fee price remain external evidence duties.
Pinned dynamic complexity/fees, conservation including validator deposits,
maximumFee/maximumTotalSpend, native syntactic checks, BLS proofs and exact codec
roundtrip are enforced; future fee movement/semantic execution is not simulated.

External signer boundary: independently review the full plan, snapshot, unsignedHex,
unsignedSha256 (the unsigned signing digest), canonical Go-struct-JSON planSha256,
role/address/index requirements and budgets. This is **not** a signed transaction
ID. Separate external owner approval/hardware custody must precede future signing.
Current tool deliberately cannot consume a signature: AcceptSignature always
errors; signingEnabled/broadcastEnabled/approvalGranted always false. No signer
callback, secret flag, submit mode or hidden RPC exists. Final external signer and
broadcast integration requires separate review/authorization; this task supplies
the unsigned preparation/validation boundary only, as requested.
