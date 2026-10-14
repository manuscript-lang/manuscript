package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A repeated parameter name is reported once, not again as a duplicate local.
func TestDuplicateParameterReportsOnce(t *testing.T) {
	for _, tt := range []struct{ name, source string }{
		{"function", "fn f(a: Int, a: Int) -> Int:\n    return a\n"},
		{"callback", "fn f() -> Int:\n    let g = fn(a: Int, a: Int) -> Int: return a\n    return 1\n"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("dup.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != 1 || !strings.Contains(p.Diagnostics[0].Message, "duplicate parameter or field a") {
				t.Fatalf("want one duplicate-parameter diagnostic, got %v", p.Diagnostics)
			}
		})
	}
}
