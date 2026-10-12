package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestDefaultArgumentBoundaries(t *testing.T) {
	for _, tt := range []struct{ name, source, want string }{
		{"wrong default type", "fn f(value: Int = true) -> Int:\n    return value\n", "expected Int, found Bool"},
		{"later parameter", "fn f(first: Int = second, second: Int = 2) -> Int:\n    return first\n", "unknown binding second"},
		{"self reference", "fn f(value: Int = value) -> Int:\n    return value\n", "unknown binding value"},
		{"missing required", "fn f(first: Int = 1, second: Int) -> Int:\n    return first + second\nfn call() -> Int:\n    return f()\n", "missing argument second"},
		{"labels still required", "fn f(first: Int = 1, second: Int = 2) -> Int:\n    return first + second\nfn call() -> Int:\n    return f(3)\n", "argument labels are required"},
		{"duplicate argument", "fn f(value: Int = 1) -> Int:\n    return value\nfn call() -> Int:\n    return f(2, value: 3)\n", "duplicate argument value"},
		{"unknown label", "fn f(value: Int = 1) -> Int:\n    return value\nfn call() -> Int:\n    return f(other: 3)\n", "unknown argument other"},
		{"default does not infer generics", "fn f[T](value: T = 3) -> T:\n    return value\n", "expected T, found Int"},
		{"omitted generic source", "fn f[T](value: T, copy: T = value) -> T:\n    return copy\nfn call() -> Int:\n    return f()\n", "cannot infer type argument T"},
		{"annotation erases defaults", "fn f(value: Int = 1) -> Int:\n    return value\nfn call() -> Int:\n    let copy: fn(value: Int) -> Int = f\n    return copy()\n", "missing argument value"},
		{"mutable binding erases defaults", "fn f(value: Int = 1) -> Int:\n    return value\nfn g(value: Int) -> Int:\n    return value\nfn call() -> Int:\n    var copy = f\n    copy = g\n    return copy()\n", "missing argument value"},
		{"function parameter erases defaults", "fn f(value: Int = 1) -> Int:\n    return value\nfn apply(callback: fn(value: Int) -> Int) -> Int:\n    return callback()\n", "missing argument value"},
		{"function result erases defaults", "fn f(value: Int = 1) -> Int:\n    return value\nfn make() -> fn(value: Int) -> Int:\n    return f\nfn call() -> Int:\n    return make()()\n", "missing argument value"},
		{"generic forwarding erases defaults", "fn f(value: Int = 1) -> Int:\n    return value\nfn forward[T](value: T) -> T:\n    return value\nfn call() -> Int:\n    let copy = forward(f)\n    return copy()\n", "missing argument value"},
		{"contract requires arguments", "interface Add:\n    fn add(value: Int) -> Int\ntype Offset:\n    value: Int\nimpl Add for Offset:\n    fn add(value: Int = self.value) -> Int:\n        return value\nfn call(value: Add) -> Int:\n    return value.add()\n", "missing argument value"},
		{"defaults count toward callback arity", "import parallel from \"@std/tasks.ms\"\nfn f(value: Int = 1) -> Int:\n    return value\nfn call() -> Unit:\n    let result = parallel(tasks: [f])\n", "parallel task requires fn() -> T"},
		{"capture assignment in default", "fn f() -> Unit:\n    var outer = 1\n    let callback = fn(value: Int = (fn() -> Int:\n        outer = 2\n        return outer\n    )()) -> Int:\n        return value\n", "cannot assign a captured binding"},
		{"recursive specialization in default", "import List from \"@std/collections.ms\"\nfn grow[T](value: T, optional: Int = grow(value: [value])) -> Int:\n    return optional\n", "recursive generic applications must preserve their parameters"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("defaults.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			for _, d := range p.Diagnostics {
				if strings.Contains(d.Message, tt.want) {
					return
				}
			}
			t.Fatalf("expected %q, got %v", tt.want, p.Diagnostics)
		})
	}
}

func TestDefaultsDoNotMutateSourceAST(t *testing.T) {
	m, err := parser.Parse("defaults.ms", "fn f(value: Int = 3) -> Int:\n    return value\nfn call() -> Int:\n    return f()\n")
	if err != nil {
		t.Fatal(err)
	}
	call := m.Declarations[1].Body[0].Value
	original := m.Declarations[0].Params[0].Default
	for range 2 {
		p := checker.Check([]*syntax.Module{m}, nil)
		if len(p.Diagnostics) != 0 {
			t.Fatal(p.Diagnostics)
		}
		if len(call.Args) != 0 || len(p.Expressions[call].Arguments) != 0 || m.Declarations[0].Params[0].Default != original {
			t.Fatal("checking rewrote a default or inserted source arguments")
		}
	}
}

func TestDefaultCapturesShareFreely(t *testing.T) {
	source := `import parallel from "@std/tasks.ms"
interface Read:
    fn get() -> Int
fn call(view: Read) -> Unit:
    let callback = fn(value: Int = view.get()) -> Int:
        return value
    let task = fn() -> Int:
        return callback()
    let result = parallel(tasks: [task])
`
	module, err := parser.Parse("defaults.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	program := checker.Check([]*syntax.Module{module}, nil)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
}
