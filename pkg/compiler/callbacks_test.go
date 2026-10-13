package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"testing"
)

const callbackDeclarations = `import {List} from "@std/collections.ms"
import Result from "@std/result.ms"
import Optional from "@std/optional.ms"
fn apply[T, U](value: T, transform: fn(value: T) -> U) -> U: transform(value)
fn chain[T, U](first: fn() -> T, second: fn(value: T) -> U) -> U: second(first())
fn result[T](transform: fn() -> Result[T, String]) -> Result[T, String]: transform()
fn checked() -> Result[Int, String]: ok(3)
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
		`let pair = Pair(1)`,
		`let pair = TwoPayloads.Pair(1, 2)`,
		`let pair = TwoPayloads.Pair(first: 1, 2)`,
		`let callback = fn(value): value`,
		`let callback = result(fn(): error("failed"))`,
		`let callback: fn(value: Int) -> Int = fn(item): item`,
		`let callback: fn(value: Int) -> Int = fn(): 1`,
		`let callback: fn(value: Int) -> Int = fn(value): "wrong"`,
		`let callback: fn(value: Int) -> Int = fn(value: String): value.length()`,
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
