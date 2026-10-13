package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestRecursiveLayoutFieldDiagnostics(t *testing.T) {
	source := "type Expr:\n    case Num(value: Int)\n    case Add(left: Expr, right: Expr)\n    case Neg(inner: Optional[Expr])\n"
	module, err := parser.Parse("layout.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	result := checker.Check([]*syntax.Module{module}, nil)
	want := []struct {
		name         string
		line, column int
	}{
		{"Expr.Add.left", 3, 14}, {"Expr.Add.right", 3, 26}, {"Expr.Neg.inner", 4, 14},
	}
	if len(result.Diagnostics) != len(want) {
		t.Fatalf("want %d diagnostics, got %v", len(want), result.Diagnostics)
	}
	for i, expected := range want {
		diagnostic := result.Diagnostics[i]
		if diagnostic.Position.Line != expected.line || diagnostic.Position.Column != expected.column {
			t.Errorf("%s: got position %v", expected.name, diagnostic.Position)
		}
		for _, text := range []string{"unguarded inline recursive layout", expected.name, "Expr", "List[Expr]"} {
			if !strings.Contains(diagnostic.Message, text) {
				t.Errorf("missing %q in %q", text, diagnostic.Message)
			}
		}
		if strings.Contains(diagnostic.Message, "Optional[") {
			t.Errorf("invalid Optional indirection hint: %s", diagnostic.Message)
		}
	}
}

func TestRecursiveLayoutRulesRemainUnchanged(t *testing.T) {
	for _, tt := range []struct {
		name, source, want string
		count              int
	}{
		{"record", "type Node:\n    next: Node\n", "Node.next", 1},
		{"mutual", "type A:\n    b: B\ntype B:\n    a: A\n", "unguarded inline recursive layout", 2},
		{"multiple inline paths in one field", "type Node:\n    next: Result[Node, Node]\n", "Node.next", 1},
		{"container", "import List from \"@std/collections.ms\"\ntype Node:\n    children: List[Node]\n", "", 0},
		{"function", "type Node:\n    build: fn() -> Node\n", "", 0},
		{"generic container", "import List from \"@std/collections.ms\"\ntype Node[T]:\n    value: T\n    children: List[Node[T]]\n", "", 0},
		{"expanding generic container", "import List from \"@std/collections.ms\"\ntype Node[T]:\n    value: T\n    children: List[Node[List[T]]]\n", "recursive generic applications must preserve their parameters", 1},
	} {
		t.Run(tt.name, func(t *testing.T) {
			module, err := parser.Parse("layout.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			result := checker.Check([]*syntax.Module{module}, nil)
			if len(result.Diagnostics) != tt.count {
				t.Fatalf("want %d diagnostics, got %v", tt.count, result.Diagnostics)
			}
			for _, diagnostic := range result.Diagnostics {
				if !strings.Contains(diagnostic.Message, tt.want) {
					t.Errorf("expected %q: %v", tt.want, diagnostic)
				}
			}
		})
	}
}
