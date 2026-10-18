package compiler_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

const resultArgumentSource = `import panic from "@std/faults.ms"
type E1:
    code: Int
impl Error for E1:
    fn message() String: "e1"
type E2:
    code: Int
impl Error for E2:
    fn message() String: "e2"
type Missing:
    code: Int
type GenericError[V: Equal]:
    value: V
impl Error for GenericError[V]:
    fn message() String: self.value.toString()
fn f() Result[Int, E1]: error(E1(1))
fn other() Result[Int, E2]: error(E2(2))
fn ignore[T](r: Result[T, Error]) Int: 1
fn h[T](r: Result[T, Error]) T:
    match r:
        ok(value): return value
        error(_): return panic("unused")
fn pair[T](first: Result[T, Error], second: Result[T, Error]) Unit: return
fn optional[T](r: Optional[Result[T, Error]]) Unit: return
fn convert[T, U](r: Result[T, Error]) Optional[U]: none
fn apply[T, U](r: Result[T, Error], callback: fn(value: T) U) U: callback(h(r))
fn exact[T, E](r: Result[T, E]) Result[T, E]: r
`

func TestResultArgumentInference(t *testing.T) {
	for name, source := range map[string]string{
		"issue191":                `fn first() Int: ignore(r: f())`,
		"no result context":       `fn first() Unit: let value = h(f())`,
		"explicit specialization": `fn first() Int: h[Int](r: f())`,
		"annotated boundary": `fn first() Int:
    let r: Result[Int, Error] = f()
    return h(r)`,
		"bounded generic error":  `fn first[E: Error](r: Result[Int, E]) Int: h(r)`,
		"outer generic success":  `fn first[T, E: Error](r: Result[T, E]) T: h(r)`,
		"generic implementation": `fn first(r: Result[Int, GenericError[Int]]) Int: h(r)`,
		"success bound": `fn bounded[T: Equal](r: Result[T, Error]) Unit: return
fn first() Unit: bounded(f())`,
		"nested success stays concrete":         `fn first(r: Result[Result[Int, E1], E2]) Result[Int, E1]: h(r)`,
		"multiple errors":                       `fn first() Unit: pair(first: f(), second: other())`,
		"reordered errors":                      `fn first() Unit: pair(second: other(), first: f())`,
		"positional errors after215":            `fn first() Unit: pair(f(), other())`,
		"mixed errors after215":                 `fn first() Unit: pair(second: other(), f())`,
		"positional callback after215":          `fn first() String: apply(f(), fn(item): item.toString())`,
		"expected missing parameter":            `fn first() Optional[String]: convert(f())`,
		"callback input and result":             `fn first() String: apply(callback: fn(item): item.toString(), r: f())`,
		"callback expected result":              `fn first() Optional[Int]: apply(r: f(), callback: fn(item): none)`,
		"optional wrapping and widening":        `fn first() Unit: optional(f())`,
		"explicit optional wrapping":            `fn first() Unit: optional[Int](f())`,
		"already optional exact":                `fn first(r: Optional[Result[Int, Error]]) Unit: optional(r)`,
		"exact domain inference":                `fn first() Result[Int, E1]: exact(f())`,
		"argument domain before result context": `fn first() Result[Int, Error]: exact(f())`,
		"known Error parameter": `fn both[T, E](cause: E, r: Result[T, E]) Unit: return
fn first(cause: Error) Unit: both(cause: cause, r: f())`,
		"explicit Error parameter": `fn both[T, E](cause: E, r: Result[T, E]) Unit: return
fn first(cause: Error) Unit: both[Int, Error](cause: cause, r: f())`,
		"constructor field": `type Holder[T]:
    r: Result[T, Error]
fn first() Holder[Int]: Holder(f())`,
		"alternative payload": `type Wrapped[T]:
    case value(r: Result[T, Error])
fn first() Wrapped[Int]: Wrapped.value(f())`,
		"shadowed Error parameter": `fn shadow[T, Error](r: Result[T, Error]) Result[T, Error]: r
fn first() Result[Int, E1]: shadow(f())`,
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource("result-arguments.ms", resultArgumentSource+source+"\n", compiler.Options{AnalyzeOnly: true})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}

func TestResultArgumentInferenceKeepsConversionEvidence(t *testing.T) {
	for _, tt := range []struct {
		name, source, actual, optional string
		scoped                         bool
	}{
		{"concrete", `fn first() Int: ignore(f())`, "Result[Int, E1]", "", false},
		{"generic bound", `fn first[E: Error](r: Result[Int, E]) Int: ignore(r)`, "Result[Int, E]", "", true},
		{"generic implementation", `fn first(r: Result[Int, GenericError[Int]]) Int: ignore(r)`, "Result[Int, GenericError[Int]]", "", true},
		{"optional", `fn first() Unit: optional(f())`, "Result[Int, E1]", "Optional[Result[Int, Error]]", false},
		{"nested success", `fn first(r: Result[Result[Int, E1], E2]) Unit: let value = h(r)`, "Result[Result[Int, E1], E2]", "", false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			result := compiler.CompileSource("result-evidence.ms", resultArgumentSource+tt.source+"\n", compiler.Options{AnalyzeOnly: true})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			found := false
			for expression, info := range result.Program.Expressions() {
				if expression.Kind != syntax.KindCall || info.Symbol == nil || (info.Symbol.Name != "ignore" && info.Symbol.Name != "optional" && info.Symbol.Name != "h") || expression.Pos.File != "result-evidence.ms" || expression.Pos.Line <= strings.Count(resultArgumentSource, "\n") {
					continue
				}
				found = true
				argument := result.Program.Info(expression.Args[0].Value)
				if argument.ErrorSource == nil || argument.ErrorSource.String() != tt.actual || argument.ScopedError != tt.scoped {
					t.Fatalf("lost conversion evidence: source %v, scoped %v", argument.ErrorSource, argument.ScopedError)
				}
				if tt.optional != "" && (argument.OptionalArgument == nil || argument.OptionalArgument.String() != tt.optional) {
					t.Fatalf("lost optional conversion: %v", argument.OptionalArgument)
				}
				want := "Int"
				if tt.name == "nested success" {
					want = "Result[Int, E1]"
				}
				if len(info.TypeArgs) != 1 || info.TypeArgs[0].String() != want {
					t.Fatalf("wrong success specialization: %v", info.TypeArgs)
				}
			}
			if !found {
				t.Fatal("missing inferred boundary call")
			}
		})
	}
}

