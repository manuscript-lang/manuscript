package compiler_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestPreparedSourceCallEligibility(t *testing.T) {
	for _, test := range []struct {
		name, source string
		prepared     bool
	}{
		{"ordered", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int: add(a: 1, b: 2)\n", true},
		{"positional", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int: add(1, 2)\n", true},
		{"mixed ordered", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int: add(1, b: 2)\n", true},
		{"mixed reordered", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int: add(b: 2, 1)\n", false},
		{"single label", "fn value(number: Int) -> Int: number\nfn run() -> Int: value(2)\n", true},
		{"shorthand", "fn add(a: Int, b: Int) -> Int: a + b\nfn run(a: Int, b: Int) -> Int: add(a, b)\n", true},
		{"no arguments", "fn value() -> Int: 2\nfn run() -> Int: value()\n", true},
		{"explicit default", "fn value(number: Int = 2) -> Int: number\nfn run() -> Int: value(3)\n", true},
		{"omitted default", "fn value(number: Int = 2) -> Int: number\nfn run() -> Int: value()\n", true},
		{"reordered", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int: add(b: 2, a: 1)\n", false},
		{"generic", "fn value[T](number: T) -> T: number\nfn run() -> Int: value(2)\n", true},
		{"generic with dynamic type arguments", "fn value[T](number: T) -> T: number\nfn forward[T](number: T) -> T: value(number)\n", false},
		{"callback", "fn add(a: Int, b: Int) -> Int: a + b\nfn run() -> Int:\n    let callback = add\n    return callback(a: 1, b: 2)\n", false},
		{"native", "import panic from \"@std/faults.ms\"\nfn run() -> Int: panic(\"stop\")\n", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := compiler.CompileSource("calls.ms", test.source, compiler.Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			if got := callsDirectly(t, result.Source); got != test.prepared {
				t.Fatalf("prepared call = %v, want %v\n%s", got, test.prepared, result.Source)
			}
		})
	}
}

// callsDirectly reports whether a source function calls another through its
// Go function (direct function) or the callee's Body (prepared call) instead of Invoke.
func callsDirectly(t *testing.T, source string) bool {
	file, err := parser.ParseFile(token.NewFileSet(), "generated.go", source, parser.SkipObjectResolution)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok || fn.Name.Name == "initialize" {
			continue
		}
		ast.Inspect(fn.Body, func(node ast.Node) bool {
			if c, ok := node.(*ast.CallExpr); ok {
				if name, ok := c.Fun.(*ast.Ident); ok && strings.HasPrefix(name.Name, "call_") {
					found = true
				}
			}
			return true
		})
	}
	return found || strings.Contains(source, ".(rt.Function).Body(")
}
