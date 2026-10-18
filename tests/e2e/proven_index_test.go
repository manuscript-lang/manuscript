package e2e_test

import (
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
