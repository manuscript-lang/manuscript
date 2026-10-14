package checker_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestRecursiveDataAndFiniteTypeApplications(t *testing.T) {
	for _, tt := range []struct {
		name, source string
		accepted     bool
	}{
		{"direct alternative", "type Expr:\n    case Num(value: Int)\n    case Add(left: Expr, right: Expr)\n    case Neg(inner: Optional[Expr])\n", true},
		{"record declaration", "type Node:\n    next: Node\n", true},
		{"mutual", "type A:\n    case End\n    case Next(value: B)\ntype B:\n    a: A\n", true},
		{"generic direct", "type Tree[T]:\n    case Leaf(value: T)\n    case Branch(left: Tree[T], right: Tree[T])\n", true},
		{"generic mutual", "type A[T]:\n    value: T\n    b: Optional[B[T]]\ntype B[U]:\n    a: A[U]\n", true},
		{"composed identity", "type A[T, U]:\n    b: B[U, T]\ntype B[X, Y]:\n    a: A[Y, X]\n", true},
		{"phantom argument expansion", "import List from \"@std/collections.ms\"\ntype Phantom[T]:\n    value: Int\ntype Grow[T]:\n    value: Phantom[Grow[List[T]]]\n", false},
		{"finite nesting", "type Box[T]:\n    value: T\ntype Nested:\n    value: Box[Box[Int]]\n", true},
		{"optional entry composition", "type Entry:\n    name: String\n    nickname: Optional[String]\ntype Person:\n    primary: Optional[Entry]\n", true},
		{"nested optional field", "type Config:\n    value: Optional[Optional[Int]]\n", true},
		{"nested optional payload", "type Config:\n    case Value(value: Optional[Optional[Int]])\n", true},
		{"nested result field", "type Config:\n    value: Result[Result[Int, String], String]\n", true},
		{"nested optional generic pair", "type Pair[T, U]:\n    first: T\n    second: U\ntype Config:\n    value: Pair[Optional[Int], Optional[Optional[String]]]\n", true},
		{"nested optional collection", "import List from \"@std/collections.ms\"\ntype Config:\n    value: Optional[List[Optional[Int]]]\n", true},
		{"regular callback", "type Node[T]:\n    build: fn() -> Node[T]\n", true},
		{"regular interface", "interface Node[T]:\n    fn build() -> Node[T]\n", true},
		{"expanding direct", "import List from \"@std/collections.ms\"\ntype Grow[T]:\n    next: Grow[List[T]]\n", false},
		{"expanding container", "import List from \"@std/collections.ms\"\ntype Grow[T]:\n    next: List[Grow[List[T]]]\n", false},
		{"expanding mutual", "import List from \"@std/collections.ms\"\ntype A[T]:\n    b: B[List[T]]\ntype B[U]:\n    a: A[U]\n", false},
		{"expanding callback", "import List from \"@std/collections.ms\"\ntype Grow[T]:\n    next: fn() -> Grow[List[T]]\n", false},
		{"expanding callback parameter", "import List from \"@std/collections.ms\"\ntype Grow[T]:\n    next: fn(value: Grow[List[T]]) -> Unit\n", false},
		{"expanding interface", "import List from \"@std/collections.ms\"\ninterface Grow[T]:\n    fn next() -> Grow[List[T]]\n", false},
		{"concrete substitution", "type Grow[T]:\n    next: Grow[Int]\n", false},
		{"permutation", "type Flip[T, U]:\n    next: Flip[U, T]\n", false},
		{"nongeneric bridge", "type Grow[T]:\n    next: Bridge\ntype Bridge:\n    next: Grow[Int]\n", false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			module, err := parser.Parse("recursion.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			result := checker.Check([]*syntax.Module{module}, nil)
			if (len(result.Diagnostics) == 0) != tt.accepted {
				t.Fatalf("accepted=%v, diagnostics=%v", tt.accepted, result.Diagnostics)
			}
			for _, d := range result.Diagnostics {
				if !strings.Contains(d.Message, "recursive generic applications must preserve their parameters") {
					t.Errorf("unexpected diagnostic: %v", d)
				}
			}
		})
	}
}

func TestRecursiveGenericDiagnosticNamesEachFieldOnce(t *testing.T) {
	source := "type Tree[T]:\n    case Leaf(value: T)\n    case Pair(left: Tree[Int], right: Tree[String])\n"
	module, err := parser.Parse("recursion.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	result := checker.Check([]*syntax.Module{module}, nil)
	if len(result.Diagnostics) != 2 {
		t.Fatal(result.Diagnostics)
	}
	for i, name := range []string{"Tree.Pair.left", "Tree.Pair.right"} {
		d := result.Diagnostics[i]
		column := []int{15, 32}[i]
		if d.Position.Line != 3 || d.Position.Column != column || !strings.Contains(d.Message, name) {
			t.Errorf("want %s at 3:%d, got %v", name, column, d)
		}
	}
}

func TestFiniteTypeApplicationsShareRepeatedDependencies(t *testing.T) {
	// A diamond at every level has exponentially many paths, but only a
	// linear number of declaration/specialization pairs per starting type.
	var source strings.Builder
	source.WriteString("type Layer0[T]:\n    value: T\n")
	for i := 1; i <= 32; i++ {
		fmt.Fprintf(&source, "type Layer%d[T]:\n    left: Layer%d[T]\n    right: Layer%d[T]\n", i, i-1, i-1)
	}
	module, err := parser.Parse("diamond.ms", source.String())
	if err != nil {
		t.Fatal(err)
	}
	result := checker.Check([]*syntax.Module{module}, nil)
	if len(result.Diagnostics) != 0 {
		t.Fatal(result.Diagnostics)
	}
}

func TestStructuralPropertiesShareRepeatedDependencies(t *testing.T) {
	var source strings.Builder
	source.WriteString("type Layer0:\n    value: Int\n")
	for i := 1; i <= 32; i++ {
		fmt.Fprintf(&source, "type Layer%d:\n    left: Layer%d\n    right: Layer%d\n", i, i-1, i-1)
	}
	source.WriteString("fn hash(value: Layer32) -> Int: return value.hash()\n")
	source.WriteString("fn equal(left: Layer32, right: Layer32) -> Bool: return left == right\n")
	module, err := parser.Parse("properties.ms", source.String())
	if err != nil {
		t.Fatal(err)
	}
	result := checker.Check([]*syntax.Module{module}, nil)
	if len(result.Diagnostics) != 0 {
		t.Fatal(result.Diagnostics)
	}
}
