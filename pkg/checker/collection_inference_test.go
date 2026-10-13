package checker_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func nestedLiteralModule(t testing.TB, depth int, empty bool) (*syntax.Module, *syntax.Expression) {
	t.Helper()
	module, err := parser.Parse("nested.ms", "fn use() -> Unit:\n    let values = 1\n")
	if err != nil {
		t.Fatal(err)
	}
	value := module.Declarations[0].Body[0].Value
	if empty {
		value = &syntax.Expression{Kind: syntax.KindList, Pos: value.Pos}
	}
	leaf := value
	for range depth {
		value = &syntax.Expression{Kind: syntax.KindList, Pos: value.Pos, Elements: []*syntax.Expression{value}}
	}
	module.Declarations[0].Body[0].Value = value
	return module, leaf
}

func TestNestedLiteralInferenceRetainsCheckedChildren(t *testing.T) {
	// Construct the AST directly: the parser's independent nesting limit remains
	// intact, while API callers and checker regressions can exercise deeper trees.
	for _, depth := range []int{500, 1000, 2000, 4000} {
		t.Run(fmt.Sprint(depth), func(t *testing.T) {
			module, _ := nestedLiteralModule(t, depth, false)
			for range 2 {
				program := checker.Check([]*syntax.Module{module}, nil)
				if len(program.Diagnostics) != 0 {
					t.Fatal(program.Diagnostics)
				}
				value := module.Declarations[0].Body[0].Value
				for range depth {
					info := program.Expressions[value]
					child := value.Elements[0]
					if info == nil || info.Type.ID != "@std/List" || len(info.Type.Args) != 1 || info.Type.Args[0] != program.Expressions[child].Type {
						t.Fatal("nested inference lost its checked child identity")
					}
					value = child
				}
				if program.Expressions[value].Type.ID != "Int" {
					t.Fatal("lost leaf type")
				}
			}
		})
	}
}

func TestNestedLiteralInferenceAllocationGrowth(t *testing.T) {
	// Allocation growth is deterministic enough to catch repeated inference
	// without imposing a wall-clock deadline on shared CI workers.
	var previous float64
	for _, depth := range []int{250, 500, 1000} {
		module, _ := nestedLiteralModule(t, depth, false)
		allocations := testing.AllocsPerRun(1, func() {
			program := checker.Check([]*syntax.Module{module}, nil)
			if len(program.Diagnostics) != 0 {
				t.Fatal(program.Diagnostics)
			}
		})
		if previous != 0 && allocations > previous*3 {
			t.Fatalf("doubling nesting from %d to %d grew allocations from %.0f to %.0f", depth/2, depth, previous, allocations)
		}
		previous = allocations
	}
}

func TestNestedEmptyLiteralReportsMissingLeafContextOnce(t *testing.T) {
	module, leaf := nestedLiteralModule(t, 500, true)
	program := checker.Check([]*syntax.Module{module}, nil)
	if len(program.Diagnostics) != 1 || !strings.HasPrefix(program.Diagnostics[0].Message, "cannot infer list element type;") || program.Diagnostics[0].Position != leaf.Pos {
		t.Fatalf("expected one leaf inference diagnostic, got %v", program.Diagnostics)
	}
	if program.Expressions[leaf] == nil {
		t.Fatal("missing checked leaf")
	}
}

func TestCollectionInferenceKeepsDifferentContexts(t *testing.T) {
	for _, test := range []struct {
		name, source string
		errors       int
	}{
		{"empty sibling context", "let xs = [[[]], [[1]]]\n", 0},
		{"callback labels", "let xs = [[fn(left: Int) -> Int: left], [fn(right: Int) -> Int: right]]\n", 0},
		{"annotation", "let xs: List[List[List[Int]]] = [[[]]]\n", 0},
		{"map value context", "let xs = {1: [[]], 2: [[1]]}\n", 0},
		{"mismatch", "let xs = [[1], [\"text\"]]\n", 1},
		{"unknown leaf", "let xs = [[[missing]]]\n", 2},
		{"independent errors", "let xs = [[1], [missing], [false]]\n", 2},
	} {
		t.Run(test.name, func(t *testing.T) {
			module, err := parser.Parse("contexts.ms", "fn use() -> Unit:\n    "+test.source)
			if err != nil {
				t.Fatal(err)
			}
			program := checker.Check([]*syntax.Module{module}, nil)
			if len(program.Diagnostics) != test.errors {
				t.Fatalf("want %d diagnostics, got %v", test.errors, program.Diagnostics)
			}
		})
	}
}

