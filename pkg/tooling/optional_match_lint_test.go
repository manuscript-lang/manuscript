package tooling

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestOptionalMatchLint(t *testing.T) {
	for _, tc := range []struct {
		name, source string
		want         int
	}{
		{"statement", "fn use(value: Optional[Int]) -> Int:\n    match value:\n    some(n): return n\n    none: return 0\n", 1},
		{"value", "fn use(value: Optional[Int]) -> Int:\n    return match value:\n    some(n): n\n    none: 0\n", 1},
		{"if let", "fn use(value: Optional[Int]) -> Int:\n    if let n = value:\n        return n\n    return 0\n", 0},
		{"result", "fn use(value: Result[Int, String]) -> Int:\n    return match value:\n    ok(n): n\n    error(_): 0\n", 0},
		{"alternative", "type Shape:\n    case Dot\n    case Line\nfn use(value: Shape) -> Int:\n    return match value:\n    Dot: 0\n    Line: 1\n", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			checked := compiler.CompileSource("optional.ms", tc.source, compiler.Options{AnalyzeOnly: true})
			if !checked.Success() {
				t.Fatal(checked.Diagnostics)
			}
			count := 0
			for _, finding := range LintProgram(checked.Program) {
				if finding.Code == "MSL108" {
					count++
				}
			}
			if count != tc.want {
				t.Fatalf("MSL108 findings = %d, want %d", count, tc.want)
			}
		})
	}
}
