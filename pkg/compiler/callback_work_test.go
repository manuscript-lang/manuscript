package compiler_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestDeepContextualCallbacksCheckedOnce(t *testing.T) {
	// Rechecking every successful callback probe doubled work at each level.
	// This depth is cheap when each body is retained under its final signature.
	expression := strings.Repeat("[1].map(fn(item): ", 40) + "1" + strings.Repeat(")", 40)
	source := "import List from \"@std/collections.ms\"\nfn first() -> Unit:\n    let values = " + expression + "\n"
	result := compiler.CompileSource("nested-callbacks.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
}

func TestCallbackProbeRetainsContextBoundaries(t *testing.T) {
	for name, body := range map[string]string{
		"deferred input":           `let value = chain(second: fn(item): item + 1, first: fn(): 2)`,
		"deferred optional result": `let value = choose(first: fn(): none, second: fn(): some(3))`,
		"deferred error result":    `let value = choose(first: fn(): error("failed"), second: fn(): Result[Int, String].ok(3))`,
		"partially inferred result": `let value = result(fn():
        if true: return error("failed")
        return ok(4)
    )`,
		"deferred early optional": `let value = choose(first: fn():
        if true: return none
        return some(1)
    , second: fn(): some(2))`,
		"inferred enclosing result": `let value = choose(first: fn():
        let value = try checked()
        return Result[Int, String].ok(value)
    , second: fn(): ok(4))`,
		"optional callback":   `optional(fn(item): item + 1)`,
		"generic constructor": `let callback = Callback(fn(item: Int): item.toString())`,
		"nested captures": `let offset = 7
    let values = [1, 2].map(fn(outer): [3, 4].map(fn(inner): outer + inner + offset))`,
		"contextual nested labels": `let callback: fn(value: Int) -> fn(input: Int) -> Int = apply(value: 1, transform: fn(base): fn(item): fn(extra): item + extra + base)`,
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource("callback-context.ms", callbackDeclarations+"fn first() -> Unit:\n    "+body+"\n", compiler.Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}

func TestCallbackProbeRetainsDiagnostics(t *testing.T) {
	for _, body := range []string{
		`let values = [1].map(fn(outer): [2].map(fn(inner): missing))`,
		`let callback = apply(value: 1, transform: fn(item: String): item.length())`,
		`let callback = choose(first: fn(): 1, second: fn(): "wrong")`,
		`let callback = Callback(fn(item: Int = "wrong"): item)`,
		`var value = 1
    let values = [1].map(fn(item):
        value = 2
        return item
    )`,
		`let callback: fn(value: Int) -> Int = apply(value: 1, transform: fn(base): fn(item: Int = 4): item + base)
    callback()`,
	} {
		result := compiler.CompileSource("callback-errors.ms", callbackDeclarations+"fn first() -> Unit:\n    "+body+"\n", compiler.Options{AnalyzeOnly: true})
		if result.Success() {
			t.Fatalf("accepted invalid callback: %s", body)
		}
	}
}

func TestDeepRejectedCallbackProbesCheckedOnce(t *testing.T) {
	for name, leaf := range map[string]string{
		"unknown binding":     "missing",
		"operand mismatch":    `"wrong" + 1`,
		"incomplete result":   "none",
		"conflicting sibling": `choose(first: fn(): 1, second: fn(): "wrong")`,
	} {
		t.Run(name, func(t *testing.T) {
			expression := strings.Repeat("[1].map(fn(item): ", 40) + leaf + strings.Repeat(")", 40)
			result := compiler.CompileSource("nested-rejected-callbacks.ms", callbackDeclarations+"fn first() -> Unit:\n    let values = "+expression+"\n", compiler.Options{AnalyzeOnly: true})
			if result.Success() || len(result.Diagnostics) > 3 {
				t.Fatalf("lost root error or repeated probe diagnostics: %v", result.Diagnostics)
			}
		})
	}
}

func TestCallbackProbeRetainsCapturedBindingsAndOptionalMetadata(t *testing.T) {
	source := `fn wrap[T](callback: Optional[fn(value: Int) -> T]) -> Unit: return
fn apply[T, U](value: T, transform: fn(value: T) -> U) -> U: transform(value)
fn first() -> Unit:
    let offset = 7
    let result = apply(value: 1, transform: fn(outer): apply(value: 2, transform: fn(inner): outer + inner + offset))
    wrap(fn(item: Int = 4): item + offset)
`
	result := compiler.CompileSource("callback-metadata.ms", source, compiler.Options{AnalyzeOnly: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	lambdas, optional, outerCaptures := 0, 0, 0
	for expression, info := range result.Program.Expressions() {
		if expression.Kind != syntax.KindLambda || expression.Pos.File != "callback-metadata.ms" {
			continue
		}
		lambdas++
		if info.Type.Params[0].Name != "value" || len(info.Type.Defaults) != 0 {
			t.Fatalf("lost contextual label/default erasure: %#v", info.Type)
		}
		for _, capture := range info.Captures {
			if capture.Name != "outer" {
				continue
			}
			outerCaptures++
			found := false
			for _, params := range result.Program.LambdaParameters() {
				for _, binding := range params {
					if binding == capture {
						found = true
					}
				}
			}
			if !found {
				t.Fatal("captured stale speculative parameter binding")
			}
		}
		if info.OptionalArgument != nil {
			optional++
			if info.OptionalArgument.String() != "Optional[fn(value: Int)->Int]" {
				t.Fatal(info.OptionalArgument)
			}
		}
	}
	if lambdas != 3 || optional != 1 || outerCaptures != 1 {
		t.Fatalf("missing callback metadata: lambdas=%d optional=%d outerCaptures=%d", lambdas, optional, outerCaptures)
	}
}
