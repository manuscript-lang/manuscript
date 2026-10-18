package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestUnprovenIndexIsRejectedAsInt(t *testing.T) {
	result := compiler.CompileSource("unproven.ms", "fn read(values: List[Int], index: Int) Int:\n    if index < values.length():\n        return values[index]\n    return 0\n", compiler.Options{})
	rejected(t, result, "type", "expected Int, found Optional[Int]")
}

func TestLoopConditionCallsInvalidateLengthFacts(t *testing.T) {
	source := `fn shrink(values: List[Int]) Bool:
    values.pop()
    return values.length() > 0

fn read(values: List[Int]) Int:
    var total = 0
    if 2 < values.length():
        while shrink(values):
            let value = values[2]
            total += value
    return total
`
	result := compiler.CompileSource("loop_condition_mutation.ms", source, compiler.Options{})
	rejected(t, result, "type", "Optional[Int]")
}

func TestProvenIndexKeepsOptionalForm(t *testing.T) {
	source := `import expect_equal from "@std/testing.ms"

fn pick(values: List[Int], index: Int) Optional[Int]:
    if index >= 0 and index < values.length():
        let found: Optional[Int] = values[index]
        return found

    return none

test "proven lookup assigns to an Optional":
    expect_equal(pick([4, 5], 1), some(5))
    expect_equal(pick([4, 5], 2), none)
`
	result := compiler.CompileSource("proven_optional.ms", source, compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(data)), "1 tests, 0 failed") {
		t.Fatalf("proven optional: %v\n%s", err, data)
	}
}
