package compiler_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestPreparedSourceCallEligibility(t *testing.T) {
	for _, test := range []struct {
		name, source string
		prepared     bool
	}{
		{"ordered", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int: add(a: 1, b: 2)\n", true},
		{"positional", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int: add(1, 2)\n", true},
		{"mixed ordered", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int: add(1, b: 2)\n", true},
		{"mixed reordered", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int: add(b: 2, 1)\n", true},
		{"single label", "fn value(number: Int) -> Int: number\nfn run() -> Int: value(2)\n", true},
		{"shorthand", "fn add(a: Int, b: Int) -> Int: a + b\nfn run(a: Int, b: Int) -> Int: add(a, b)\n", true},
		{"no arguments", "fn value() -> Int: 2\nfn run() -> Int: value()\n", true},
		{"explicit default", "fn value(number: Int = 2) -> Int: number\nfn run() -> Int: value(3)\n", true},
		{"omitted default", "fn value(number: Int = 2) -> Int: number\nfn run() -> Int: value()\n", false},
		{"reordered", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int: add(b: 2, a: 1)\n", true},
		{"generic", "fn value[T](number: T) -> T: number\nfn run() -> Int: value(2)\n", false},
		{"callback", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int:\n    let callback = add\n    return callback(a: 1, b: 2)\n", false},
		{"native", "import panic from \"@std/faults.ms\"\nfn run() -> Int: panic(\"stop\")\n", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := compiler.CompileSource("calls.ms", test.source, compiler.Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			if got := strings.Contains(result.Source, ".(rt.Function).Body(") || strings.Contains(result.Source, "return symbol1Native("); got != test.prepared {
				t.Fatalf("prepared call = %v, want %v\n%s", got, test.prepared, result.Source)
			}
		})
	}
}
