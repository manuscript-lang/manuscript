package compiler_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// These pairs pin eligibility as well as cancellation behavior: dynamic starts
// retain a tick because keeping their initial value regressed throughput.
func TestLiteralCounterPollingEligibility(t *testing.T) {
	for _, tc := range []struct {
		name, prefix, body string
		ticks              int
	}{
		{"zero", "var i = 0", "i += 1", 0},
		{"negative", "var i = -137", "i += 1", 0},
		{"unrelated literal", "var i = 0\n    var unrelated = 7", "i += 1", 0},
		{"parameter", "var i = start", "i += 1", 1},
		{"nonliteral reset", "var i = 0\n    i = start", "i += 1", 1},
		{"conditional write", "var i = 0\n    if flag:\n        i = 5", "i += 1", 1},
		{"match write", "var i = 0\n    let captured = match some(0):\n        some(n):\n            i = start\n            n\n        none: 0", "i += 1", 1},
		{"latest literal reset", "var i = start\n    i = 5", "i += 1", 0},
		{"prior loop", "var i = 0\n    while i < 3:\n        i += 1", "i += 1", 1},
		{"reset after step", "var i = 0", "i += 1\n        if flag:\n            i = 0", 1},
		{"continue before step", "var i = 0", "if flag:\n            continue\n        i += 1", 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := "fn probe(start: Int, flag: Bool) Unit:\n    " + tc.prefix +
				"\n    while i < 1000:\n        " + tc.body + "\n"
			r := compiler.CompileSource("poll.ms", source, compiler.Options{})
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			if got := strings.Count(r.Source, "uint32"); got != tc.ticks {
				t.Fatalf("got %d polling ticks, want %d:\n%s", got, tc.ticks, r.Source)
			}
		})
	}
	r := compiler.CompileSource("nested.ms", `fn probe(flag: Bool) Unit:
    var i = 0
    if flag:
        while i < 1000:
            i += 1
`, compiler.Options{})
	if !r.Success() || strings.Count(r.Source, "uint32") != 1 {
		t.Fatalf("enclosing-body facts crossed a branch: %v\n%s", r.Diagnostics, r.Source)
	}
	r = compiler.CompileSource("down.ms", `fn probe() Unit:
    var i = 137
    while i > 0:
        i -= 1
`, compiler.Options{})
	if !r.Success() || strings.Contains(r.Source, "uint32") {
		t.Fatalf("descending literal counter retained a tick: %v\n%s", r.Diagnostics, r.Source)
	}
}
