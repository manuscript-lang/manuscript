package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestTypedNumericFaults(t *testing.T) {
	result := compiler.CompileSource("numeric-faults.ms", `fn add(a: Int, b: Int) -> Int: return a + b
fn subtract(a: Int, b: Int) -> Int: return a - b
fn multiply(a: Int, b: Int) -> Int: return a * b
fn divide(a: Int, b: Int) -> Int: return a / b
fn remainder(a: Int, b: Int) -> Int: return a % b
test "add high":
    let bad = add(a: 9223372036854775807, b: 1)
test "add low":
    let bad = add(a: -9223372036854775808, b: -1)
test "subtract high":
    let bad = subtract(a: 9223372036854775807, b: -1)
test "subtract low":
    let bad = subtract(a: -9223372036854775808, b: 1)
test "multiply high":
    let bad = multiply(a: 9223372036854775807, b: 2)
test "multiply minimum":
    let bad = multiply(a: -9223372036854775808, b: -1)
test "divide minimum":
    let bad = divide(a: -9223372036854775808, b: -1)
test "divide zero":
    let bad = divide(a: 1, b: 0)
test "remainder zero":
    let bad = remainder(a: 1, b: 0)
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err == nil || !strings.Contains(string(output), "9 tests, 9 failed") {
		t.Fatalf("numeric faults were lost: %v\n%s", err, output)
	}
	if strings.Count(string(output), "Int overflow;") != 6 || strings.Count(string(output), "Int./: overflow;") != 1 || strings.Count(string(output), "division by zero;") != 1 || strings.Count(string(output), "remainder by zero;") != 1 {
		t.Fatalf("numeric fault identities changed: %s", output)
	}
}

func TestTypedNegation(t *testing.T) {
	result := compiler.CompileSource("negation.ms", `import panic from "@std/faults.ms"

fn negate(a: Int) -> Int: return -a
fn flip(a: Float) -> Float: return -a
fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)
test "negation":
    check(ok: negate(a: 5) == -5, name: "five")
    check(ok: negate(a: -7) == 7, name: "minus seven")
    check(ok: negate(a: 0) == 0, name: "zero")
    check(ok: negate(a: 9223372036854775807) == -9223372036854775807, name: "maximum")
    check(ok: -9223372036854775808 == negate(a: 9223372036854775807) - 1, name: "minimum literal")
    check(ok: flip(a: 1.5) == -1.5, name: "float")
    check(ok: 1.0 / flip(a: 0.0) < 0.0, name: "negative zero")
    check(ok: 1.0 / -0.0 < 0.0, name: "literal negative zero")
    var count = -3
    count = count + 1
    check(ok: count == -2, name: "typed local")
test "negate minimum":
    let bad = negate(a: -9223372036854775808)
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err == nil || !strings.Contains(string(output), "2 tests, 1 failed") || strings.Count(string(output), "Int overflow;") != 1 {
		t.Fatalf("negation changed: %v\n%s", err, output)
	}
}

func TestBoundNativeMembersKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("bound.ms", `import panic from "@std/faults.ms"
import {List, Set, Map} from "@std/collections.ms"
import StringBuilder from "@std/string.ms"

type Folded:
    name: String

impl Equal for Folded:
    fn equals(other: Equal) -> Bool:
        return true

impl Hashable for Folded:
    fn hash() -> Int:
        return 1

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn replace_first[T](xs: List[T], value: T) -> List[T]:
    return xs.set(index: 0, value: value)

test "string members":
    check(ok: "  a,b ".trim().split(separator: ",").length() == 2, name: "trim split")
    check(ok: "abc".upper() == "ABC", name: "upper")
test "list members":
    let xs = [1, 2, 3]
    xs.set(index: -1, value: 9)
    check(ok: xs.at(index: 2) == some(9), name: "negative set")
    check(ok: replace_first(xs: xs, value: 5).at(index: 0) == some(5), name: "generic set")
    check(ok: xs.contains(value: 9), name: "contains")
test "custom equality is kept for bound members":
    let a = Set[Folded]()
    a.add(value: Folded(name: "x"))
    a.add(value: Folded(name: "y"))
    check(ok: a.length() == 1, name: "set add uses Equal")
    let mapped = a.map(transform: fn(value: Folded) -> Folded: return Folded(name: "z"))
    check(ok: mapped.length() == 1, name: "set map deduplicates")
test "builder":
    let sb = StringBuilder()
    sb.append("a")
    sb.append("b")
    check(ok: sb.freeze() == "ab", name: "freeze")
    check(ok: sb.freeze() == "ab", name: "repeat freeze")
test "sealed builder":
    let sb = StringBuilder()
    sb.freeze()
    sb.append("late")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err == nil || !strings.Contains(string(output), "5 tests, 1 failed") || strings.Count(string(output), "builder is sealed") != 1 {
		t.Fatalf("bound members changed: %v\n%s", err, output)
	}
}
