// Offline unsigned preparation only. No wallet, signer, RPC or broadcast client.
package offline

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/ava-labs/avalanchego/genesis"
	"github.com/ava-labs/avalanchego/ids"
	"github.com/ava-labs/avalanchego/snow"
	"github.com/ava-labs/avalanchego/utils/constants"
	"github.com/ava-labs/avalanchego/utils/formatting/address"
	"github.com/ava-labs/avalanchego/vms/components/avax"
	"github.com/ava-labs/avalanchego/vms/components/gas"
	"github.com/ava-labs/avalanchego/vms/platformvm/platform"
	"github.com/ava-labs/avalanchego/vms/platformvm/signer"
	"github.com/ava-labs/avalanchego/vms/platformvm/txs/fee"
	"github.com/ava-labs/avalanchego/vms/platformvm/warp/message"
	"github.com/ava-labs/avalanchego/vms/secp256k1fx"
)

const AvalancheCommit = "fdb2c1b9b02ef357b5867d5ababb6acc83837a01"
const MainnetAVAX = "FvwEAhmxKfeiG8SnEvq42hc6whRyY3EFYAvebMqDNDGCgxN5Z"

var ErrSigningDisabled = errors.New("signing and broadcast disabled; external review envelope only")

type Owners struct {
	Threshold uint32   `json:"threshold"`
	Addresses []string `json:"addresses"`
	Locktime  uint64   `json:"locktime"`
}
type FundingInput struct {
	TxID             string   `json:"txId"`
	OutputIndex      uint32   `json:"outputIndex"`
	Amount           uint64   `json:"amountNanoAvax"`
	Owner            Owners   `json:"owner"`
	SignatureIndices []uint32 `json:"signatureIndices"`
}
type FundingOutput struct {
	Amount uint64 `json:"amountNanoAvax"`
	Owner  Owners `json:"owner"`
}
type InitialValidator struct {
	NodeID         string `json:"nodeId"`
	Weight         uint64 `json:"weight"`
	Balance        uint64 `json:"balanceNanoAvax"`
	PublicKey      string `json:"blsPublicKey"`
	Proof          string `json:"proofOfPossession"`
	RemainingOwner Owners `json:"remainingBalanceOwner"`
	DisableOwner   Owners `json:"deactivationOwner"`
}
type Plan struct {
	Operation              string             `json:"operation"`
	NetworkID              uint32             `json:"networkId"`
	AssetID                string             `json:"avaxAssetId"`
	Inputs                 []FundingInput     `json:"inputs"`
	Outputs                []FundingOutput    `json:"outputs"`
	SubnetOwner            Owners             `json:"subnetOwner"`
	AuthIndices            []uint32           `json:"subnetSignatureIndices"`
	SubnetID               string             `json:"subnetId"`
	BlockchainID           string             `json:"blockchainId"`
	ManagerAddress         string             `json:"managerAddress"`
	EVMChainID             uint64             `json:"evmChainId"`
	ManagerChurnPercentage uint8              `json:"managerChurnPercentage"`
	ManagerChurnPeriod     uint64             `json:"managerChurnPeriodSeconds"`
	ChainName              string             `json:"chainName"`
	VMID                   string             `json:"vmId"`
	GenesisHex             string             `json:"genesisHex"`
	GenesisSHA256          string             `json:"genesisSha256"`
	Validators             []InitialValidator `json:"validators"`
	GasPrice               uint64             `json:"gasPriceNanoAvax"`
	MaximumFee             uint64             `json:"maximumFeeNanoAvax"`
	MaximumSpend           uint64             `json:"maximumTotalSpendNanoAvax"`
	ObservedAt             time.Time          `json:"observedAt"`
	ExpiresAt              time.Time          `json:"expiresAt"`
	StateEvidenceSHA256    string             `json:"stateEvidenceSha256"`
	AcceptedSubnetTxID     string             `json:"acceptedSubnetTxId"`
	AcceptedChainTxID      string             `json:"acceptedChainTxId"`
}
type SignerRequirement struct {
	Role      string   `json:"role"`
	Threshold uint32   `json:"threshold"`
	Addresses []string `json:"addresses"`
	Indices   []uint32 `json:"indices"`
}
type Envelope struct {
	Operation          string              `json:"operation"`
	NetworkID          uint32              `json:"networkId"`
	AvalancheCommit    string              `json:"avalancheCommit"`
	UnsignedHex        string              `json:"unsignedHex"`
	UnsignedSHA256     string              `json:"unsignedSha256"`
	PlanSHA256         string              `json:"planSha256"`
	Fee                uint64              `json:"feeNanoAvax"`
	MinimumFee         uint64              `json:"minimumFeeAtSnapshotNanoAvax"`
	ValidatorDeposits  uint64              `json:"validatorDepositsNanoAvax"`
	SignerRequirements []SignerRequirement `json:"signerRequirements"`
	SigningEnabled     bool                `json:"signingEnabled"`
	BroadcastEnabled   bool                `json:"broadcastEnabled"`
	ApprovalGranted    bool                `json:"approvalGranted"`
	Limitation         string              `json:"limitation"`
}

