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
