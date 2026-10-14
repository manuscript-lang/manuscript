package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestScalarStandardCallsMatchDynamicCalls(t *testing.T) {
	result := compiler.CompileSource("scalar-natives.ms", `import panic from "@std/faults.ms"
import {abs, abs_int, atan2, ceil, floor, max, min, pow, remainder, round, sqrt, truncate} from "@std/math.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn viaValue(f: fn(value: Float) -> Float, x: Float) -> Float: f(value: x)

test "typed math":
    check(ok: sqrt(value: 9.0) == 3.0, name: "sqrt")
    check(ok: viaValue(f: sqrt, x: 16.0) == 4.0, name: "sqrt value")
    check(ok: abs(value: 0.0 - 2.5) == 2.5 and abs_int(value: 0 - 7) == 7, name: "abs")
    check(ok: floor(value: 2.7) == 2.0 and ceil(value: 2.1) == 3.0 and truncate(value: 0.0 - 2.7) == 0.0 - 2.0, name: "rounding")
    check(ok: round(value: 2.5) == 3.0 and round(value: 0.0 - 2.5) == 0.0 - 2.0, name: "round half up")
    check(ok: pow(base: 2.0, exponent: 10.0) == 1024.0, name: "pow")
    check(ok: min(left: 1.0, right: 2.0) == 1.0 and max(left: 1.0, right: 2.0) == 2.0, name: "min max")
    check(ok: remainder(left: 7.0, right: 4.0) == 3.0, name: "remainder")
    check(ok: atan2(y: 0.0, x: 1.0) == 0.0, name: "atan2")
    check(ok: sqrt(value: 0.0 - 1.0).is_nan and sqrt(value: 1.0).is_finite, name: "classification")
    var total = 0.0
    var i = 0
    while i < 4:
        total = total + sqrt(value: 4.0) + abs(value: 0.0 - 1.0)
        i = i + 1
    check(ok: total == 12.0, name: "typed accumulation")

test "typed string members":
    let text = "  Hello World  "
    check(ok: text.trim() == "Hello World", name: "trim")
    check(ok: text.trim().upper() == "HELLO WORLD" and text.trim().lower() == "hello world", name: "case")
    check(ok: text.contains(value: "World") and not text.contains(value: "world"), name: "contains")
    check(ok: text.trim().starts_with(prefix: "Hello") and text.trim().ends_with(suffix: "World"), name: "affixes")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("scalar standard calls changed: %v\n%s", err, output)
	}
}

func TestAbsIntOverflowStillFaults(t *testing.T) {
	result := compiler.CompileSource("abs-overflow.ms", `import {abs_int} from "@std/math.ms"

test "overflow":
    let smallest = 0 - 9223372036854775807 - 1
    abs_int(value: smallest)
`, compiler.Options{Tests: true})
	output, _ := execute(t, result)
	if !strings.Contains(string(output), "Int overflow") {
		t.Fatalf("expected overflow fault\n%s", output)
	}
}
