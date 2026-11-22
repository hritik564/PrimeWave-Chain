package offline

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/ava-labs/avalanchego/api/metrics"
	"github.com/ava-labs/avalanchego/chains/atomic"
	"github.com/ava-labs/avalanchego/database/memdb"
	"github.com/ava-labs/avalanchego/ids"
	"github.com/ava-labs/avalanchego/snow"
	"github.com/ava-labs/avalanchego/snow/engine/common"
	"github.com/ava-labs/avalanchego/snow/engine/enginetest"
	"github.com/ava-labs/avalanchego/snow/validators"
	"github.com/ava-labs/avalanchego/snow/validators/validatorstest"
	"github.com/ava-labs/avalanchego/upgrade"
	"github.com/ava-labs/avalanchego/utils/crypto/bls"
	"github.com/ava-labs/avalanchego/utils/logging"
	"github.com/ava-labs/avalanchego/vms/platformvm/warp"
	"github.com/ava-labs/avalanchego/vms/rpcchainvm"
	"github.com/ava-labs/avalanchego/vms/rpcchainvm/runtime"
)

type exactProcessTracker struct{}

func (exactProcessTracker) TrackProcess(int)   {}
func (exactProcessTracker) UntrackProcess(int) {}

type exactRuntimeTracker struct{}

func (exactRuntimeTracker) TrackRuntime(runtime.Stopper) {}

type refuseWarpSigning struct{}

func (refuseWarpSigning) Sign(*warp.UnsignedMessage) ([]byte, error) { return nil, ErrSigningDisabled }

type ExactExpectations struct {
	Schema            string `json:"schema"`
	GenesisFileSHA256 string `json:"genesisFileSha256"`
	ChainID           uint64 `json:"chainId"`
	SubnetID          string `json:"subnetId"`
	Accounts          map[string]struct {
		Code    string            `json:"code"`
		Balance string            `json:"balance"`
		Nonce   string            `json:"nonce"`
		Storage map[string]string `json:"storage"`
	} `json:"accounts"`
	Calls []struct {
		To       string `json:"to"`
		Data     string `json:"data"`
		Expected string `json:"expected"`
	} `json:"calls"`
	PublicNodeIdentity struct {
		NodeID       string `json:"nodeId"`
		BLSPublicKey string `json:"blsPublicKey"`
	} `json:"publicNodeIdentity"`
}

func ReadExact(genesisBytes, expectedBytes []byte) (ExactExpectations, error) {
	var x ExactExpectations
	if e := CheckJSON(genesisBytes); e != nil {
		return x, e
	}
	if e := CheckJSON(expectedBytes); e != nil {
		return x, e
	}
	if e := json.Unmarshal(expectedBytes, &x); e != nil {
		return x, e
	}
	if x.Schema != "primewave-exact-genesis-v1" || x.GenesisFileSHA256 != Hash(genesisBytes) || len(x.Accounts) == 0 || len(x.Calls) == 0 {
		return x, errors.New("exact file digest/accounts/role calls required")
	}
	var g struct {
		Config struct {
			ChainID uint64 `json:"chainId"`
		} `json:"config"`
		Alloc json.RawMessage `json:"alloc"`
	}
	if e := json.Unmarshal(genesisBytes, &g); e != nil {
		return x, e
	}
	if g.Config.ChainID != x.ChainID || x.ChainID < 1000 {
		return x, errors.New("chain ID mismatch")
	}
	// Require every account and every storage slot, no subset expectation permitted.
	var alloc map[string]json.RawMessage
	if e := json.Unmarshal(g.Alloc, &alloc); e != nil {
		return x, e
	}
	total := new(big.Int)
	for _, state := range x.Accounts {
		n, ok := new(big.Int).SetString(state.Balance, 0)
		if !ok || n.Sign() < 0 {
			return x, errors.New("invalid balance")
		}
		total.Add(total, n)
	}
	supply := new(big.Int).Mul(big.NewInt(100000000), new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil))
	if total.Cmp(supply) != 0 {
		return x, errors.New("fixed100M PW required")
	}
	canonicalAccounts, _ := json.Marshal(x.Accounts)
	var expanded map[string]any
	_ = json.Unmarshal(canonicalAccounts, &expanded)
	if len(alloc) != len(expanded) {
		return x, errors.New("complete account expectation required")
	}
	for a, v := range alloc {
		var state struct {
			Code    string            `json:"code"`
			Balance string            `json:"balance"`
			Nonce   string            `json:"nonce"`
			Storage map[string]string `json:"storage"`
		}
		if e := json.Unmarshal(v, &state); e != nil {
			return x, e
		}
		other, ok := x.Accounts[a]
		if !ok {
			return x, errors.New("account mismatch")
		}
		b1, _ := json.Marshal(state)
		b2, _ := json.Marshal(other)
		if !bytes.Equal(b1, b2) {
			return x, errors.New("full genesis account/storage mismatch")
		}
	}
	if _, e := ids.FromString(x.SubnetID); e != nil {
		return x, e
	}
	if _, e := ids.NodeIDFromString(x.PublicNodeIdentity.NodeID); e != nil {
		return x, e
	}
	pk, e := rawHex(x.PublicNodeIdentity.BLSPublicKey, 48)
	if e != nil {
		return x, e
	}
	if _, e = bls.PublicKeyFromCompressedBytes(pk); e != nil {
		return x, e
	}
	return x, nil
}

