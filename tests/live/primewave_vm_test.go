package rpcchainvm

import (
 "bytes"
 "context"
 "encoding/hex"
 "encoding/json"
 "fmt"
 "math/big"
 "net/http"
 "net/http/httptest"
 "os"
 "testing"
 "time"

 ethcommon "github.com/ava-labs/libevm/common"
 "github.com/ava-labs/libevm/core/types"
 "github.com/ava-labs/libevm/crypto"
 "github.com/ava-labs/avalanchego/api/metrics"
 "github.com/ava-labs/avalanchego/database/memdb"
 "github.com/ava-labs/avalanchego/ids"
 "github.com/ava-labs/avalanchego/snow"
 "github.com/ava-labs/avalanchego/snow/engine/common"
 "github.com/ava-labs/avalanchego/snow/engine/enginetest"
 "github.com/ava-labs/avalanchego/snow/snowtest"
 "github.com/ava-labs/avalanchego/utils/logging"
 "github.com/ava-labs/avalanchego/vms/rpcchainvm/runtime"
)

type primewaveProcesses struct{}
func (primewaveProcesses) TrackProcess(int) {}
func (primewaveProcesses) UntrackProcess(int) {}
type primewaveRuntimes struct{}
func (primewaveRuntimes) TrackRuntime(runtime.Stopper) {}

