package e2e_test

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestListSnapshotsStandalone(t *testing.T) {
	result := compiler.CompileFile("testdata/accept/list-snapshots.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	source, err := compiler.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "snapshots")
	if err := compiler.Build(source, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := commandOutput(t, binary); err != nil || !strings.Contains(string(output), "4 tests, 0 failed") {
		t.Fatalf("standalone snapshot/interop cases: %v\n%s", err, output)
	}
}
