package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Runaway recursion is a Manuscript fault with a bounded trace, not Go's
// unrecoverable stack overflow.
func TestRunawayRecursionIsAFault(t *testing.T) {
	result := compiler.CompileSource("depth.ms", `fn depth(n: Int) -> Int:
    return 1 + depth(n + 1)
export fn main() -> Int:
    return depth(0)
`, compiler.Options{Entry: true})
	data, err := execute(t, result)
	if err == nil {
		t.Fatalf("expected fault: %s", data)
	}
	text := string(data)
	if !strings.Contains(text, "call depth limit exceeded") {
		t.Fatalf("missing depth fault; transcript:\n%.2000s", text)
	}
	if strings.Contains(text, "fatal error") || strings.Contains(text, "goroutine") {
		t.Fatalf("Go runtime failure leaked; transcript:\n%.2000s", text)
	}
	if lines := strings.Count(text, "\n"); lines > 100 {
		t.Fatalf("trace has %d lines; transcript:\n%.2000s", lines, text)
	}
}

// Recursion deeper than a typical program still runs normally.
func TestDeepRecursionBelowTheLimit(t *testing.T) {
	result := compiler.CompileSource("depth.ms", `fn depth(n: Int, limit: Int) -> Int:
    if n == limit:
        return 0
    return 1 + depth(n: n + 1, limit: limit)
export fn main() -> Int:
    return depth(n: 0, limit: 100000) - 100000
`, compiler.Options{Entry: true})
	if data, err := execute(t, result); err != nil {
		t.Fatalf("deep recursion failed: %v\n%.2000s", err, data)
	}
}
