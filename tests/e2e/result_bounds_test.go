package e2e_test

import (
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"path/filepath"
	"strings"
	"testing"
)

func TestSuccessfulResultBoundsStandalone(t *testing.T) {
	result := compiler.CompileFile("testdata/accept/successful-result-int-bounds.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if !strings.Contains(result.Source, "sum = sum + found") || !strings.Contains(result.Source, "rt.IntAdd(n, int(1))") {
		t.Fatal("fixture must remove only the bounded caller check")
	}
	source, err := build.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "result-bounds")
	if err := build.Build(source, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := commandOutput(t, binary); err != nil || !strings.Contains(string(output), "5 tests, 0 failed") {
		t.Fatalf("standalone Result bounds: %v\n%s", err, output)
	}
}
