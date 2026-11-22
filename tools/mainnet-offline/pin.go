package offline

import (
	"errors"
	"runtime/debug"
)

// The executable cannot silently use another SDK release or a local replacement.
func VerifyBuildPin() error {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return errors.New("missing Go build provenance")
	}
	for _, m := range info.Deps {
		if m.Path == "github.com/ava-labs/avalanchego" {
			if m.Version != "v1.15.1" || m.Sum != "h1:rHEc0OrOyyh6gHIs4KrKyDm/vw81J0Cc3FDwgCRklgg=" || m.Replace != nil {
				return errors.New("pinned AvalancheGo SDK differs")
			}
			return nil
		}
	}
	return errors.New("AvalancheGo SDK missing from build")
}
