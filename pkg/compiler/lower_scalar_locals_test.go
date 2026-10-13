package compiler

import (
	"strings"
	"testing"
)

func TestScalarLocalStorageUsesCheckedIdentity(t *testing.T) {
	result := CompileSource("locals.ms", `fn identity[T](value: T) -> T:
    let copy = value
    return copy
fn locals(input: Int) -> Int:
    var number = input
    var floating = 0.5
    var flag = false
    let saved = number
    let callback = fn() -> Int: saved
    number = number + 1
    floating = floating + 1.0
    flag = not flag
    return callback() + number
fn calls(input: Int) -> Int:
    var forwarded = identity(input)
    var accumulator = 0
    accumulator = identity(forwarded)
    return accumulator
fn integer_identity(value: Int) -> Int:
    let copy_int = value
    return copy_int
fn float_identity(value: Float) -> Float:
    let copy_float = value
    return copy_float
fn integer_payload(value: Result[Int, String]) -> Result[Int, String]:
    var payload_int = 0
    payload_int = try value
    return ok(payload_int)
fn float_payload(value: Result[Float, String]) -> Result[Float, String]:
    var payload_float = 0.0
    payload_float = try value
    return ok(payload_float)
fn positive_identity(value: Float) -> Float:
    var positive = value
    positive = +positive
    return positive
`, Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, fragment := range []string{"_number int64 =", "_floating float64 =", "_flag bool =", "_saved rt.Value =", "_copy rt.Value =", "_forwarded rt.Value =", "_accumulator rt.Value =", "_copy_int rt.Value =", "_copy_float rt.Value =", "_payload_int rt.Value =", "_payload_float rt.Value =", "_positive rt.Value ="} {
		if !strings.Contains(result.Source, fragment) {
			t.Fatalf("missing %q in generated source:\n%s", fragment, result.Source)
		}
	}
}
