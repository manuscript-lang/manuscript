package e2e

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestConstantDiagnostics(t *testing.T) {
	for _, tt := range []struct{ name, source, want string }{
		{"call", "fn f() Int:\n    return 1\nlet X = f()\n", "a constant takes literals, operators, collections, and other constants"},
		{"function reference", "fn f() Int:\n    return 1\nlet X = f\n", "a constant can refer only to other constants, but f is a function"},
		{"cycle", "let A = B\nlet B = A\n", "constant A depends on itself"},
		{"self cycle", "let A = A + 1\n", "constant A depends on itself"},
		{"annotated cycle", "let A: Int = B + 1\nlet B: Int = A + 1\n", "constant A depends on itself"},
		{"annotated self cycle", "let A: Int = A\n", "constant A depends on itself"},
		{"written call", "let A = 1\nfn f() Int:\n    return A()\n", "A is a constant, not a function; remove the parentheses"},
		{"assignment", "let A = 1\nfn f() Int:\n    A = 2\n    return A\n", "cannot assign to constant A"},
		{"annotation mismatch", "let A: Int = \"x\"\n", "expected Int, found String"},
		{"duplicate", "let A = 1\nlet A = 2\n", "duplicate or intrinsic name A"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			result := compiler.CompileSource("constants.ms", tt.source, compiler.Options{})
			var messages []string
			for _, d := range result.Diagnostics {
				messages = append(messages, d.Message)
			}
			if joined := strings.Join(messages, "\n"); !strings.Contains(joined, tt.want) {
				t.Fatalf("want %q, got %q", tt.want, joined)
			}
		})
	}
}

func TestConstantMainIsRejectedAsEntry(t *testing.T) {
	result := compiler.CompileSource("main.ms", "export let main = 0\n", compiler.Options{Entry: true})
	if len(result.Diagnostics) == 0 || !strings.Contains(result.Diagnostics[0].Message, "main is a constant") {
		t.Fatalf("got %v", result.Diagnostics)
	}
}
