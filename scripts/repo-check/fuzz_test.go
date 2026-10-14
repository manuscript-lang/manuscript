package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestCompilerFuzzDiscovery(t *testing.T) {
	for _, tool := range []string{"make", "sh"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skip("fuzz target requires", tool)
		}
	}
	t.Chdir("../..")
	for _, test := range []struct {
		name, inventory, status string
		success                 bool
	}{
		{"listed", "FuzzCompile\nok package 0.01s\n", "0", true},
		{"missing", "ok package 0.01s\n", "0", false},
		{"failed discovery with partial output", "FuzzCompile\n", "7", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			dir := t.TempDir()
			tool := filepath.Join(dir, "go")
			log := filepath.Join(dir, "fuzz-run")
			mock := `#!/bin/sh
set -eu
case " $* " in
    *' -list '*)
        printf '%s' "$FUZZ_INVENTORY"
        exit "$FUZZ_DISCOVERY_STATUS" ;;
    *' -fuzz ^FuzzCompile$ '*) printf '%s\n' "$*" > "$FUZZ_RUN_LOG" ;;
esac
`
			if err := os.WriteFile(tool, []byte(mock), 0700); err != nil {
				t.Fatal(err)
			}
			// Skip SDK preparation so the real recipe runs against the fake SDK.
			cmd := exec.Command("make", "--no-print-directory", "-o", "payload", "fuzz", "GO="+tool, "FUZZTIME=1x")
			cmd.Env = append(os.Environ(), "FUZZ_INVENTORY="+test.inventory, "FUZZ_DISCOVERY_STATUS="+test.status, "FUZZ_RUN_LOG="+log)
			output, err := cmd.CombinedOutput()
			if (err == nil) != test.success {
				t.Fatalf("success=%v, got %v\n%s", test.success, err, output)
			}
			_, err = os.Stat(log)
			if test.success && err != nil {
				t.Fatal("discovered compiler fuzz target was not executed", err)
			}
			if !test.success && !os.IsNotExist(err) {
				t.Fatal("compiler fuzzing ran after unsuccessful discovery", err)
			}
		})
	}
}