func TestFailedResultArgumentDoesNotConstrainLaterEvidence(t *testing.T) {
	for name, actual := range map[string]string{
		"failed widening":    "Result[Int, Missing]",
		"failed exact error": "Result[Int, E1]",
	} {
		t.Run(name, func(t *testing.T) {
			errorType := "Error"
			if name == "failed exact error" {
				errorType = "E2"
			}
			source := "fn target[T](r: Result[T, " + errorType + "], value: T) Unit: return\nfn first(r: " + actual + ") Unit: target(r: r, value: \"later\")\n"
			result := compiler.CompileSource("result-transaction.ms", resultArgumentSource+source, compiler.Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted incompatible error")
			}
			found := false
			for _, info := range result.Program.Expressions() {
				if info.Symbol == nil || info.Symbol.Name != "target" || len(info.TypeArgs) == 0 {
					continue
				}
				found = true
				if len(info.TypeArgs) != 1 || info.TypeArgs[0].String() != "String" {
					t.Fatalf("failed match committed its success prefix: %v", info.TypeArgs)
				}
			}
			if !found || len(result.Diagnostics) != 2 || strings.Contains(fmt.Sprint(result.Diagnostics), "<invalid>") {
				t.Fatalf("lost later evidence or cascaded diagnostics: %v", result.Diagnostics)
			}
		})
	}
}

func TestResultArgumentInferenceRejects(t *testing.T) {
	for _, tt := range []struct{ name, source, want string }{
		{"missing implementation", `fn first(r: Result[Int, Missing]) Int: h(r)`, "conflicting generic inference"},
		{"unbounded error", `fn first[E](r: Result[Int, E]) Int: h(r)`, "conflicting generic inference"},
		{"implementation bound", `fn first(r: Result[Int, GenericError[Error]]) Int: h(r)`, "does not satisfy Equal"},
		{"success bound", `fn bounded[T: Equal](r: Result[T, Error]) Unit: return
fn first(r: Result[Error, E1]) Unit: bounded(r)`, "does not satisfy Equal"},
		{"conflicting success", `fn first(r: Result[String, E2]) Unit: pair(first: f(), second: r)`, "conflicting generic inference"},
		{"explicit success conflict", `fn first() String: h[String](f())`, "expected Result[String, Error], found Result[Int, E1]"},
		{"expected success conflict", `fn first() String: h(f())`, "expected String, found Int"},
		{"domain mismatch", `fn domain[T](r: Result[T, E2]) Unit: return
fn first() Unit: domain(f())`, "conflicting generic inference"},
		{"repeated error mismatch", `fn same[T, E](first: Result[T, E], second: Result[T, E]) Unit: return
fn first() Unit: same(first: f(), second: other())`, "conflicting generic inference"},
		{"numeric success", `fn first() Float: h(f())`, "expected Float, found Int"},
		{"no result wrapping", `fn first() Int: h(1)`, "conflicting generic inference"},
		{"invariant list", `fn values[T](r: List[Result[T, Error]]) Unit: return
fn first() Unit: values([f()])`, "conflicting generic inference"},
		{"invariant existing optional", `fn first(r: Optional[Result[Int, E1]]) Unit: optional(r)`, "conflicting generic inference"},
		{"no recursive optional wrapping", `fn twice[T](r: Optional[Optional[Result[T, Error]]]) Unit: return
fn first() Unit: twice(f())`, "conflicting generic inference"},
		{"invariant nested success", `fn nested[T](r: Result[Result[T, Error], Error]) Unit: return
fn first(r: Result[Result[Int, E1], E2]) Unit: nested(r)`, "conflicting generic inference"},
		{"callback identity", `fn callback[T](r: Result[fn(value: T) Int, Error]) Unit: return
fn first(r: Result[fn(item: Int) Int, E1]) Unit: callback(r)`, "conflicting generic inference"},
		{"other interface stays explicit", `interface Read:
    fn get() Int
impl Read for E1:
    fn get() Int: self.code
fn read[T](r: Result[T, Read]) Unit: return
fn first() Unit: read(f())`, "conflicting generic inference"},
		{"missing independent evidence", `fn first() Unit: let result = h(error(E1(1)))`, "cannot infer type argument T"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			result := compiler.CompileSource("result-arguments.ms", resultArgumentSource+tt.source+"\n", compiler.Options{AnalyzeOnly: true})
			if result.Success() || !strings.Contains(fmt.Sprint(result.Diagnostics), tt.want) {
				t.Fatalf("want %q, got %v", tt.want, result.Diagnostics)
			}
		})
	}
}
