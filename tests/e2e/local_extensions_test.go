package e2e_test

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/compiler"
)

func TestLocalInterfaceExtensions(t *testing.T) {
	result := compiler.CompileFile("testdata/projects/local_extensions/main.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "extensions")
	if err := compiler.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	output, err := exec.Command(binary).CombinedOutput()
	if err != nil || !strings.Contains(string(output), "6 tests, 0 failed") {
		t.Fatalf("local extension execution: %v\n%s", err, output)
	}
}