// Real released Subnet-EVM process + AvalancheGo's pinned RPCChainVM client.
// No P-Chain, public networking, pre-existing keys or external transactions.
func TestPrimeWaveReleasedVMLive(t *testing.T) {
 ctx,cancel:=context.WithTimeout(context.Background(),90*time.Second);defer cancel()
 t.Setenv("HOME",t.TempDir())
 plugin:=os.Getenv("PRIMEWAVE_VM_BINARY")
 if plugin=="" {t.Fatal("explicit verified VM binary required")}
 factory:=NewFactory(plugin,primewaveProcesses{},primewaveRuntimes{},metrics.NewPrefixGatherer())
 raw,err:=factory.New(logging.NoLog{});if err!=nil {t.Fatal("HANDSHAKE FAILED",err)}
 vm:=raw.(*VMClient)
 defer func(){if err:=vm.Shutdown(context.Background());err!=nil{t.Log("shutdown",err)}}()
 version,err:=vm.Version(ctx);if err!=nil{t.Fatal(err)}
 t.Log("REAL_PLUGIN_HANDSHAKE",version)
 key,err:=crypto.GenerateKey();if err!=nil{t.Fatal(err)} // fresh ephemeral local fixture only
 sender:=crypto.PubkeyToAddress(key.PublicKey)
 chainID:=big.NewInt(73571999) // local test only, never production/Fuji identity
 cfg:=map[string]interface{}{"chainId":chainID.Int64(),"homesteadBlock":0,"eip150Block":0,"eip155Block":0,"eip158Block":0,
 "byzantiumBlock":0,"constantinopleBlock":0,"petersburgBlock":0,"istanbulBlock":0,"muirGlacierBlock":0,
 "subnetEVMTimestamp":0,"durangoTimestamp":0,"etnaTimestamp":0,"fortunaTimestamp":0,"graniteTimestamp":0,
 "feeConfig":map[string]interface{}{"gasLimit":15000000,"targetBlockRate":2,"minBaseFee":1000000000,
 "targetGas":10000000,"baseFeeChangeDenominator":36,"minBlockGasCost":0,"maxBlockGasCost":1000000,"blockGasCostStep":200000}}
 amounts:=[]int64{40000000,15000000,10000000,15000000,5000000,7500000,7500000}
 alloc:=map[string]interface{}{}
 unit:=new(big.Int).Exp(big.NewInt(10),big.NewInt(18),nil)
 for i,amount:=range amounts{
  address:=fmt.Sprintf("%040x",i+100)
  if i==0{address=sender.Hex()[2:]}
  alloc[address]=map[string]interface{}{"balance":"0x"+new(big.Int).Mul(big.NewInt(amount),unit).Text(16)}
 }
 genesis,_:=json.Marshal(map[string]interface{}{"config":cfg,"alloc":alloc,"difficulty":"0x0","gasLimit":"0xe4e1c0","timestamp":"0x0","nonce":"0x0","extraData":"0x"})
 chainCtx:=snowtest.Context(t,ids.GenerateTestID())
 db:=memdb.New()
 senderApp:=&enginetest.Sender{T:t,SendAppGossipF:func(context.Context,common.SendConfig,[]byte)error{return nil}}
 config:=[]byte(`{"eth-apis":["eth","eth-filter","internal-blockchain","net","web3"],"pruning-enabled":true,"state-sync-enabled":false,"allow-unprotected-txs":false}`)
 if err:=vm.Initialize(ctx,chainCtx,db,genesis,nil,config,nil,senderApp);err!=nil{t.Fatal("GENESIS/INITIALIZE FAILED",err)}
 if err:=vm.SetState(ctx,snow.Bootstrapping);err!=nil{t.Fatal(err)}
 if err:=vm.SetState(ctx,snow.NormalOp);err!=nil{t.Fatal(err)}
 handlers,err:=vm.CreateHandlers(ctx);if err!=nil{t.Fatal(err)}
 handler,ok:=handlers["/rpc"];if !ok{t.Fatalf("RPC handler missing: %v",handlers)}
 server:=httptest.NewServer(handler);defer server.Close()
 client:=&http.Client{Timeout:5*time.Second}
 call:=func(method string,params interface{}) json.RawMessage{
  t.Helper();body,_:=json.Marshal(map[string]interface{}{"jsonrpc":"2.0","id":1,"method":method,"params":params})
  response,err:=client.Post(server.URL,"application/json",bytes.NewReader(body));if err!=nil{t.Fatal(err)};defer response.Body.Close()
  var result struct{Result json.RawMessage `json:"result"`;Error json.RawMessage `json:"error"`}
  if err:=json.NewDecoder(response.Body).Decode(&result);err!=nil{t.Fatal(err)}
  if len(result.Error)>0&&string(result.Error)!="null"{t.Fatalf("%s: %s",method,result.Error)}
  if len(result.Result)==0{t.Fatalf("%s: missing result",method)}
  t.Log("RPC",method,string(result.Result));return result.Result
 }
 var chain string;json.Unmarshal(call("eth_chainId",[]interface{}{}),&chain)
 if chain!=fmt.Sprintf("0x%x",chainID.Int64()){t.Fatal("unexpected chainID",chain)}
 call("eth_blockNumber",[]interface{}{})
 call("eth_getBlockByNumber",[]interface{}{"0x0",false})
 var before string;json.Unmarshal(call("eth_getBalance",[]interface{}{sender.Hex(),"latest"}),&before)
 expected:=new(big.Int).Mul(big.NewInt(40000000),unit)
 if before!="0x"+expected.Text(16){t.Fatal("C00 fixture balance mismatch")}
 recipient:=ethcommon.HexToAddress("0x0000000000000000000000000000000000000123")
 tx,err:=types.SignTx(types.NewTransaction(0,recipient,new(big.Int).Set(unit),21000,big.NewInt(25000000000),nil),types.NewEIP155Signer(chainID),key)
 if err!=nil{t.Fatal(err)}
 txBytes,_:=tx.MarshalBinary();call("eth_sendRawTransaction",[]interface{}{"0x"+hex.EncodeToString(txBytes)})
 deadline:=time.Now().Add(15*time.Second)
 for{
  block,err:=vm.BuildBlock(ctx)
  if err==nil{
   if err:=block.Verify(ctx);err!=nil{t.Fatal("VERIFY",err)}
   if err:=vm.SetPreference(ctx,block.ID());err!=nil{t.Fatal(err)}
   if err:=block.Accept(ctx);err!=nil{t.Fatal("ACCEPT",err)}
   t.Log("LOCAL_BLOCK_ACCEPTED",block.Height(),block.ID());break
  }
  if time.Now().After(deadline){t.Fatal("BUILD BLOCK",err)}
  time.Sleep(100*time.Millisecond)
 }
 receipt:=call("eth_getTransactionReceipt",[]interface{}{tx.Hash().Hex()})
 var decoded map[string]interface{};json.Unmarshal(receipt,&decoded)
 if decoded["status"]!="0x1"{t.Fatal("local fixture receipt failed",decoded)}
 var balance string;json.Unmarshal(call("eth_getBalance",[]interface{}{recipient.Hex(),"latest"}),&balance)
 if balance!="0x"+unit.Text(16){t.Fatal("local fixture transfer balance",balance)}
 t.Log("PASS_REAL_VM_HANDSHAKE_C00_SUPPLY_GENESIS_FOUR_RPC_AND_LOCAL_EVM_BLOCK; PCHAIN_BROADCASTS=0")
}
