package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A payload that contradicts an already known type argument yields one
// precise mismatch rather than an additional generic "conflict" diagnostic.
func TestKnownConstructorTypeArgumentReportsOneMismatch(t *testing.T) {
	const prefix = "import Result from \"@std/result.ms\"\n"
	for _, tt := range []struct {
		name, source, want string
		count              int
	}{
		{"expected result", prefix + "fn f() -> Result[Int, String]:\n    return ok(value: \"a\")\n", "expected Int, found String", 1},
		{"earlier argument fixes the type", "type Pair[T]:\n    a: T\n    b: T\nfn f() -> Int:\n    let p = Pair(a: 1, b: \"x\")\n    return 0\n", "expected Int, found String", 1},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("conflict.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != tt.count || !strings.Contains(p.Diagnostics[0].Message, tt.want) {
				t.Fatalf("want one %q, got %v", tt.want, p.Diagnostics)
			}
		})
	}
}
