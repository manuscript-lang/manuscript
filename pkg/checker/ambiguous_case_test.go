package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// An ambiguous unqualified case is reported once; it must not also be
// reported as an unknown binding.
func TestAmbiguousCaseReportsOnce(t *testing.T) {
	for _, tt := range []struct{ name, source string }{
		{"nullary value", "type A:\n    case X\ntype B:\n    case X\nfn f() Int:\n    let a = X\n    return 1\n"},
		{"constructor call", "type A:\n    case X(n: Int)\ntype B:\n    case X(n: Int)\nfn f() Int:\n    let a = X(n: 1)\n    return 1\n"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("ambiguous.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != 1 || !strings.Contains(p.Diagnostics[0].Message, "ambiguous alternative case X") {
				t.Fatalf("want one ambiguity diagnostic, got %v", p.Diagnostics)
			}
		})
	}
}
