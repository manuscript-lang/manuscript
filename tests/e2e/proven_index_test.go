package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestProvenIndexNarrowsAndExecutes(t *testing.T) {
	source := `import expect_equal from "@std/testing.ms"

fn read(values: List[Int], index: Int) -> Int:
    if index < 0 or index >= values.length():
        return -1

    return values[index]

fn total(values: List[Int]) -> Int:
    var sum = 0
    var i = 0

    while i < values.length():
        sum = sum + values[i]
        i = i + 1

    return sum

fn nested(values: List[Optional[Int]], index: Int) -> Optional[Int]:
    if index >= 0 and index < values.length():
        return values[index]

    return none

test "guarded and looped lookups":
    expect_equal(read([1, 2, 3], 1), 2)
    expect_equal(read([1, 2, 3], 3), -1)
    expect_equal(read([1, 2, 3], -1), -1)
    expect_equal(total([1, 2, 3]), 6)
    expect_equal(nested([some(1), none], 1), none)
    expect_equal(nested([some(1), none], 0), some(1))
`
	result := compiler.CompileSource("proven_index.ms", source, compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(data)), "1 tests, 0 failed") {
		t.Fatalf("proven index: %v\n%s", err, data)
	}
}

func TestUnprovenIndexIsRejectedAsInt(t *testing.T) {
	result := compiler.CompileSource("unproven.ms", "fn read(values: List[Int], index: Int) -> Int:\n    if index < values.length():\n        return values[index]\n    return 0\n", compiler.Options{})
	rejected(t, result, "type", "expected Int, found Optional[Int]")
}

func TestLoopConditionCallsInvalidateLengthFacts(t *testing.T) {
	source := `fn shrink(values: List[Int]) -> Bool:
    values.pop()
    return values.length() > 0

fn read(values: List[Int]) -> Int:
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
