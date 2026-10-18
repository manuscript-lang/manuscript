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
	result := compiler.CompileSource("negation.ms", `import {expect_true, fail} from "@std/testing.ms"

fn negate(a: Int) Int: return -a
fn flip(a: Float) Float: return -a
test "negation":
    (negate(a: 5) == -5) | try expect_true
    (negate(a: -7) == 7) | try expect_true
    (negate(a: 0) == 0) | try expect_true
    (negate(a: 9223372036854775807) == -9223372036854775807) | try expect_true
    (-9223372036854775808 == negate(a: 9223372036854775807) - 1) | try expect_true
    (flip(a: 1.5) == -1.5) | try expect_true
    (1.0 / flip(a: 0.0) < 0.0) | try expect_true
    (1.0 / -0.0 < 0.0) | try expect_true
    var count = -3
    count = count + 1
    (count == -2) | try expect_true
test "negate minimum":
    let bad = negate(a: -9223372036854775808)
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err == nil || !strings.Contains(string(output), "2 tests, 1 failed") || strings.Count(string(output), "Int overflow;") != 1 {
		t.Fatalf("negation changed: %v\n%s", err, output)
	}
}

func TestBoundNativeMembersKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("bound.ms", `import {expect_true, fail} from "@std/testing.ms"
import StringBuilder from "@std/string.ms"

type Folded:
    name: String

impl Equal for Folded:
    fn equals(other: Equal) Bool:
        return true

impl Hashable for Folded:
    fn hash() Int:
        return 1


fn replace_first[T](xs: List[T], value: T) List[T]:
    return xs.set(index: 0, value: value)

test "string members":
    ("  a,b ".trim().split(separator: ",").length() == 2) | try expect_true
    ("abc".upper() == "ABC") | try expect_true
test "list members":
    let xs = [1, 2, 3]
    xs.set(index: -1, value: 9)
    (xs.get(index: 2) == 9) | try expect_true
    (replace_first(xs: xs, value: 5).get(index: 0) == 5) | try expect_true
    (xs.contains(value: 9)) | try expect_true
test "custom equality is kept for bound members":
    let a = Set[Folded]()
    a.add(value: Folded(name: "x"))
    a.add(value: Folded(name: "y"))
    (a.length() == 1) | try expect_true
    let mapped = a.map(transform: fn(value: Folded) Folded: return Folded(name: "z"))
    (mapped.length() == 1) | try expect_true
test "builder":
    let sb = StringBuilder()
    sb.append("a")
    sb.append("b")
    (sb.freeze() == "ab") | try expect_true
    (sb.freeze() == "ab") | try expect_true
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
