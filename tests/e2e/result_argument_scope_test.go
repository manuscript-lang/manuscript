package e2e_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// The accepted behavior is testdata/projects/result_argument_scope. Loading both
// implementation modules must not expose either implementation to a raw Cause
// value in the importing module.
func TestResultArgumentInferenceDoesNotLeakLocalErrorScope(t *testing.T) {
	entry := copyProject(t, "testdata/projects/result_argument_scope", "conformance_test.ms", `import erase from "./helper.ms"
fn invalid(r: Result[Int, Cause[Int]]) Result[Int, Error]: erase(r)
`)
	result := compiler.CompileFile(entry, compiler.Options{AnalyzeOnly: true})
	if result.Success() {
		t.Fatal("local Error implementation leaked into importing module")
	}
	for _, diagnostic := range result.Diagnostics {
		if diagnostic.Position.File != "conformance_test.ms" {
			t.Fatalf("failed outside raw use site: %v", result.Diagnostics)
		}
	}
}
