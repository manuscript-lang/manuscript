package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// An unknown member is reported once; its placeholder type must not produce
// "callee is not a function" or "found <invalid>" follow-ups.
func TestUnknownMemberReportsOnce(t *testing.T) {
	for _, tt := range []struct{ name, source string }{
		{"method call", "fn f[T](a: T) -> T:\n    return a.foo()\n"},
		{"field read", "fn f() -> Int:\n    let x = 1\n    let y: Int = x.foo\n    return y\n"},
		{"call argument", "fn g(v: Int) -> Int:\n    return v\nfn f() -> Int:\n    let x = 1\n    return g(v: x.foo())\n"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("member.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != 1 || !strings.Contains(p.Diagnostics[0].Message, "unknown or ambiguous member foo") {
				t.Fatalf("want one member diagnostic, got %v", p.Diagnostics)
			}
		})
	}
}
