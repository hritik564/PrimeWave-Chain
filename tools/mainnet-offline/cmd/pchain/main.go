package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"

	"os"
	offline "primewave.local/mainnet-offline"
	"time"
)

func main() {
	if err := offline.VerifyBuildPin(); err != nil {
		panic(err)
	}
	input := flag.String("plan", "", "public transaction plan JSON")
	state := flag.String("state-evidence", "", "digest-bound public observed state JSON")
	verify := flag.String("verify-envelope", "", "optional unsigned review envelope to compare; no signature accepted")
	flag.Parse()
	if *input == "" || *state == "" || flag.NArg() != 0 {
		panic("--plan and --state-evidence required; no signing/broadcast modes")
	}
	planRaw, e := os.ReadFile(*input)
	if e != nil || len(planRaw) > 8<<20 {
		panic("public plan missing/too large")
	}
	var p offline.Plan
	if e = offline.StrictJSON(planRaw, &p); e != nil {
		panic(e)
	}
	raw, e := os.ReadFile(*state)
	if e != nil || len(raw) > 8<<20 {
		panic("public snapshot missing/too large")
	}
	r, e := offline.PrepareWithEvidence(p, raw, time.Now().UTC())
	if e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
	b, e := json.MarshalIndent(r, "", "  ")
	if e != nil {
		panic(e)
	}
	if *verify != "" {
		old, e := os.ReadFile(*verify)
		if e != nil {
			panic(e)
		}
		var envelope offline.Envelope
		if e = offline.StrictJSON(old, &envelope); e != nil {
			panic(e)
		}
		x, _ := json.Marshal(envelope)
		y, _ := json.Marshal(r)
		if !bytes.Equal(x, y) {
			panic("unsigned envelope, request digest, budget or signer requirements differ")
		}
	}
	fmt.Println(string(b))
}
