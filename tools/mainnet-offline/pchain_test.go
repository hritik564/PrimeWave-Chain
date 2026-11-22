package offline

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/ava-labs/avalanchego/genesis"
	"github.com/ava-labs/avalanchego/ids"
	"github.com/ava-labs/avalanchego/utils/constants"
	"os"
	"sort"
	"strings"
	"testing"
	"time"
)

func testPlan() (Plan, time.Time) {
	now := time.Date(2026, 11, 22, 0, 0, 0, 0, time.UTC)
	o := Owners{Threshold: 1, Addresses: []string{"0x1111111111111111111111111111111111111111"}}
	return Plan{Operation: "createSubnet", NetworkID: 1, AssetID: MainnetAVAX, Inputs: []FundingInput{{TxID: "2wiU5PnFTjTmoAXGZutHAsPF36qGGyLHYHj9G1Aucfmb3JFFGN", OutputIndex: 1, Amount: 1000000000, Owner: o, SignatureIndices: []uint32{0}}}, SubnetOwner: o, GasPrice: uint64(genesis.MainnetParams.DynamicFeeConfig.MinPrice), MaximumFee: 1000000000, MaximumSpend: 1000000000, ObservedAt: now, ExpiresAt: now.Add(time.Minute), StateEvidenceSHA256: strings.Repeat("a", 64)}, now
}
func asChain(p Plan) Plan {
	p.Operation = "createChain"
	p.SubnetID = "SkB92YpWm4UpburLz9tEKZw2i67H3FF6YkjaU4BkFUDTG9Xm"
	p.AcceptedSubnetTxID = p.SubnetID
	p.AuthIndices = []uint32{0}
	p.ChainName = "PrimeWave test only"
	p.VMID = constants.SubnetEVMID.String()
	g := []byte(`{"config":{"chainId":73571001}}`)
	p.EVMChainID = 73571001
	p.GenesisHex = "0x" + hex.EncodeToString(g)
	p.GenesisSHA256 = Hash(g)
	return p
}
func asConvert(t *testing.T, p Plan) Plan {
	t.Helper()
	p = asChain(p)
	p.Operation = "convertSubnet"
	p.GenesisHex = ""
	p.GenesisSHA256 = Hash([]byte("synthetic final genesis binding only"))
	p.VMID = ""
	p.ChainName = ""
	p.BlockchainID = "NfebWJbJMmUpduqFCF8i1m5pstbVYLP1gGHbacrevXZMhpVMy"
	p.AcceptedChainTxID = p.BlockchainID
	p.ManagerAddress = "0x1111111111111111111111111111111111111112"
	p.ManagerChurnPercentage = 20
	p.ManagerChurnPeriod = 3600
	raw, e := os.ReadFile("testdata/public-bls-vectors.json")
	if e != nil {
		t.Fatal(e)
	}
	var v struct {
		Validators []InitialValidator `json:"validators"`
	}
	if e = json.Unmarshal(raw, &v); e != nil {
		t.Fatal(e)
	}
	for _, validator := range v.Validators {
		validator.Weight = 1000
		validator.Balance = 1000
		validator.RemainingOwner = p.SubnetOwner
		validator.DisableOwner = p.SubnetOwner
		p.Validators = append(p.Validators, validator)
	}
	sort.Slice(p.Validators, func(i, j int) bool {
		a, _ := ids.NodeIDFromString(p.Validators[i].NodeID)
		b, _ := ids.NodeIDFromString(p.Validators[j].NodeID)
		return bytes.Compare(a[:], b[:]) < 0
	})
	return p
}
func TestPChainThreeUnsignedCanonicalRoundTrips(t *testing.T) {
	p, now := testPlan()
	for _, plan := range []Plan{p, asChain(p), asConvert(t, p)} {
		t.Run(plan.Operation, func(t *testing.T) {
			a, e := Prepare(plan, now)
			if e != nil {
				t.Fatal(e)
			}
			b, e := Prepare(plan, now)
			if e != nil || a.UnsignedSHA256 != b.UnsignedSHA256 {
				t.Fatal("nondeterministic", e)
			}
			if a.SigningEnabled || a.BroadcastEnabled || a.ApprovalGranted || a.MinimumFee == 0 || len(a.SignerRequirements) == 0 {
				t.Fatal("unsafe envelope")
			}
		})
	}
}
func TestPChainSafetyRefusals(t *testing.T) {
	p, now := testPlan()
	cases := map[string]func(*Plan){"network": func(p *Plan) { p.NetworkID = 5 }, "asset": func(p *Plan) { p.AssetID = p.Inputs[0].TxID }, "expired": func(p *Plan) { p.ExpiresAt = now }, "feeCap": func(p *Plan) { p.MaximumFee = 1 }, "wrongIndices": func(p *Plan) { p.Inputs[0].SignatureIndices = []uint32{1} }, "ownerThreshold": func(p *Plan) { p.SubnetOwner.Threshold = 0 }, "futureId": func(p *Plan) { p.SubnetID = p.Inputs[0].TxID }, "differentOutputOwner": func(p *Plan) {
		p.Outputs = []FundingOutput{{Amount: 1, Owner: Owners{Threshold: 1, Addresses: []string{"0x2222222222222222222222222222222222222222"}}}}
	}}
	for name, change := range cases {
		t.Run(name, func(t *testing.T) {
			raw, _ := json.Marshal(p)
			var copy Plan
			_ = json.Unmarshal(raw, &copy)
			change(&copy)
			if _, e := Prepare(copy, now); e == nil {
				t.Fatal("accepted unsafe plan")
			}
		})
	}
}
func TestPChainExactGenesisAndPriorIDs(t *testing.T) {
	p, now := testPlan()
	p = asChain(p)
	p.GenesisHex += "20"
	if _, e := Prepare(p, now); e == nil {
		t.Fatal("modified bytes accepted")
	}
	p = asChain(p)
	p.AcceptedSubnetTxID = ""
	if _, e := Prepare(p, now); e == nil {
		t.Fatal("missing prior receipt accepted")
	}
}
func TestPChainConversionProofWeightsOwnersAndOrdering(t *testing.T) {
	p, now := testPlan()
	p = asConvert(t, p)
	cases := []func(*Plan){func(p *Plan) { p.Validators[0].Weight = 0 }, func(p *Plan) { p.Validators[0].Proof = "0x" + strings.Repeat("00", 96) }, func(p *Plan) { p.Validators[0].DisableOwner.Threshold = 0 }, func(p *Plan) { p.Validators[0], p.Validators[1] = p.Validators[1], p.Validators[0] }, func(p *Plan) { p.ManagerChurnPercentage = 0 }, func(p *Plan) { p.MaximumSpend = 1 }, func(p *Plan) { p.AcceptedChainTxID = "" }}
	for i, change := range cases {
		raw, _ := json.Marshal(p)
		var copy Plan
		_ = json.Unmarshal(raw, &copy)
		change(&copy)
		if _, e := Prepare(copy, now); e == nil {
			t.Fatalf("unsafe conversion %d", i)
		}
	}
}
func TestPChainPublicSnapshotBinding(t *testing.T) {
	p, now := testPlan()
	s := StateSnapshot{NetworkID: 1, AssetID: MainnetAVAX, ObservedAt: now, Reference: "synthetic-test-only", Inputs: p.Inputs, SubnetOwner: p.SubnetOwner, GasPrice: p.GasPrice}
	raw, _ := json.Marshal(s)
	p.StateEvidenceSHA256 = Hash(raw)
	if _, e := PrepareWithEvidence(p, raw, now); e != nil {
		t.Fatal(e)
	}
	p.GasPrice++
	if _, e := PrepareWithEvidence(p, raw, now); e == nil {
		t.Fatal("fee drift accepted")
	}
}
func TestSigningAlwaysDisabled(t *testing.T) {
	if !errors.Is(AcceptSignature(Envelope{}, []byte("not a signature")), ErrSigningDisabled) {
		t.Fatal("signing not disabled")
	}
}
func TestExactInputsRejectModifiedOrPartialGenesis(t *testing.T) {
	if _, e := ReadExact([]byte(`{}`), []byte(`{}`)); e == nil {
		t.Fatal("missing exact expectations accepted")
	}
}
func TestPChainAmbiguousJSONAndEnabledEnvelopeRefused(t *testing.T) {
	for _, raw := range []string{`{"networkId":1,"networkId":5}`, `{} {}`, `{"privateKey":"never accepted"}`} {
		var plan Plan
		if e := StrictJSON([]byte(raw), &plan); e == nil {
			t.Fatal("ambiguous/nonpublic input accepted")
		}
	}
}
func TestExactInputsRejectDetachedStorageEvenWithMatchingFileHash(t *testing.T) {
	raw := []byte(`{"config":{"chainId":73571001},"alloc":{"0x1111111111111111111111111111111111111111":{"balance":"100000000000000000000000000","code":"0x6000","storage":{"0x00":"0x01"}}}}`)
	expected := map[string]any{"schema": "primewave-exact-genesis-v1", "genesisFileSha256": Hash(raw), "chainId": 73571001, "calls": []any{map[string]string{"to": "test", "data": "0x", "expected": "0x"}}, "accounts": map[string]any{"0x1111111111111111111111111111111111111111": map[string]any{"balance": "100000000000000000000000000", "code": "0x6000", "storage": map[string]string{"0x00": "0x02"}}}}
	b, _ := json.Marshal(expected)
	if _, e := ReadExact(raw, b); e == nil || !strings.Contains(e.Error(), "full genesis account/storage mismatch") {
		t.Fatal("detached storage not rejected", e)
	}
}