func Hash(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }
func checkedAdd(a, b uint64) (uint64, error) {
	if a > math.MaxUint64-b {
		return 0, errors.New("uint64 overflow")
	}
	return a + b, nil
}
func rawHex(s string, n int) ([]byte, error) {
	if !strings.HasPrefix(s, "0x") {
		return nil, errors.New("0x hex required")
	}
	b, e := hex.DecodeString(s[2:])
	if e != nil || len(b) != n {
		return nil, errors.New("wrong hex length")
	}
	return b, nil
}
func owner(o Owners) (*secp256k1fx.OutputOwners, error) {
	r := &secp256k1fx.OutputOwners{Threshold: o.Threshold, Locktime: o.Locktime}
	if o.Threshold == 0 || int(o.Threshold) > len(o.Addresses) {
		return nil, errors.New("explicit nonzero owner threshold required")
	}
	for _, a := range o.Addresses {
		var b []byte
		var e error
		if strings.HasPrefix(a, "0x") {
			b, e = rawHex(a, 20)
		} else {
			var alias, hrp string
			alias, hrp, b, e = address.Parse(a)
			if alias != "P" || hrp != "avax" {
				return nil, errors.New("Mainnet P-address required")
			}
		}
		if e != nil {
			return nil, e
		}
		id, e := ids.ToShortID(b)
		if e != nil || id == ids.ShortEmpty {
			return nil, errors.New("nonzero owner address required")
		}
		r.Addrs = append(r.Addrs, id)
	}
	if e := r.Verify(); e != nil {
		return nil, e
	}
	return r, nil
}
func requirements(role string, o *secp256k1fx.OutputOwners, indices []uint32) (SignerRequirement, error) {
	if len(indices) != int(o.Threshold) {
		return SignerRequirement{}, errors.New("exact threshold signature indices required")
	}
	r := SignerRequirement{Role: role, Threshold: o.Threshold, Indices: indices}
	for i, index := range indices {
		if int(index) >= len(o.Addrs) || (i > 0 && indices[i-1] >= index) {
			return r, errors.New("invalid signature indices")
		}
		a, e := address.Format("P", "avax", o.Addrs[index][:])
		if e != nil {
			return r, e
		}
		r.Addresses = append(r.Addresses, a)
	}
	return r, nil
}
func Prepare(p Plan, now time.Time) (Envelope, error) {
	var out Envelope
	if p.NetworkID != 1 || p.AssetID != MainnetAVAX {
		return out, errors.New("Mainnet network1 and canonical AVAX required")
	}
	if p.ObservedAt.IsZero() || p.ExpiresAt.IsZero() || now.Before(p.ObservedAt) || now.Sub(p.ObservedAt) > 15*time.Minute || !now.Before(p.ExpiresAt) || p.ExpiresAt.Sub(p.ObservedAt) > 15*time.Minute {
		return out, errors.New("fresh <=15 minute public state/fee snapshot required")
	}
	if len(p.StateEvidenceSHA256) != 64 {
		return out, errors.New("state snapshot digest required")
	}
	if _, e := hex.DecodeString(p.StateEvidenceSHA256); e != nil {
		return out, e
	}
	if p.GasPrice < uint64(genesis.MainnetParams.DynamicFeeConfig.MinPrice) || p.MaximumFee == 0 || p.MaximumSpend < p.MaximumFee {
		return out, errors.New("explicit Mainnet fee/budget required")
	}
	asset, e := ids.FromString(p.AssetID)
	if e != nil {
		return out, e
	}
	base := platform.BaseTx{BaseTx: avax.BaseTx{NetworkID: 1, BlockchainID: constants.PlatformChainID}}
	var inSum, outSum, deposits uint64
	var reqs []SignerRequirement
	if len(p.Inputs) == 0 {
		return out, errors.New("explicit funding UTXOs required")
	}
	for i, input := range p.Inputs {
		txID, e := ids.FromString(input.TxID)
		if e != nil || txID == ids.Empty {
			return out, errors.New("invalid funding tx ID")
		}
		own, e := owner(input.Owner)
		if e != nil {
			return out, e
		}
		if own.Locktime > uint64(now.Unix()) {
			return out, errors.New("locked funding input")
		}
		req, e := requirements(fmt.Sprintf("input-%d", i), own, input.SignatureIndices)
		if e != nil {
			return out, e
		}
		reqs = append(reqs, req)
		base.Ins = append(base.Ins, &avax.TransferableInput{UTXOID: avax.UTXOID{TxID: txID, OutputIndex: input.OutputIndex}, Asset: avax.Asset{ID: asset}, In: &secp256k1fx.TransferInput{Amt: input.Amount, Input: secp256k1fx.Input{SigIndices: input.SignatureIndices}}})
		inSum, e = checkedAdd(inSum, input.Amount)
		if e != nil {
			return out, e
		}
	}
	for _, output := range p.Outputs {
		own, e := owner(output.Owner)
		if e != nil {
			return out, e
		}
		change := false
		for _, funding := range p.Inputs {
			source, _ := owner(funding.Owner)
			if source.Equals(own) {
				change = true
			}
		}
		if !change {
			return out, errors.New("only exact funding-owner change outputs supported")
		}
		base.Outs = append(base.Outs, &avax.TransferableOutput{Asset: avax.Asset{ID: asset}, Out: &secp256k1fx.TransferOutput{Amt: output.Amount, OutputOwners: *own}})
		outSum, e = checkedAdd(outSum, output.Amount)
		if e != nil {
			return out, e
		}
	}
	var tx platform.UnsignedTx
	switch p.Operation {
	case "createSubnet":
		if p.SubnetID != "" || p.GenesisHex != "" || p.BlockchainID != "" || len(p.Validators) > 0 || len(p.AuthIndices) > 0 {
			return out, errors.New("future-operation fields forbidden")
		}
		own, e := owner(p.SubnetOwner)
		if e != nil {
			return out, e
		}
		tx = &platform.CreateSubnetTx{BaseTx: base, Owner: own}
	case "createChain", "convertSubnet":
		subnet, e := ids.FromString(p.SubnetID)
		if e != nil || subnet == ids.Empty || p.AcceptedSubnetTxID != p.SubnetID {
			return out, errors.New("accepted CreateSubnet ID binding required")
		}
		own, e := owner(p.SubnetOwner)
		if e != nil {
			return out, e
		}
		if own.Locktime > uint64(now.Unix()) {
			return out, errors.New("subnet control locked")
		}
		r, e := requirements("subnet-control", own, p.AuthIndices)
		if e != nil {
			return out, e
		}
		reqs = append(reqs, r)
		auth := &secp256k1fx.Input{SigIndices: p.AuthIndices}
		if p.Operation == "createChain" {
			if p.BlockchainID != "" || len(p.Validators) > 0 || p.ManagerAddress != "" {
				return out, errors.New("conversion fields forbidden")
			}
			vm, e := ids.FromString(p.VMID)
			if e != nil || vm != constants.SubnetEVMID {
				return out, errors.New("pinned Subnet-EVM VMID required")
			}
			data, e := hex.DecodeString(strings.TrimPrefix(p.GenesisHex, "0x"))
			if e != nil || len(data) == 0 || Hash(data) != p.GenesisSHA256 {
				return out, errors.New("exact genesis bytes/hash required")
			}
			var g struct {
				Config struct {
					ChainID uint64 `json:"chainId"`
				} `json:"config"`
			}
			if json.Unmarshal(data, &g) != nil || g.Config.ChainID != p.EVMChainID || p.EVMChainID < 1000 || p.EVMChainID > 9007199254740991 || p.EVMChainID == 1337 || p.EVMChainID == 31337 || p.EVMChainID == 73571 || p.EVMChainID == 43113 || p.EVMChainID == 43114 {
				return out, errors.New("explicit distinct EVM chain ID binding required")
			}
			tx = &platform.CreateChainTx{BaseTx: base, SubnetID: subnet, ChainName: p.ChainName, VMID: vm, GenesisData: data, SubnetAuth: auth}
		} else {
			if p.GenesisHex != "" || p.VMID != "" || p.ChainName != "" {
				return out, errors.New("createChain fields forbidden in conversion")
			}
			if len(p.GenesisSHA256) != 64 || p.EVMChainID < 1000 || p.EVMChainID == 73571 || p.EVMChainID == 1337 || p.EVMChainID == 31337 || p.EVMChainID == 43113 || p.EVMChainID == 43114 || p.EVMChainID > 9007199254740991 {
				return out, errors.New("final genesis hash and distinct EVM chain ID required for conversion")
			}
			if _, e := hex.DecodeString(p.GenesisSHA256); e != nil {
				return out, e
			}
			chain, e := ids.FromString(p.BlockchainID)
			if e != nil || chain == ids.Empty || chain == subnet || p.AcceptedChainTxID != p.BlockchainID {
				return out, errors.New("accepted CreateChain binding required")
			}
			manager, e := rawHex(p.ManagerAddress, 20)
			if e != nil || bytes.Equal(manager, make([]byte, 20)) {
				return out, errors.New("manager address required")
			}
			if len(p.Validators) != 2 {
				return out, errors.New("two explicitly reviewed validators required")
			}
			list := make([]*platform.ConvertSubnetToL1Validator, 0, 2)
			keys := map[string]bool{}
			total := uint64(0)
			for _, v := range p.Validators {
				node, e := ids.NodeIDFromString(v.NodeID)
				if e != nil || node == ids.EmptyNodeID {
					return out, errors.New("invalid NodeID")
				}
				pk, e := rawHex(v.PublicKey, 48)
				if e != nil {
					return out, e
				}
				pop, e := rawHex(v.Proof, 96)
				if e != nil {
					return out, e
				}
				if keys[hex.EncodeToString(pk)] || v.Weight == 0 || v.Balance == 0 {
					return out, errors.New("duplicate BLS key or zero weight/deposit")
				}
				keys[hex.EncodeToString(pk)] = true
				total, e = checkedAdd(total, v.Weight)
				if e != nil {
					return out, e
				}
				deposits, e = checkedAdd(deposits, v.Balance)
				if e != nil {
					return out, e
				}
				remain, e := owner(v.RemainingOwner)
				if e != nil || remain.Locktime != 0 {
					return out, errors.New("explicit unlocked return owner required")
				}
				disable, e := owner(v.DisableOwner)
				if e != nil || disable.Locktime != 0 {
					return out, errors.New("explicit deactivation owner required")
				}
				proof := signer.ProofOfPossession{}
				copy(proof.PublicKey[:], pk)
				copy(proof.ProofOfPossession[:], pop)
				list = append(list, &platform.ConvertSubnetToL1Validator{NodeID: node.Bytes(), Weight: v.Weight, Balance: v.Balance, Signer: proof, RemainingBalanceOwner: message.PChainOwner{Threshold: remain.Threshold, Addresses: remain.Addrs}, DeactivationOwner: message.PChainOwner{Threshold: disable.Threshold, Addresses: disable.Addrs}})
			}
			churn := uint64(p.ManagerChurnPercentage)
			if churn == 0 || churn > 20 || p.ManagerChurnPeriod == 0 || p.ManagerChurnPeriod > 86400 || total > math.MaxUint64/churn || total*churn < 100 {
				return out, errors.New("explicit pinned manager churn initialization bounds")
			}
			tx = &platform.ConvertSubnetToL1Tx{BaseTx: base, Subnet: subnet, ChainID: chain, Address: manager, Validators: list, SubnetAuth: auth}
		}
	default:
		return out, errors.New("one explicit supported transaction required")
	}
	if e := tx.SyntacticVerify(&snow.Context{NetworkID: 1, ChainID: constants.PlatformChainID}); e != nil {
		return out, e
	}
	minFee, e := fee.NewDynamicCalculator(genesis.MainnetParams.DynamicFeeConfig.Weights, gas.Price(p.GasPrice)).CalculateFee(tx)
	if e != nil {
		return out, e
	}
	costs, e := checkedAdd(outSum, deposits)
	if e != nil || inSum < costs {
		return out, errors.New("funding underflow")
	}
	paid := inSum - costs
	spend, e := checkedAdd(paid, deposits)
	if e != nil || paid < minFee || paid > p.MaximumFee || spend > p.MaximumSpend {
		return out, errors.New("fee/deposit budget mismatch")
	}
	raw, e := platform.Codec.Marshal(platform.CodecVersion, &tx)
	if e != nil {
		return out, e
	}
	var decoded platform.UnsignedTx
	if _, e = platform.Codec.Unmarshal(raw, &decoded); e != nil {
		return out, e
	}
	round, e := platform.Codec.Marshal(platform.CodecVersion, &decoded)
	if e != nil || !bytes.Equal(raw, round) {
		return out, errors.New("noncanonical unsigned codec round trip")
	}
	if e = decoded.SyntacticVerify(&snow.Context{NetworkID: 1, ChainID: constants.PlatformChainID}); e != nil {
		return out, e
	}
	planJSON, e := json.Marshal(p)
	if e != nil {
		return out, e
	}
	return Envelope{Operation: p.Operation, NetworkID: 1, AvalancheCommit: AvalancheCommit, UnsignedHex: hex.EncodeToString(raw), UnsignedSHA256: Hash(raw), PlanSHA256: Hash(planJSON), Fee: paid, MinimumFee: minFee, ValidatorDeposits: deposits, SignerRequirements: reqs,
		Limitation: "Unsigned only; snapshot authenticity, UTXO unspent state, subnet ownership, fee-price freshness and execution require separately authenticated current chain evidence; no acceptance or signature approval"}, nil
}