func BenchmarkNestedLiteralInference(b *testing.B) {
	for _, depth := range []int{250, 500, 1000, 2000, 4000} {
		b.Run(fmt.Sprint(depth), func(b *testing.B) {
			module, _ := nestedLiteralModule(b, depth, false)
			checker.Check([]*syntax.Module{module}, nil)
			b.ReportAllocs()
			b.ResetTimer()
			for range b.N {
				if program := checker.Check([]*syntax.Module{module}, nil); len(program.Diagnostics) != 0 {
					b.Fatal(program.Diagnostics)
				}
			}
		})
	}
}

func TestNestedMapLiteralInferenceAllocationGrowth(t *testing.T) {
	var previous float64
	for _, depth := range []int{250, 500, 1000, 2000, 4000} {
		module, _ := nestedLiteralModule(t, 0, false)
		value := module.Declarations[0].Body[0].Value
		for range depth {
			key := &syntax.Expression{Kind: syntax.KindNumber, Text: "1", Pos: value.Pos}
			value = &syntax.Expression{Kind: syntax.KindMap, Elements: []*syntax.Expression{key, value}, Pos: value.Pos}
		}
		module.Declarations[0].Body[0].Value = value
		allocations := testing.AllocsPerRun(1, func() {
			program := checker.Check([]*syntax.Module{module}, nil)
			if len(program.Diagnostics) != 0 {
				t.Fatal(program.Diagnostics)
			}
			current := value
			for range depth {
				info := program.Expressions[current]
				child := current.Elements[1]
				if info.Type.ID != "@std/Map" || info.Type.Args[0].ID != "Int" || info.Type.Args[1] != program.Expressions[child].Type {
					t.Fatal("nested map lost its checked child identity")
				}
				current = child
			}
		})
		if previous != 0 && allocations > previous*3 {
			t.Fatalf("map allocation growth %.0f -> %.0f at depth %d", previous, allocations, depth)
		}
		previous = allocations
	}
}

func TestCollectionBoundFailuresRetainEachUseSite(t *testing.T) {
	module, err := parser.Parse("bounds.ms", "fn use() -> Unit:\n    let first = {1.0: 1}\n    let second = {2.0: 2}\n")
	if err != nil {
		t.Fatal(err)
	}
	program := checker.Check([]*syntax.Module{module}, nil)
	if len(program.Diagnostics) != 2 || program.Diagnostics[0].Position.Line != 2 || program.Diagnostics[1].Position.Line != 3 {
		t.Fatalf("bound failures lost their use sites: %v", program.Diagnostics)
	}
}

func TestNestedMapBoundFailuresDoNotCascadeThroughParents(t *testing.T) {
	module, _ := nestedLiteralModule(t, 0, false)
	value := module.Declarations[0].Body[0].Value
	const depth = 250
	for level := range depth {
		position := syntax.Position{File: "bounds.ms", Line: level + 2, Column: 1}
		key := &syntax.Expression{Kind: syntax.KindNumber, Text: "1.0", Pos: position}
		value = &syntax.Expression{Kind: syntax.KindMap, Elements: []*syntax.Expression{key, value}, Pos: position}
	}
	module.Declarations[0].Body[0].Value = value
	program := checker.Check([]*syntax.Module{module}, nil)
	if len(program.Diagnostics) != depth {
		t.Fatalf("want one bound diagnostic per map, got %d", len(program.Diagnostics))
	}
	for _, diagnostic := range program.Diagnostics {
		if !strings.Contains(diagnostic.Message, "Hashable") {
			t.Fatal(diagnostic)
		}
	}
}
