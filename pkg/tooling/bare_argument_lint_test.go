package tooling

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestBareArgumentLint(t *testing.T) {
	const prelude = "type Pair:\n    left: Int\n    right: Int\nfn subtract(left: Int, right: Int) -> Int:\n    return left - right\nfn one(value: Int) -> Int:\n    return value\n"
	for _, tc := range []struct {
		name, body string
		want       int
	}{
		{"redirected", "let right = 10\n    let amount = 3\n    return subtract(right, amount)", 1},
		{"parenthesized", "let right = 10\n    let amount = 3\n    return subtract((right), amount)", 0},
		{"labeled", "let right = 10\n    let amount = 3\n    return subtract(left: right, right: amount)", 0},
		{"explicit shorthand", "let right = 10\n    let amount = 3\n    return subtract(right: right, left: amount)", 0},
		{"matching slot", "let left = 10\n    let amount = 3\n    return subtract(left, amount)", 0},
		{"unrelated names", "let a = 10\n    let b = 3\n    return subtract(a, b)", 0},
		{"single parameter", "let value = 3\n    return one(value)", 0},
		{"constructor", "let right = 10\n    let amount = 3\n    let pair = Pair(right, amount)\n    return pair.left", 1},
		{"function value", "let right = 10\n    let amount = 3\n    let f = subtract\n    return f(right, amount)", 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := prelude + "fn use() -> Int:\n    " + tc.body + "\n"
			checked := compiler.CompileSource("bare.ms", source, compiler.Options{AnalyzeOnly: true})
			if !checked.Success() {
				t.Fatal(checked.Diagnostics)
			}
			got := 0
			for _, finding := range LintProgram(checked.Program) {
				if finding.Code != "MSL109" {
					continue
				}
				got++
				if !strings.HasPrefix(source[finding.Position.Offset:], "right") || !strings.Contains(finding.Message, "left: right") || !strings.Contains(finding.Message, "(right)") || !strings.Contains(finding.Message, "right: right") {
					t.Fatalf("wrong finding: %+v", finding)
				}
			}
			if got != tc.want {
				t.Fatalf("got %d MSL109 findings, want %d", got, tc.want)
			}
		})
	}
}
