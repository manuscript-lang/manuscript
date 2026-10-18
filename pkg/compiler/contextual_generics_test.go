package compiler_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

const contextualGenericsSource = `import {TextError} from "@std/errors.ms"
import panic from "@std/faults.ms"
fn fail[T](message: String) Result[T, TextError]: error(TextError(message))
fn fail_cause[T, E: Error](cause: E) Result[T, E]: error(cause)
fn absent[T]() Optional[T]: none
fn identity[T](value: T) T: value
fn convert[T, U](value: T) Optional[U]: none
fn from_callback[T](factory: fn() T) T: factory()
fn transform[T, U](callback: fn(value: T) U) fn(value: T) U: callback
fn repeated[T]() Pair[T, T]: panic("not called")
fn unused[T]() Int: 0
fn constrained[T: Equal]() Optional[T]: none
type Pair[A, B]:
    first: A
    second: B
type Holder:
    value: Optional[Int]
type Failure:
    detail: String
impl Error for Failure:
    fn message() String: self.detail
fn consume(value: Optional[Int]) Unit: return
`

func TestExpectedResultGenericInference(t *testing.T) {
	for name, source := range map[string]string{
		"return": `fn first() Result[Int, TextError]: fail("empty")`,
		"binding": `fn first() Unit:
    let result: Result[Int, TextError] = fail("empty")`,
		"nested":          `fn first() Result[List[Optional[Int]], TextError]: fail("empty")`,
		"outer generic":   `fn first[T]() Result[T, TextError]: fail("empty")`,
		"known arguments": `fn first() Optional[String]: convert(1)`,
		"argument":        `fn first() Unit: consume(absent())`,
		"field":           `fn first() Holder: Holder(absent())`,
		"callback return": `fn first() Unit:
    let callback: fn() Optional[Int] = fn(): absent()`,
		"callback inputs":            `fn first() fn(value: Int) String: transform(fn(item): item.to_string())`,
		"callback factory":           `fn first() Optional[Int]: from_callback(fn(): absent())`,
		"native callback":            `fn first() List[Optional[Int]]: [1].map(fn(item): absent())`,
		"empty argument":             `fn first() List[Int]: identity([])`,
		"optional argument wrapping": `fn first() Unit: consume(identity(1))`,
		"anonymous label context":    `fn first() fn(value: Int) Int: identity(fn(item: Int): item)`,
		"none argument":              `fn first() Optional[Int]: identity(none)`,
		"explicit":                   `fn first() Result[Int, TextError]: fail[Int]("empty")`,
		"error boundary":             `fn first() Result[Int, Error]: fail_cause(Failure("empty"))`,
		"fixed error boundary": `fn failed[T]() Result[T, Failure]: error(Failure("empty"))
fn first() Result[Int, Error]: failed()`,
		"generic error boundary": `fn first[E: Error](cause: E) Result[Int, Error]: fail_cause(cause)`,
		"bare error boundary":    `fn first() Error: identity(Failure("empty"))`,
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource("context.ms", contextualGenericsSource+source+"\n", compiler.Options{AnalyzeOnly: true})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}

func TestExpectedResultGenericInferenceRejects(t *testing.T) {
	for _, tt := range []struct{ name, source, want string }{
		{"no context", `fn first() Unit: let value = absent()`, "cannot infer type argument T"},
		{"unused parameter", `fn first() Int: unused()`, "cannot infer type argument T"},
		{"argument conflict", `fn first() String: identity(1)`, "expected String, found Int"},
		{"repeated context conflict", `fn first() Pair[Int, String]: repeated()`, "conflicting generic inference"},
		{"bounds", `fn first() Optional[fn() Int]: constrained()`, "does not satisfy Equal"},
		{"explicit conflict", `fn first() Optional[String]: absent[Int]()`, "expected Optional[String], found Optional[Int]"},
		{"numeric conversion", `fn first() Float: identity(1)`, "expected Float, found Int"},
		{"optional wrapping", `fn first() Optional[Int]: identity(1)`, "expected Optional[Int], found Int"},
		{"no implicit interface", `interface Read:
    fn get() Int
type Box:
    value: Int
impl Read for Box:
    fn get() Int: self.value
fn first() Read: identity(Box(1))`, "expected Read, found Box"},
		{"function label", `fn first() fn(value: Int) Int:
    let callback = fn(item: Int): item
    return identity(callback)`, "expected fn(value: Int) Int"},
		{"context erases callback defaults", `fn first() Unit:
    let callback: fn(value: Int) Int = from_callback(fn(): fn(value: Int = 4): value)
    callback()`, "missing argument value"},
		{"context erases mutable callback defaults", `fn required(value: Int) Int: value
fn first() Unit:
    var callback: fn(value: Int) Int = from_callback(fn(): fn(value: Int = 4): value)
    callback = required
    callback()`, "missing argument value"},
		{"bare generic value", `fn first() Unit:
    let value: fn(message: String) Result[Int, TextError] = fail`, "requires explicit specialization"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			result := compiler.CompileSource("context.ms", contextualGenericsSource+tt.source+"\n", compiler.Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("invalid program accepted")
			}
			if !strings.Contains(fmt.Sprint(result.Diagnostics), tt.want) {
				t.Fatalf("want %q, got %v", tt.want, result.Diagnostics)
			}
		})
	}
}