// Explicit environment paths only; no fixture fallback, keys, transactions, blocks,
// public-network client or daemon. Genesis bytes reach Initialize unchanged.
func TestExactGenesisWhenSupplied(t *testing.T) {
	path := os.Getenv("PRIMEWAVE_EXACT_GENESIS")
	if path == "" {
		t.Skip("explicit exact-genesis input not supplied")
	}
	expectedPath := os.Getenv("PRIMEWAVE_EXACT_EXPECTATIONS")
	plugin := os.Getenv("PRIMEWAVE_EXACT_VM_BINARY")
	raw, e := os.ReadFile(path)
	if e != nil {
		t.Fatal(e)
	}
	expect, e := os.ReadFile(expectedPath)
	if e != nil {
		t.Fatal(e)
	}
	x, e := ReadExact(raw, expect)
	if e != nil {
		t.Fatal(e)
	}
	pluginBytes, e := os.ReadFile(plugin)
	if e != nil || Hash(pluginBytes) != os.Getenv("PRIMEWAVE_EXACT_VM_SHA256") {
		t.Fatal("verified pinned plugin required", e)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	t.Setenv("HOME", t.TempDir())
	factory := rpcchainvm.NewFactory(plugin, exactProcessTracker{}, exactRuntimeTracker{}, metrics.NewPrefixGatherer())
	instance, e := factory.New(logging.NoLog{})
	if e != nil {
		t.Fatal("protocol46 handshake", e)
	}
	vm := instance.(*rpcchainvm.VMClient)
	defer func() { _ = vm.Shutdown(context.Background()) }()
	version, e := vm.Version(ctx)
	if e != nil {
		t.Fatal(e)
	}
	t.Log("PINNED_VM", version)
	subnet, _ := ids.FromString(x.SubnetID)
	node, _ := ids.NodeIDFromString(x.PublicNodeIdentity.NodeID)
	pkBytes, _ := rawHex(x.PublicNodeIdentity.BLSPublicKey, 48)
	pk, _ := bls.PublicKeyFromCompressedBytes(pkBytes)
	// Local deterministic context ID is not an asserted production BlockchainID.
	var chain ids.ID
	hashBytes, _ := hex.DecodeString(Hash(raw))
	copy(chain[:], hashBytes)
	aliaser := ids.NewAliaser()
	_ = aliaser.Alias(chain, chain.String())
	state := &validatorstest.State{GetMinimumHeightF: func(context.Context) (uint64, error) { return 0, nil }, GetCurrentHeightF: func(context.Context) (uint64, error) { return 0, nil }, GetSubnetIDF: func(context.Context, ids.ID) (ids.ID, error) { return subnet, nil }, GetCurrentValidatorSetF: func(context.Context, ids.ID) (map[ids.ID]*validators.GetCurrentValidatorOutput, uint64, error) {
		return map[ids.ID]*validators.GetCurrentValidatorOutput{}, 0, nil
	}}
	asset, _ := ids.FromString(MainnetAVAX)
	chainCtx := &snow.Context{NetworkID: 1, SubnetID: subnet, ChainID: chain, NodeID: node, PublicKey: pk, NetworkUpgrades: upgrade.GetConfig(1), AVAXAssetID: asset, Log: logging.NoLog{}, SharedMemory: atomic.NewMemory(memdb.New()).NewSharedMemory(chain), BCLookup: aliaser, Metrics: metrics.NewPrefixGatherer(), WarpSigner: refuseWarpSigning{}, ValidatorState: state, ChainDataDir: t.TempDir()}
	sender := &enginetest.Sender{T: t, SendAppGossipF: func(context.Context, common.SendConfig, []byte) error { return errors.New("public gossip disabled") }}
	config := []byte(`{"eth-apis":["eth","eth-filter","internal-blockchain","internal-transaction","net","web3"],"state-sync-enabled":false,"pruning-enabled":false}`)
	// NEVER json.Marshal or reconstruct raw. Fresh isolated in-memory database only.
	if e = vm.Initialize(ctx, chainCtx, memdb.New(), raw, nil, config, nil, sender); e != nil {
		t.Fatal("EXACT_GENESIS_REJECTED", e)
	}
	if e = vm.SetState(ctx, snow.Bootstrapping); e != nil {
		t.Fatal(e)
	}
	if e = vm.SetState(ctx, snow.NormalOp); e != nil {
		t.Fatal(e)
	}
	handlers, e := vm.CreateHandlers(ctx)
	if e != nil {
		t.Fatal(e)
	}
	handler, ok := handlers["/rpc"]
	if !ok {
		t.Fatal("missing RPC")
	}
	server := httptest.NewServer(handler)
	defer server.Close() // Go binds127.0.0.1:0 only
	client := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{Proxy: nil}, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("redirect forbidden") }}
	call := func(method string, params any) string {
		t.Helper()
		if method != "eth_chainId" && method != "eth_getCode" && method != "eth_getStorageAt" && method != "eth_getBalance" && method != "eth_getTransactionCount" && method != "eth_call" {
			t.Fatal("forbidden RPC")
		}
		body, _ := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
		response, e := client.Post(server.URL, "application/json", bytes.NewReader(body))
		if e != nil {
			t.Fatal(e)
		}
		defer response.Body.Close()
		var result struct {
			Result string          `json:"result"`
			Error  json.RawMessage `json:"error"`
		}
		if e = json.NewDecoder(io.LimitReader(response.Body, 16<<20)).Decode(&result); e != nil {
			t.Fatal(e)
		}
		if len(result.Error) > 0 && string(result.Error) != "null" {
			t.Fatal(method, string(result.Error))
		}
		return result.Result
	}
	if got := call("eth_chainId", []any{}); got != fmt.Sprintf("0x%x", x.ChainID) {
		t.Fatal("chainId", got)
	}
	quantity := func(s string) *big.Int {
		t.Helper()
		if s == "" {
			return new(big.Int)
		}
		n, ok := new(big.Int).SetString(s, 0)
		if !ok {
			t.Fatal("quantity", s)
		}
		return n
	}
	for a, v := range x.Accounts {
		expectedCode := v.Code
		if expectedCode == "" {
			expectedCode = "0x"
		}
		if got := call("eth_getCode", []any{a, "0x0"}); got != expectedCode {
			t.Fatal("code", a)
		}
		if quantity(call("eth_getBalance", []any{a, "0x0"})).Cmp(quantity(v.Balance)) != 0 {
			t.Fatal("balance", a)
		}
		if quantity(call("eth_getTransactionCount", []any{a, "0x0"})).Cmp(quantity(v.Nonce)) != 0 {
			t.Fatal("nonce", a)
		}
		for slot, value := range v.Storage {
			if quantity(call("eth_getStorageAt", []any{a, slot, "0x0"})).Cmp(quantity(value)) != 0 {
				t.Fatal("storage", a, slot)
			}
		}
	}
	for _, c := range x.Calls {
		if got := call("eth_call", []any{map[string]string{"to": c.To, "data": c.Data}, "0x0"}); got != c.Expected {
			t.Fatal("ownership/state getter", c.To, c.Data, got, c.Expected)
		}
	}
	after, e := os.ReadFile(path)
	if e != nil || !bytes.Equal(after, raw) {
		t.Fatal("input changed during validation")
	}
	t.Log("PASS_EXACT_GENESIS_IMPORT", Hash(raw), "accounts", len(x.Accounts), "no signing/broadcast/consensus proof")
}
