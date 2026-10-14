package compiler

import (
	"go/ast"
	"go/parser"
	"go/token"
	"testing"
)

func TestDirectCollectionCallsRetainArgumentConversions(t *testing.T) {
	for _, tc := range []struct {
		name, receiver, statement, runtime string
		converted                          []int
	}{
		{"append", "List[Optional[Int]]", "values.append(7)", "ListAppend", []int{2}},
		{"list contains", "List[Optional[Int]]", "values.contains(7)", "ListContains", []int{2}},
		{"map contains", "Map[Optional[Int], Int]", "values.contains(7)", "MapContains", []int{2}},
		{"map get", "Map[Optional[Int], Int]", "values.get(7)", "MapGet", []int{2}},
		{"map add", "Map[Optional[Int], Optional[Int]]", "values.add(7, 9)", "MapWithEntry", []int{2, 3}},
		{"map entry", "Map[Optional[Int], Optional[Int]]", "values.add(7, 9)", "MapWithEntry", []int{2, 3}},
		{"map remove", "Map[Optional[Int], Int]", "values.remove(7)", "MapRemove", []int{2}},
		{"set contains", "Set[Optional[Int]]", "values.contains(7)", "SetContains", []int{2}},
		{"set value", "Set[Optional[Int]]", "values.add(7)", "SetWithValue", []int{2}},
		{"set add", "Set[Optional[Int]]", "values.add(7)", "SetWithValue", []int{2}},
		{"set remove", "Set[Optional[Int]]", "values.remove(7)", "SetRemove", []int{2}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := CompileSource("conversions.ms", "import {List, Map, Set} from \"@std/collections.ms\"\nfn check(values: "+tc.receiver+") -> Unit:\n    "+tc.statement+"\n", Options{})
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			file, err := parser.ParseFile(token.NewFileSet(), "generated.go", r.Source, 0)
			if err != nil {
				t.Fatal(err)
			}
			found := false
			ast.Inspect(file, func(node ast.Node) bool {
				call, ok := node.(*ast.CallExpr)
				if !ok || !runtimeSelector(call.Fun, tc.runtime) {
					return true
				}
				found = true
				for _, at := range tc.converted {
					value := call.Args[at]
					for {
						capture, ok := value.(*ast.CallExpr)
						if !ok || !runtimeSelector(capture.Fun, "Seq") {
							break
						}
						value = capture.Args[0]
					}
					wrapped, ok := value.(*ast.CallExpr)
					if !ok || !runtimeSelector(wrapped.Fun, "NewAlternative") {
						t.Fatalf("%s argument %d lost checked Some wrapping\n%s", tc.runtime, at, r.Source)
					}
					if tag, ok := wrapped.Args[1].(*ast.BasicLit); !ok || tag.Value != `"some"` {
						t.Fatal("wrong conversion tag")
					}
				}
				return true
			})
			if !found {
				t.Fatalf("lost direct %s fast path\n%s", tc.runtime, r.Source)
			}
		})
	}
}

func runtimeSelector(expr ast.Expr, name string) bool {
	selector, ok := expr.(*ast.SelectorExpr)
	if !ok || selector.Sel.Name != name {
		return false
	}
	qualifier, ok := selector.X.(*ast.Ident)
	return ok && qualifier.Name == "rt"
}