// External signer boundary deliberately has no secret, callback, wallet or execution method.
// The exact unsigned digest, full plan, role indices and budget must be independently
// approved outside this tool. It will not consume even an allegedly approved signature.
func AcceptSignature(_ Envelope, _ []byte) error { return ErrSigningDisabled }

// Public evidence is caller-supplied and digest-bound; authenticity still requires
// independent provenance review. This tool never fetches chain state.
type StateSnapshot struct {
	GenesisSHA256      string         `json:"genesisSha256"`
	EVMChainID         uint64         `json:"evmChainId"`
	NetworkID          uint32         `json:"networkId"`
	AssetID            string         `json:"avaxAssetId"`
	ObservedAt         time.Time      `json:"observedAt"`
	Reference          string         `json:"reference"`
	Inputs             []FundingInput `json:"inputs"`
	SubnetID           string         `json:"subnetId"`
	SubnetOwner        Owners         `json:"subnetOwner"`
	AcceptedSubnetTxID string         `json:"acceptedSubnetTxId"`
	AcceptedChainTxID  string         `json:"acceptedChainTxId"`
	GasPrice           uint64         `json:"gasPriceNanoAvax"`
}

func PrepareWithEvidence(p Plan, raw []byte, now time.Time) (Envelope, error) {
	if Hash(raw) != p.StateEvidenceSHA256 {
		return Envelope{}, errors.New("public state file SHA256 mismatch")
	}
	var s StateSnapshot
	if e := StrictJSON(raw, &s); e != nil {
		return Envelope{}, e
	}
	expected := StateSnapshot{GenesisSHA256: p.GenesisSHA256, EVMChainID: p.EVMChainID, NetworkID: p.NetworkID, AssetID: p.AssetID, ObservedAt: p.ObservedAt, Reference: s.Reference, Inputs: p.Inputs, SubnetID: p.SubnetID, SubnetOwner: p.SubnetOwner, AcceptedSubnetTxID: p.AcceptedSubnetTxID, AcceptedChainTxID: p.AcceptedChainTxID, GasPrice: p.GasPrice}
	a, _ := json.Marshal(s)
	b, _ := json.Marshal(expected)
	if s.Reference == "" || !bytes.Equal(a, b) {
		return Envelope{}, errors.New("public snapshot input/owner/fee/accepted-ID mismatch")
	}
	return Prepare(p, now)
}
