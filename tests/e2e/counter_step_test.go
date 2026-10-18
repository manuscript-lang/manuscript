package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestGuardedCounterStepsKeepOverflowFaults(t *testing.T) {
	result := compiler.CompileSource("counter-step.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) Unit:
    if not ok:
        return panic(message: name)

fn count_up(limit: Int) Int:
    var i = limit - 3
    var steps = 0
    while i < limit:
        steps = steps + 1
        i = i + 1
    return steps

fn count_down(limit: Int) Int:
    var i = limit + 3
    var steps = 0
    while i > limit:
        steps = steps + 1
        i = i - 1
    return steps

fn reset_then_step() Int:
    var i = 0
    while i < 1:
        i = 9223372036854775807
        i = i + 1
    return i

fn nested_reset(flag: Bool) Int:
    var i = 0
    while i < 1:
        if flag:
            i = 9223372036854775807
        i = i + 1
    return i

test "counts reach the extreme without a fault":
    check(ok: count_up(limit: 9223372036854775807) == 3, name: "up to maximum")
    check(ok: count_down(limit: -9223372036854775807) == 3, name: "down to minimum")

test "reassigned counter still faults":
    let bad = reset_then_step()

test "conditionally reassigned counter still faults":
    let bad = nested_reset(flag: true)
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err == nil || !strings.Contains(string(output), "3 tests, 2 failed") || strings.Count(string(output), "Int overflow;") != 2 {
		t.Fatalf("counter step proof changed overflow behavior: %v\n%s", err, output)
	}
}
