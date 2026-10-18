package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestTypedNumericFaults(t *testing.T) {
	result := compiler.CompileSource("numeric-faults.ms", `fn add(a: Int, b: Int) Int: return a + b
fn subtract(a: Int, b: Int) Int: return a - b
fn multiply(a: Int, b: Int) Int: return a * b
fn divide(a: Int, b: Int) Int: return a / b
fn remainder(a: Int, b: Int) Int: return a % b
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

fn negate(a: Int) Int: return -a
fn flip(a: Float) Float: return -a
fn check(ok: Bool, name: String) Unit:
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
import StringBuilder from "@std/string.ms"

type Folded:
    name: String

impl Equal for Folded:
    fn equals(other: Equal) Bool:
        return true

impl Hashable for Folded:
    fn hash() Int:
        return 1

fn check(ok: Bool, name: String) Unit:
    if not ok:
        return panic(message: name)

fn replace_first[T](xs: List[T], value: T) List[T]:
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
    let mapped = a.map(transform: fn(value: Folded) Folded: return Folded(name: "z"))
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

func TestNestedTryReturnsInSourceOrder(t *testing.T) {
	result := compiler.CompileSource("nested_try.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) Unit:
    if not ok:
        return panic(message: name)

fn step(log: List[String], name: String, n: Int) Result[Int, String]:
    log.append(value: name)
    if n < 0:
        return error(cause: name)
    return ok(value: n)

fn add(x: Int, y: Int) Int:
    return x + y

fn sum(log: List[String], a: Int, b: Int) Result[Int, String]:
    let v = (try step(log: log, name: "a", n: a)) + (try step(log: log, name: "b", n: b))
    log.append(value: "done")
    return ok(value: v)

fn arguments(log: List[String], a: Int, b: Int) Result[Int, String]:
    return ok(value: add(x: try step(log: log, name: "x", n: a), y: try step(log: log, name: "y", n: b)))

fn effect_first(log: List[String], a: Int) Result[Int, String]:
    log.append(value: "before")
    let v = add(x: 1, y: try step(log: log, name: "s", n: a))
    return ok(value: v)

fn loop(log: List[String], n: Int) Result[Int, String]:
    var total = 0
    var i = 0
    while i < n:
        total = total + try step(log: log, name: "l", n: 1 - i)
        i = i + 1
    return ok(value: total)

fn joined(log: List[String]) Result[String, String]:
    return ok(value: "{try step(log: log, name: "p", n: 1)}-{try step(log: log, name: "q", n: -1)}")

fn text(log: List[String]) String:
    return log.join(separator: ",")

test "nested try":
    let first = List[String]()
    check(ok: sum(log: first, a: 1, b: 2).get() == 3, name: "sum")
    check(ok: text(log: first) == "a,b,done", name: "order")
    let second = List[String]()
    check(ok: sum(log: second, a: -1, b: 2).err() == "a", name: "first cause")
    check(ok: text(log: second) == "a", name: "stops at the first failure")
    let third = List[String]()
    check(ok: arguments(log: third, a: 1, b: -1).err() == "y", name: "argument cause")
    check(ok: text(log: third) == "x,y", name: "argument order")
    let fourth = List[String]()
    check(ok: effect_first(log: fourth, a: -1).err() == "s", name: "effect cause")
    check(ok: text(log: fourth) == "before,s", name: "effects before try")
    let fifth = List[String]()
    check(ok: loop(log: fifth, n: 5).err() == "l", name: "loop cause")
    check(ok: text(log: fifth) == "l,l,l", name: "loop stops")
    let sixth = List[String]()
    check(ok: joined(log: sixth).err() == "q", name: "text cause")
    check(ok: text(log: sixth) == "p,q", name: "text order")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
		t.Fatalf("nested try changed: %v\n%s", err, output)
	}
}
