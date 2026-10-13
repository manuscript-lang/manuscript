package checker_test

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"os"
	"path/filepath"
	"testing"
)

func TestAcceptedDesignFixtures(t *testing.T) {
	files, _ := filepath.Glob("../../tests/e2e/testdata/accept/*.ms")
	for _, file := range files {
		t.Run(filepath.Base(file), func(t *testing.T) {
			source, err := os.ReadFile(file)
			if err != nil {
				t.Fatal(err)
			}
			m, err := parser.Parse(file, string(source))
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			for _, d := range p.Diagnostics {
				t.Error(d)
			}
		})
	}
}

func TestOmittedLabelPreservesSourceAST(t *testing.T) {
	source := "fn identity[T](value: T) -> T:\n    return value\nfn call() -> Int:\n    return identity(3)\n"
	module, err := parser.Parse("argument.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	call := module.Declarations[1].Body[0].Value
	for range 2 {
		program := checker.Check([]*syntax.Module{module}, nil)
		if len(program.Diagnostics) != 0 {
			t.Fatal(program.Diagnostics)
		}
		if call.Args[0].Name != "" {
			t.Fatal("checking changed the source argument label")
		}
		arguments := program.Expressions[call].Arguments
		if len(arguments) != 1 || arguments[0].Name != "value" || arguments[0].Value != call.Args[0].Value || arguments[0].Pos != call.Args[0].Pos {
			t.Fatal("incorrect checked argument mapping", arguments)
		}
	}
}

func TestContextualCallbackPreservesSourceAST(t *testing.T) {
	source := "type Callback:\n    value: fn(value: Int) -> Int\nfn example() -> Unit:\n    let callback = Callback(fn(value): value + 1)\n"
	module, err := parser.Parse("callback.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	call := module.Declarations[1].Body[0].Value
	callback := call.Args[0].Value
	for range 2 {
		program := checker.Check([]*syntax.Module{module}, nil)
		if len(program.Diagnostics) != 0 {
			t.Fatal(program.Diagnostics)
		}
		if call.Args[0].Name != "" || callback.Params[0].Type != nil || callback.Result != nil {
			t.Fatal("checking changed source syntax")
		}
		if program.Expressions[call].Arguments[0].Name != "value" || program.LambdaParameters[callback][0].Type.ID != "Int" {
			t.Fatal("missing inferred source information")
		}
	}
}

// Different collection applications can occur along a recursive declaration path.
// The finite-application rule constrains nominal user types, not Map/List storage.
func TestNestedCollectionsPreserveFiniteRecursiveApplications(t *testing.T) {
	for _, test := range []struct {
		source   string
		accepted bool
	}{
		{`import {List, Map} from "@std/collections.ms"
type Value:
    children: Map[String, Value]
type Wrapper:
    entries: Map[String, Node]
type Node:
    case Leaf(value: Value)
    case Children(values: List[Wrapper])
`, true},
		{`import List from "@std/collections.ms"
type Growing[T]:
    children: List[Growing[List[T]]]
`, false},
	} {
		module, err := parser.Parse("layout.ms", test.source)
		if err != nil {
			t.Fatal(err)
		}
		program := checker.Check([]*syntax.Module{module}, nil)
		if (len(program.Diagnostics) == 0) != test.accepted {
			t.Fatal(test.accepted, program.Diagnostics)
		}
	}
}

func TestMatchingLabelPreservesSourceAST(t *testing.T) {
	source := "fn first[T](left: T, right: T) -> T: return left\nfn call(left: Int, right: Int) -> Int: return first(right, left)\n"
	module, err := parser.Parse("shorthand.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	call := module.Declarations[1].Body[0].Value
	for range 2 {
		program := checker.Check([]*syntax.Module{module}, nil)
		if len(program.Diagnostics) != 0 {
			t.Fatal(program.Diagnostics)
		}
		for at, label := range []string{"right", "left"} {
			if call.Args[at].Name != "" || program.Expressions[call].Arguments[at].Name != label {
				t.Fatal("incorrect shorthand mapping")
			}
		}
	}
}
