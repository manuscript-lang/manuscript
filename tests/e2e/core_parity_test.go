package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestCoreParityScopedImplementations(t *testing.T) {
	result := compiler.CompileFile("testdata/projects/core_parity/main.ms", compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(data)), "4 tests, 0 failed") {
		t.Fatalf("scoped core parity: %v\n%s", err, data)
	}
}
