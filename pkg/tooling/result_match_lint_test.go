package tooling

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestResultMatchLint(t *testing.T) {
	for _, tc := range []struct {
		name, source string
		want         int
	}{
		{"value", "fn use(value: Result[Int, String]) Int:\n    return match value:\n        ok(n): n\n        error(_): 0\n", 1},
		{"statement", "fn use(value: Result[Int, String]) Int:\n    match value:\n        ok(n): return n\n        error(_): return 0\n", 1},
		{"if let", "fn use(value: Result[Int, String]) Int:\n    if let n = value:\n        return n\n    return 0\n", 0},
		{"get(default)", "fn use(value: Result[Int, String]) Int:\n    return value.get(0)\n", 0},
		{"optional", "fn use(value: Optional[Int]) Int:\n    return match value:\n        some(n): n\n        none: 0\n", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			checked := compiler.CompileSource("result.ms", tc.source, compiler.Options{AnalyzeOnly: true})
			if !checked.Success() {
				t.Fatal(checked.Diagnostics)
			}
			count := 0
			for _, finding := range LintProgram(checked.Program) {
				if finding.Code == "MSL109" {
					count++
				}
			}
			if count != tc.want {
				t.Fatalf("MSL109 findings = %d, want %d", count, tc.want)
			}
		})
	}
}
