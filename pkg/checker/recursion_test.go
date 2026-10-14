package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

const preserveMessage = "recursive generic applications must preserve their parameters"

func TestExpandingTypeApplicationsThroughSignatures(t *testing.T) {
	for _, tt := range []struct {
		name, source string
		reject       bool
	}{
		{"function field expands", "import List from \"@std/collections.ms\"\ntype Grow[T]:\n    f: fn(x: Grow[List[T]]) -> Int\n", true},
		{"function result expands", "type Grow[T]:\n    f: fn() -> Grow[Grow[T]]\n", true},
		{"interface operation expands", "import List from \"@std/collections.ms\"\ninterface I[T]:\n    fn f(x: I[List[T]]) -> Int\n", true},
		{"interface nests itself", "interface I[T]:\n    fn f(x: I[I[T]]) -> Int\n", true},
		{"function field preserves", "type Walk[T]:\n    f: fn(x: Walk[T]) -> Int\n", false},
		{"interface preserves", "interface I[T]:\n    fn f(x: I[T]) -> T\n", false},
		{"unrelated interface application", "import List from \"@std/collections.ms\"\ninterface J[T]:\n    fn g() -> Int\ninterface I[T]:\n    fn f(x: J[List[T]]) -> Int\n", false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("expand.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			found := false
			for _, d := range p.Diagnostics {
				found = found || strings.Contains(d.Message, preserveMessage)
			}
			if found != tt.reject {
				t.Fatalf("reject=%v, diagnostics %v", tt.reject, p.Diagnostics)
			}
		})
	}
}
