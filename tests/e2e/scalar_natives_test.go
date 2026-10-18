package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

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

func TestNegativeSplitCapStillFaults(t *testing.T) {
	result := compiler.CompileSource("split-fault.ms", `test "negative":
    "a,b".split(separator: ",", max_parts: some(0 - 1))
`, compiler.Options{Tests: true})
	output, _ := execute(t, result)
	if !strings.Contains(string(output), "max_parts must be nonnegative") {
		t.Fatalf("expected split fault\n%s", output)
	}
}
