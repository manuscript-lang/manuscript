package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func nestedLiteral(open, leaf, close string, depth int) string {
	return "fn example() -> Int:\n    let x = " +
		strings.Repeat(open, depth) + leaf + strings.Repeat(close, depth) + "\n    return 0\n"
}

func checkNested(t testing.TB, source string) *checker.Program {
	t.Helper()
	m, err := parser.Parse("nested.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	return checker.Check([]*syntax.Module{m}, nil)
}

func BenchmarkNestedMapLiteral(b *testing.B) {
	source := nestedLiteral(`{"a": `, "1", "}", 400)
	for b.Loop() {
		checkNested(b, source)
	}
}

func BenchmarkNestedListLiteral(b *testing.B) {
	source := nestedLiteral("[", "1", "]", 900)
	for b.Loop() {
		checkNested(b, source)
	}
}

// Checking a nested literal must not repeat each level's subtree or rebuild
// its type key once per enclosing level; doubling the depth should roughly
// double the work. Before, it grew about eightfold (cubic) for lists and
// faster still for maps.
func TestNestedLiteralCheckingScalesWithDepth(t *testing.T) {
	for _, shape := range []struct{ name, open, close string }{{"list", "[", "]"}, {"map", `{"a": `, "}"}} {
		t.Run(shape.name, func(t *testing.T) {
			allocations := func(depth int) float64 {
				source := nestedLiteral(shape.open, "1", shape.close, depth)
				return testing.AllocsPerRun(1, func() {
					if p := checkNested(t, source); len(p.Diagnostics) != 0 {
						t.Fatal(p.Diagnostics)
					}
				})
			}
			small, large := allocations(200), allocations(800)
			if large > 6*small {
				t.Fatalf("checking 800 levels allocated %.0f times, 200 levels %.0f; want near-linear growth", large, small)
			}
		})
	}
}

func TestNestedLiteralTypes(t *testing.T) {
	source := nestedLiteral("[", "1", "]", 3)
	p := checkNested(t, source)
	if len(p.Diagnostics) != 0 {
		t.Fatal(p.Diagnostics)
	}
	want := map[string]bool{"List[Int]": false, "List[List[Int]]": false, "List[List[List[Int]]]": false}
	for expression, info := range p.Expressions() {
		if expression.Kind == syntax.KindList {
			if _, ok := want[info.Type.String()]; !ok {
				t.Fatalf("unexpected nested list type %s", info.Type)
			}
			want[info.Type.String()] = true
		}
	}
	for typ, found := range want {
		if !found {
			t.Fatalf("missing nested list of type %s", typ)
		}
	}
}

// An element type that cannot be inferred is reported once at the outermost
// literal, not again at every nested empty literal inside it.
func TestNestedEmptyLiteralReportsOnce(t *testing.T) {
	for _, test := range []struct{ name, source, message string }{
		{"list", nestedLiteral("[", "", "]", 50), "cannot infer list element type"},
		{"map", nestedLiteral(`{"a": `, "{}", "}", 50), "cannot infer map key or value type"},
		{"mixed", nestedLiteral("[", `{"a": []}`, "]", 5), "cannot infer map key or value type"},
	} {
		t.Run(test.name, func(t *testing.T) {
			p := checkNested(t, test.source)
			if len(p.Diagnostics) != 1 || !strings.Contains(p.Diagnostics[0].Message, test.message) {
				t.Fatalf("want one %q diagnostic, got %v", test.message, p.Diagnostics)
			}
		})
	}
}

// Nested constructor calls infer ever larger types; checking each call's bounds
// must not rebuild a structural key of the whole result per level.
func TestNestedConstructorCheckingScalesWithDepth(t *testing.T) {
	for _, shape := range []struct{ name, prelude, open string }{
		{"some", "", "some("},
		{"generic type", "type Box[T]:\n    value: T\n", "Box(value: "},
	} {
		t.Run(shape.name, func(t *testing.T) {
			allocations := func(depth int) float64 {
				source := shape.prelude + nestedLiteral(shape.open, "1", ")", depth)
				return testing.AllocsPerRun(1, func() {
					if p := checkNested(t, source); len(p.Diagnostics) != 0 {
						t.Fatal(p.Diagnostics)
					}
				})
			}
			small, large := allocations(200), allocations(800)
			if large > 6*small {
				t.Fatalf("checking 800 levels allocated %.0f times, 200 levels %.0f; want near-linear growth", large, small)
			}
		})
	}
}
