package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// An unknown receiver or interface in an impl header is reported once; it must
// not also be called a non-nominal receiver or a non-interface target.
func TestImplUnknownTypeReportsOnce(t *testing.T) {
	for _, tt := range []struct{ name, source string }{
		{"receiver", "interface I:\n    fn m() Int\nimpl I for Missing:\n    fn m() Int: return 1\n"},
		{"interface", "type S:\n    x: Int\nimpl Missing for S:\n    fn m() Int: return 1\n"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("impl.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != 1 || !strings.Contains(p.Diagnostics[0].Message, "unknown type Missing") {
				t.Fatalf("want one unknown-type diagnostic, got %v", p.Diagnostics)
			}
		})
	}
}
