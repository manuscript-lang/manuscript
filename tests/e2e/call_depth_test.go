package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Runaway recursion is a Manuscript fault with a bounded trace, not Go's
// unrecoverable stack overflow.
func TestRunawayRecursionIsAFault(t *testing.T) {
	result := compiler.CompileSource("depth.ms", `fn depth(n: Int) Int:
    return 1 + depth(n + 1)
export fn main() Int:
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
	if strings.Contains(text, "generated.go") || !strings.Contains(text, "\n  at depth.ms:") {
		t.Fatalf("frames must name source positions only; transcript:\n%.2000s", text)
	}
	if lines := strings.Count(text, "\n"); lines > 100 {
		t.Fatalf("trace has %d lines; transcript:\n%.2000s", lines, text)
	}
}
