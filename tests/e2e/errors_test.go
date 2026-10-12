package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestErrorBoundariesPreserveLocalImplementations(t *testing.T) {
	result := compiler.CompileFile("testdata/projects/error_boundaries/main.ms", compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
		t.Fatalf("error boundary execution: %v\n%s", err, output)
	}
}
