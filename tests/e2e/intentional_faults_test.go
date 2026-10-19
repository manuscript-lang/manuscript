package e2e_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

// Fault injection and Never contracts live in Go source strings. Physical .ms tests use Result errors.
func TestIntentionalFaultContracts(t *testing.T) {
	for _, fixture := range []struct{ name, source string }{
		{"cl-06", `import {expect_equal} from "@std/testing.ms"
import panic from "@std/faults.ms"

fn positive(value: Int) Int:
    if value > 0:
        return value
    else:
        panic(message: "positive value required")

fn discard(value: Int) Unit:
    return

test "return contracts":
    positive(value: 3) | try expect_equal(expected: 3)
    discard(value: 1) | try expect_equal(expected: unit)
`},
		{"cl-17", `import {expect_contains, expect_fault} from "@std/testing.ms"
import panic from "@std/faults.ms"

fn failed_initializer() Never:
    let impossible: Int = panic(message: "initializer cannot return")

fn returned_failure() Int:
    return panic(message: "result cannot return")

fn endless() Int:
    while true:
        continue

test "Never faults propagate through initializers and returned values":
    try expect_contains(
        try expect_fault(
            fn():
                let impossible = failed_initializer()
        ),
        "initializer cannot return"
    )
    try expect_contains(
        try expect_fault(
            fn():
                let impossible = returned_failure()
        ),
        "result cannot return"
    )
`},
		{"expect-fault", `import {expect_contains, expect_fault} from "@std/testing.ms"
import panic from "@std/faults.ms"
test "expect_fault reports the injected fault":
    try expect_contains(try expect_fault(fn(): panic("boom")), "boom")
`},
	} {
		t.Run(fixture.name, func(t *testing.T) {
			result := compiler.CompileSource(fixture.name+".ms", fixture.source, compiler.Options{Tests: true})
			output, err := execute(t, result)
			if err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
				t.Fatalf("fault contract: %v\n%s", err, output)
			}
		})
	}
}
