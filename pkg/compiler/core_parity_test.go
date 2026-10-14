package compiler

import (
	"strings"
	"testing"
)

func TestCoreParityRejectsInvalidContracts(t *testing.T) {
	for _, test := range []struct{ name, source, want string }{
		{"Result fallback type", `fn wrong(value: Result[Int, String]) -> Int: value.unwrap_or("wrong")`, "expected Int, found String"},
		{"Result fallback callback labels", `fn wrong(value: Result[Int, String], create: fn(value: String) -> Int) -> Int: value.unwrap_or_else(create)`, "cause"},
		{"Result chain keeps error type", `fn wrong(value: Result[Int, String]) -> Result[Int, Int]: value.and_then(fn(n): Result[Int, Int].ok(n))`, "String"},
		{"Result map does not map errors", `fn wrong(value: Result[Int, String]) -> Result[Int, Int]: value.map(fn(n): n)`, "Result[U, String]"},
		{"Result map does not flatten", `fn wrong(value: Result[Int, String]) -> Int: value.map(fn(n): n)`, "Result[U, String]"},
		{"Optional chain must return Optional", `fn wrong(value: Optional[Int]) -> Optional[Int]: value.and_then(fn(n): n)`, "Optional"},
		{"Optional fallback keeps payload", `fn wrong(value: Optional[Int]) -> Optional[Int]: value.or_else(fn(): some("wrong"))`, "Int"},
		{"Set output requires Hashable", `fn wrong(value: Set[Int]) -> Unit:
    let output = value.map(fn(n): n.to_float())`, "Hashable"},
		{"Set generic output needs bound", `fn wrong[U](value: Set[Int], transform: fn(value: Int) -> U) -> Unit:
    let output = value.map(transform)`, "Hashable"},
		{"Map predicate result", `fn wrong(value: Map[String, Int]) -> Unit:
    let output = value.filter(fn(k, n): n)`, "Bool"},
		{"Map fallback payload", `fn wrong(value: Map[String, Int]) -> Int: value.get_or("key", "wrong")`, "Int"},
		{"local Result gets no methods", `type Result[T, E]:
    case ok(value: T)
    case error(cause: E)
fn wrong(value: Result[Int, String]) -> Int: value.unwrap()`, "no fields or operations"},
		{"private native Result helper", `import unwrap from "@std/result.ms"`, "unwrap"},
	} {
		t.Run(test.name, func(t *testing.T) {
			source := "" + test.source + "\n"
			result := CompileSource("parity.ms", source, Options{AnalyzeOnly: true})
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
