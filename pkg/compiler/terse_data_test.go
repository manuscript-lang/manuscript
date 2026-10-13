package compiler_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestTerseDataRejections(t *testing.T) {
	prefix := `import {Map, List} from "@std/collections.ms"
fn f(first: Int, second: Int) -> Int: return first + second
`
	for _, tc := range []struct{ body, message string }{
		{`let value = {}`, "cannot infer map"},
		{`let value = {"a": 1, "b": true}`, "expected"},
		{`let value = {1: 1, "b": 2}`, "expected"},
		{`let value = {[1]: 2}`, "Hashable"},
		{`let first = 1
    let value = f(first, first: 2, second: 3)`, "duplicate argument first"},
		{`let wrong = true
    let value = f(wrong, second: 2)`, "expected Int, found Bool"},
		{`let first = 1
    let value = f(first + 1, first: 2)`, "duplicate argument first"},
	} {
		t.Run(tc.body, func(t *testing.T) {
			r := compiler.CompileSource("terse.ms", prefix+"fn test_case() -> Unit:\n    "+tc.body+"\n", compiler.Options{})
			if r.Success() {
				t.Fatal("accepted invalid source")
			}
			found := false
			for _, d := range r.Diagnostics {
				found = found || strings.Contains(d.Message, tc.message)
			}
			if !found {
				t.Fatalf("expected %q: %v", tc.message, r.Diagnostics)
			}
		})
	}
	r := compiler.CompileSource("import.ms", "fn f() -> Unit:\n    let value = {1: 2}\n", compiler.Options{})
	if r.Success() || !strings.Contains(r.Diagnostics[0].Message, "canonical Map import") {
		t.Fatal(r.Diagnostics)
	}
}
