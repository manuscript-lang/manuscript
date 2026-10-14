package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

const callbackDeclarations = `fn apply[T, U](value: T, transform: fn(value: T) -> U) -> U: transform(value)
fn chain[T, U](first: fn() -> T, second: fn(value: T) -> U) -> U: second(first())
fn result[T](transform: fn() -> Result[T, String]) -> Result[T, String]: transform()
fn checked() -> Result[Int, String]: ok(3)
fn choose[T](first: fn() -> T, second: fn() -> T) -> T: second()
fn optional(transform: Optional[fn(value: Int) -> Int] = none) -> Unit: return
type Box[T]:
    value: T
type Callback[T, U]:
    transform: fn(value: T) -> U
type Choice[T]:
    case Payload(value: T)
type Pair:
    first: Int
    second: Int = 2
type TwoPayloads:
    case Pair(first: Int, second: Int)
interface Read:
    fn get() -> Int
impl Read for Box[Int]:
    fn get() -> Int: self.value
`

func TestContextualCallbacks(t *testing.T) {
	for _, body := range []string{
		`let values = [1, 2].map(fn(value): value.toString()).filter(fn(value): value != "")`,
		`let result: String = apply(transform: fn(value): value.toString(), value: 1)`,
		`let result = chain(second: fn(value): value + 1, first: fn(): 2)`,
		`let callback: fn(value: Int) -> Int = fn(value): value + 1`,
		`let callback = fn(value: Int): value + 1`,
		`let values = [1, 2].filter(fn(item: Int) -> Bool: item > 1).map(fn(number): number.toString()).join(",")`,
		`let result = apply(transform: fn(item): item.toString(), value: 1)`,
		`let callback: fn(value: Int) -> Int = fn(item): item`,
		`let callback: fn(left: Int, right: Int) -> Int = fn(a, b): a - b`,
		`let callback = Callback(fn(item: Int): item.toString())`,
		`optional(fn(item): item + 1)`,
		`let callbacks: List[fn(value: Int) -> Int] = [fn(item): item + 1]`,
		`let callback = Callback[Int, String](fn(value): value.toString())`,
		`let callback = Callback(fn(value: Int): value.toString())`,
		`optional(fn(value): value + 1)`,
		`let callbacks: List[fn(value: Int) -> Int] = [fn(value): value + 1]`,
		`let choice: Choice[fn(value: Int) -> Int] = Choice.Payload(fn(value): value + 1)`,
		`let view = Read(Box(1))`,
		`let callback = fn(): unit`,
		`let value: Result[Int, String] = result(fn(): ok(4))`,
		`let value = result(fn():
        let n = try checked()
        return ok(n)
    )`,
		`let value = result(fn():
        if true: return error("failed")
        return ok(4)
    )`,
	} {
		result := compiler.CompileSource("callbacks.ms", callbackDeclarations+"fn example() -> Unit:\n    "+body+"\n", compiler.Options{})
		if !result.Success() {
			t.Errorf("%s: %v", body, result.Diagnostics)
		}
	}
}

func TestCallbackInferenceRejections(t *testing.T) {
	for _, body := range []string{
		`let original = fn(item: Int): item
    let incompatible: fn(value: Int) -> Int = original`,
		`let callback: fn(left: Int, right: Int) -> Int = fn(a, b): a - b
    callback(a: 1, b: 2)`,
		`let callback: fn(value: Int) -> Int = fn(item: Int = 4): item
    callback()`,
		`let callback = fn(value): value`,
		`let callback = result(fn(): error("failed"))`,

		`let callback: fn(value: Int) -> Int = fn(): 1`,
		`let callback: fn(value: Int) -> Int = fn(value): "wrong"`,
		`let callback: fn(value: Int) -> Int = fn(value: String): value.length`,
		`let callback = fn(value: Bool):
        if value: return 1
        return "wrong"`,
		`let callback = fn(value: Bool):
        if value: return 1`,
		`let callback: fn(value: Int) -> Int = fn(value):
        value + 1`,
	} {
		result := compiler.CompileSource("callbacks.ms", callbackDeclarations+"fn example() -> Unit:\n    "+body+"\n", compiler.Options{AnalyzeOnly: true})
		if result.Success() {
			t.Errorf("accepted %s", body)
		}
	}
}

func TestInvalidCallbackInferenceDoesNotCascade(t *testing.T) {
	for _, body := range []string{
		`let names = [1, 2].map(fn(item): missing).join(",")`,
		`let names = [1, 2].map(fn(item): missing)
    names.join(",")`,
		`let names = [1].map(fn(item): missing)
    let next = names.map[String]`,
		`let name = apply(value: 1, transform: fn(item): missing)
    name.toString()`,
		`let callback = Callback(fn(item: Int): missing)`,
		`let name = choose(first: fn(): missing, second: fn(): "known")`,
		`let name = choose(first: fn(): "known", second: fn(): missing)`,
	} {
		result := compiler.CompileSource("callbacks.ms", callbackDeclarations+"fn example() -> Unit:\n    "+body+"\n", compiler.Options{AnalyzeOnly: true})
		if len(result.Diagnostics) != 1 || !strings.Contains(result.Diagnostics[0].Message, "unknown binding missing") {
			t.Errorf("%s: expected only the callback's root error, got %v", body, result.Diagnostics)
		}
	}
}

func TestInvalidCallbackPreservesIndependentDiagnostics(t *testing.T) {
	source := callbackDeclarations + `fn example() -> Unit:
    let names = [1, 2].map(fn(item): missing).join(other_missing)
    let conflict = apply(value: 1, transform: fn(item: String): missing_result)
    let wrong: Int = "text"
    let callback: fn(value: Int) -> Int = fn(): missing_too
`
	result := compiler.CompileSource("callbacks.ms", source, compiler.Options{AnalyzeOnly: true})
	for _, message := range []string{"unknown binding missing", "unknown binding other_missing", "conflicting generic inference", "unknown binding missing_result", "expected Int, found String", "callback parameter count does not match", "unknown binding missing_too"} {
		found := false
		for _, diagnostic := range result.Diagnostics {
			found = found || strings.Contains(diagnostic.Message, message)
		}
		if !found {
			t.Errorf("missing %q in %v", message, result.Diagnostics)
		}
	}
}

func TestUnknownCallbackLabelDoesNotConflictWithInference(t *testing.T) {
	source := callbackDeclarations + `fn example() -> Unit:
    choose(first: fn(): "a", second: fn(): "b", other: fn(): missing)
`
	result := compiler.CompileSource("callbacks.ms", source, compiler.Options{AnalyzeOnly: true})
	if result.Success() {
		t.Fatal("accepted unknown callback argument")
	}
	for _, diagnostic := range result.Diagnostics {
		if strings.Contains(diagnostic.Message, "conflicting generic inference") {
			t.Fatal(result.Diagnostics)
		}
	}
}
