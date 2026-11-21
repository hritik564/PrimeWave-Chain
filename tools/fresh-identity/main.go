// Build inside the pinned AvalancheGo v1.15.1 source tree. No existing key reads.
package main
import (
 "crypto/sha256"
 "encoding/json"
 "encoding/pem"
 "flag"
 "fmt"
 "os"
 "path/filepath"
 "github.com/ava-labs/avalanchego/ids"
 "github.com/ava-labs/avalanchego/staking"
 "github.com/ava-labs/avalanchego/utils/crypto/bls/signer/localsigner"
 "github.com/ava-labs/avalanchego/vms/platformvm/signer"
)
func run() error {
 out:=flag.String("out","","new identity directory, never an existing path")
 purpose:=flag.String("purpose","","fuji-rehearsal or mainnet-pilot")
 approval:=flag.Bool("approve-identity-creation",false,"explicit operator authorization")
 flag.Parse()
 if !*approval||(*purpose!="fuji-rehearsal"&&*purpose!="mainnet-pilot")||!filepath.IsAbs(*out){return fmt.Errorf("explicit purpose, absolute new output and approval required")}
 // Refuse symlink ancestors and old identities; never overwrite/rotate implicitly.
 for p:=filepath.Dir(*out);;p=filepath.Dir(p){s,err:=os.Lstat(p);if err!=nil{return err};if s.Mode()&os.ModeSymlink!=0{return fmt.Errorf("symlink refused")};if filepath.Dir(p)==p{break}}
 if err:=os.Mkdir(*out,0700);err!=nil{return err}
 cert,key,err:=staking.NewCertAndKeyBytes();if err!=nil{return err}
 secret,err:=localsigner.New();if err!=nil{return err}
 proof,err:=signer.NewProofOfPossession(secret);if err!=nil{return err};if err:=proof.Verify();err!=nil{return err}
 block,_:=pem.Decode(cert);if block==nil{return fmt.Errorf("invalid generated public certificate")}
 parsed,err:=staking.ParseCertificate(block.Bytes);if err!=nil{return err}
 digest:=sha256.Sum256(cert)
 record:=map[string]interface{}{"purpose":*purpose,"nodeId":ids.NodeIDFromCert(parsed).String(),
  "blsPublicKey":fmt.Sprintf("0x%x",proof.PublicKey),"proofOfPossession":fmt.Sprintf("0x%x",proof.ProofOfPossession),
  "stakingCertificateSha256":fmt.Sprintf("%x",digest),"freshCeremonyIdentity":true,"environment":"mainnet"}
 if *purpose=="fuji-rehearsal"{record["environment"]="fuji";record["freshTestIdentity"]=true}
 public,_:=json.MarshalIndent(record,"","  ")
 for name,data:=range map[string][]byte{"staker.crt":cert,"staker.key":key,"signer.key":secret.ToBytes(),"public-identity.json":append(public,'\n')}{
  f,err:=os.OpenFile(filepath.Join(*out,name),os.O_WRONLY|os.O_CREATE|os.O_EXCL,0600);if err!=nil{return err}
  _,err=f.Write(data);f.Close();if err!=nil{return err}
 }
 fmt.Println(string(public));return nil
}
func main(){if err:=run();err!=nil{fmt.Fprintln(os.Stderr,"Fresh identity creation refused/failed; preserve partial state and never retry over it.");os.Exit(1)}}
