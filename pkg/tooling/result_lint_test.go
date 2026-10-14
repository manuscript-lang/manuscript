package tooling

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestDiscardedResultLint(t *testing.T) {
	const operation = "fn operation() -> Result[Int, String]: ok(1)\n"
	for _, tc := range []struct {
		name, source string
		want         int
	}{
		{"call", operation + "fn caller() -> Unit:\n    operation()\n", 1},
		{"explicit standard import", "import Result from \"@std/result.ms\"\n" + operation + "fn caller() -> Unit:\n    operation()\n", 1},
		{"unit result", "fn operation() -> Result[Unit, String]: ok(unit)\nfn caller() -> Unit:\n    operation()\n", 1},
		{"nested closure", operation + "fn caller() -> Unit:\n    let callback = fn() -> Unit:\n        if true:\n            operation()\n    callback()\n", 1},
		{"match value", operation + "fn caller() -> Unit:\n    match operation():\n        ok(value): operation()\n        error(cause): operation()\n", 1},
		{"bound and returned", operation + "fn caller() -> Result[Int, String]:\n    let value = operation()\n    return value\n", 0},
		{"argument consumed", operation + "fn consume(value: Result[Int, String]) -> Unit: unit\nfn caller() -> Unit:\n    consume(operation())\n", 0},
		{"returned match", operation + "fn caller() -> Result[Int, String]:\n    return match operation():\n        ok(value): operation()\n        error(cause): operation()\n", 0},
		{"discard in match arm body", operation + "fn caller() -> Result[Int, String]:\n    return match operation():\n        ok(value):\n            operation()\n            operation()\n        error(cause): operation()\n", 1},
		{"explicit discard", operation + "fn caller() -> Unit:\n    let _ignored = operation()\n", 0},
		{"propagate unit", "fn operation() -> Result[Unit, String]: ok(unit)\nfn caller() -> Result[Int, String]:\n    try operation()\n    return ok(1)\n", 0},
		{"inline return", operation + "fn caller() -> Result[Int, String]: operation()\n", 0},
		{"ordinary value", "fn operation() -> Int: 1\nfn caller() -> Unit:\n    operation()\n", 0},
		{"local Result identity", "type Result:\n    value: Int\nfn caller() -> Unit:\n    Result(1)\n", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			checked := compiler.CompileSource("result.ms", tc.source, compiler.Options{AnalyzeOnly: true})
			if !checked.Success() {
				t.Fatal(checked.Diagnostics)
			}
			findings := LintProgram(checked.Program)
			count := 0
			for _, finding := range findings {
				if finding.Code == "MSL104" {
					count++
					if finding.Position.File != "result.ms" || finding.Position.Line < 2 || finding.Position.Column < 5 || !strings.Contains(finding.Message, "_ignored") {
						t.Fatalf("unexpected diagnostic: %+v", finding)
					}
					if tc.name == "call" && (finding.Position.Line != 3 || finding.Position.Column != 5 || finding.Position.Offset != strings.LastIndex(tc.source, "operation()")) {
						t.Fatalf("discarded call position is not its source location: %+v", finding.Position)
					}
				}
			}
			if count != tc.want {
				t.Fatalf("got %d discarded Result findings, want %d: %+v", count, tc.want, findings)
			}
			if tc.name == "explicit discard" && len(findings) != 0 {
				t.Fatalf("intentional discard should not report unread binding: %+v", findings)
			}
		})
	}
}
