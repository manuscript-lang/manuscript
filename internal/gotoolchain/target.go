package gotoolchain

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/manuscript-lang/manuscript/internal/gotoolchain/internal/buildcfg"
)

// The target comes from the environment (GOOS, GOARCH, GOAMD64, ...), read
// once by the copied buildcfg package exactly as the tools will read it.

// Supported reports why the copied tools cannot build with goroot for the
// target selected by the environment, or nil when they can. Callers may then
// fall back to an installed go command.
func Supported(goroot string) error {
	if buildcfg.Error != nil {
		return buildcfg.Error
	}
	switch buildcfg.GOARCH {
	case "amd64", "arm64":
	default:
		return fmt.Errorf("built-in Go tools do not support GOARCH=%s", buildcfg.GOARCH)
	}
	if os.Getenv("GOEXPERIMENT") != "" || os.Getenv("GOFLAGS") != "" {
		return errors.New("built-in Go tools require empty GOEXPERIMENT and GOFLAGS")
	}
	if fips := os.Getenv("GOFIPS140"); fips != "" && fips != "off" {
		return errors.New("built-in Go tools do not support GOFIPS140")
	}
	data, err := os.ReadFile(filepath.Join(goroot, "VERSION"))
	if err != nil {
		return err
	}
	version, _, _ := strings.Cut(string(data), "\n")
	if version = strings.TrimSpace(version); version != Version() {
		return fmt.Errorf("SDK %s does not match built-in Go tools %s", version, Version())
	}
	return nil
}

// Environment reports the target settings as go env would, for build pins.
// Variables for other architectures are empty.
func Environment() map[string]string {
	settings := map[string]string{
		"GOVERSION": Version(), "GOOS": buildcfg.GOOS, "GOARCH": buildcfg.GOARCH, "CGO_ENABLED": "0",
		"GOEXPERIMENT": os.Getenv("GOEXPERIMENT"), "GOFLAGS": os.Getenv("GOFLAGS"),
	}
	for _, name := range []string{"GOAMD64", "GOARM", "GOARM64", "GOMIPS", "GOMIPS64", "GOPPC64", "GORISCV64", "GOWASM"} {
		settings[name] = ""
	}
	if name, value := buildcfg.GOGOARCH(); name != "" {
		settings[name] = value
	}
	return settings
}
