package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func defaultArgumentDiagnostics(t *testing.T, source string) []syntax.Diagnostic {
	t.Helper()
	m, err := parser.Parse("defaults.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	return checker.Check([]*syntax.Module{m}, nil).Diagnostics
}

func TestDefaultTypeArgumentRules(t *testing.T) {
	cases := []struct{ name, source, want string }{
		{"valid", "type Pair[A, B = A]:\n    first: A\n    second: B\nfn use() -> Pair[Int]: Pair[Int](1, 2)\n", ""},
		{"required after default", "fn f[A = Int, B](value: B) -> B: value\n", "needs a default"},
		{"later parameter", "fn f[A = B, B = Int](value: B) -> B: value\n", "unknown type"},
		{"unmet bound", "interface Named:\n    fn name() -> String\nfn f[T: Named = Int]() -> Unit: unit\n", "implement"},
		{"too few", "type Trio[A, B, C = A]:\n    first: A\nfn use(t: Trio[Int]) -> Unit: unit\n", "takes 2 to 3"},
		{"uninferable required", "fn make[T, U = Int]() -> Optional[T]: none\nfn use() -> Unit:\n    let x = make()\n", "cannot infer type argument T"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			diagnostics := defaultArgumentDiagnostics(t, c.source)
			if c.want == "" {
				if len(diagnostics) != 0 {
					t.Fatal(diagnostics)
				}
				return
			}
			for _, d := range diagnostics {
				if strings.Contains(d.Message, c.want) {
					return
				}
			}
			t.Fatalf("want %q, got %v", c.want, diagnostics)
		})
	}
}
