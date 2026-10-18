package compiler

import (
	"strings"
	"testing"
)

func TestConversionsAndQueriesRejectInvalidContracts(t *testing.T) {
	for _, test := range []struct{ name, source, want string }{
		{"conversion error stays exact", `fn wrong(value: Optional[Int]) Result[Int, String]: value.ok_or(false)`, "String"},
		{"lazy conversion takes no parameters", `fn cause(value: Int) String: "cause"
fn wrong(value: Optional[Int]) Result[Int, String]: value.ok_or_else(cause)`, "fn()"},
		{"Result conversion stays wrapped", `fn wrong(value: Result[Int, String]) Int: value.to_optional()`, "Optional[Int]"},
		{"Map find returns entry", `fn wrong(value: Map[String, Int]) Optional[Int]: value.find(fn(k, v): true)`, "MapEntry"},
		{"Map predicate result", `fn wrong(value: Map[String, Int]) Bool: value.some(fn(k, v): v)`, "Bool"},
		{"Set predicate result", `fn wrong(value: Set[Int]) Bool: value.every(fn(n): n)`, "Bool"},
		{"Map fold initial result stays exact", `fn wrong(value: Map[String, Int]) Int: value.fold(0, fn(acc, k, v): k)`, "Int"},
		{"Set fold step result stays exact", `fn wrong(value: Set[Int]) Int: value.fold(0, fn(acc, n): n.to_string())`, "Int"},
		{"stored Map predicate labels", `fn check(value: Int, key: String) Bool: true
fn wrong(value: Map[String, Int]) Bool: value.every(check)`, "key"},
		{"local Optional declaration is rejected", `type Optional[T]:
    case some(value: T)
    case none
fn wrong(value: Optional[Int]) Result[Int, String]: value.ok_or("missing")`, "reuses a prelude name"},
		{"local Result declaration is rejected", `type Result[T, E]:
    case ok(value: T)
    case error(cause: E)
fn wrong(value: Result[Int, String]) Optional[Int]: value.to_optional()`, "reuses a prelude name"},
		{"native helpers stay private", `import ok_or from "@std/optional.ms"`, "ok_or"},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := CompileSource("queries.ms", ""+test.source+"\n", Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted invalid contract")
			}
			for _, diagnostic := range result.Diagnostics {
				if strings.Contains(diagnostic.Message, test.want) {
					return
				}
			}
			t.Fatalf("expected %q, got %v", test.want, result.Diagnostics)
		})
	}
}

func TestOperatorOnInvalidOperandReportsOnce(t *testing.T) {
	result := CompileSource("once.ms", "fn f() Int:\n    var x: Int = 1\n    x += try 3\n    return x\n", Options{AnalyzeOnly: true})
	if len(result.Diagnostics) != 1 || !strings.Contains(result.Diagnostics[0].Message, "try requires Result") {
		t.Fatalf("want only the try error, got %+v", result.Diagnostics)
	}
}
