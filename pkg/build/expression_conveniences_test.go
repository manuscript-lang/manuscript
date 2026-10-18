package build

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestExpressionConvenienceRejections(t *testing.T) {
	imports := ""
	for _, tt := range []struct{ name, source, want string }{
		{"selected function requires arguments", "fn optional(value: Int = 1) -> Int: return value\nfn required(value: Int) -> Int: return value\nfn call(x: Optional[Int]) -> Int:\n    let chosen = match x:\n    some(n): optional\n    none: required\n    return chosen()\n", "missing argument value"},
		{"condition exits enclosing loop", "fn f(x: Optional[Int]) -> Int:\n    while true:\n        while (match x:\n        some(n): true\n        none: break\n        ):\n            break\n", "reachable fallthrough"},
		{"index type", "fn f(xs: List[Int]) -> Int: return xs[\"0\"]\n", "expected Int, found String"},
		{"non-list", "fn f() -> Int: return 1[0]\n", "indexing requires List"},
		{"empty inference", "fn f() -> Unit: let xs = List()\n", "cannot infer constructor type argument"},
		{"list arguments", "fn f() -> Unit: let xs = List[Int](1)\n", "argument"},
		{"mixed string", "fn f() -> String: return \"a\" + 1\n", "same independently known type"},
		{"string subtract", "fn f() -> String: return \"a\" - \"b\"\n", "arithmetic requires"},
		{"exhaustive", "fn f(x: Optional[Int]) -> Int:\n    return match x:\n    some(n): n\n", "non-exhaustive match"},
		{"arm types", "fn f(x: Optional[Int]) -> Unit:\n    let y = match x:\n    some(n): n\n    none: \"missing\"\n", "expected Int, found String"},
		{"return type", "fn f(x: Optional[Int]) -> Int:\n    return match x:\n    some(n): n\n    none: return \"missing\"\n", "expected Int, found String"},
		{"arm scope", "fn f(x: Optional[Int]) -> Int:\n    let y = match x:\n    some(n): n\n    none: 0\n    return n\n", "unknown binding n"},
		{"try in arm", "fn p() -> Result[Int, Error]:\n    return ok(1)\nfn f(x: Optional[Int]) -> Result[Unit, Error]:\n    match x:\n    some(n):\n        try p()\n        return ok(unit)\n    none: return ok(unit)\n", "standalone try requires a Unit success value"},
		{"result where value expected", "fn p() -> Result[Int, Error]:\n    return ok(1)\nfn f() -> Int:\n    return p()\n", "unwrap it with 'try'"},
		{"optional where value expected", "fn f(x: Optional[Int]) -> Int:\n    return x\n", "unwrap it first with 'if let'"},
		{"multiple expressions", "fn f(x: Optional[Int]) -> Int:\n    return match x:\n    some(n):\n        n\n        n + 1\n    none: 0\n", "final expression"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			result := compiler.CompileSource("expressions.ms", imports+tt.source, compiler.Options{})
			for _, d := range result.Diagnostics {
				if strings.Contains(d.Message, tt.want) {
					return
				}
			}
			t.Fatalf("want %q, got %v", tt.want, result.Diagnostics)
		})
	}
}

func TestExpressionConveniencesCompile(t *testing.T) {
	result := compiler.CompileFile("../../tests/e2e/testdata/accept/expression-conveniences.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
}
