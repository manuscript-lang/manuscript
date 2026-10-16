package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Operands whose own diagnostic was already reported must not produce a second
// operator diagnostic that merely restates the failure.
func TestInvalidOperandsReportOnce(t *testing.T) {
	for _, tt := range []struct{ name, source string }{
		{"arithmetic", "fn f() -> Int:\n    let x = nope\n    return x + x\n"},
		{"constant arithmetic", "let X = nope\nlet Y = X + X\n"},
		{"logical", "fn f() -> Bool:\n    let x = nope\n    return x and x\n"},
		{"interpolated text", "fn f() -> String:\n    let x = nope\n    return \"a\" + x.foo + x.bar()\n"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("operand.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != 1 || !strings.Contains(p.Diagnostics[0].Message, "unknown binding nope") {
				t.Fatalf("want one unknown-binding diagnostic, got %v", p.Diagnostics)
			}
		})
	}
}
