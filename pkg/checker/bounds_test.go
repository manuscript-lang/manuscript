package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func boundsDiagnostics(t *testing.T, source string) []syntax.Diagnostic {
	t.Helper()
	module, err := parser.Parse("bounds.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	return checker.Check([]*syntax.Module{module}, nil).Diagnostics
}

func TestProvenIndexNarrowsToElementType(t *testing.T) {
	cases := map[string]string{
		"guard": `fn read(index: Int) -> Int:
    let values = [10, 20, 30]
    if index >= 0 and index < values.length():
        let value: Int = values[index]
        return value
    return 0
`,
		"reversed guard": `fn read(values: List[Int], index: Int) -> Int:
    if 0 <= index and values.length() > index:
        return values[index]
    return 0
`,
		"canonical loop": `fn sum(values: List[Int]) -> Int:
    var total = 0
    var i = 0
    while i < values.length():
        total = total + values[i]
        i = i + 1
    return total
`,
		"early exit": `fn read(values: List[Int], index: Int) -> Int:
    if index < 0 or index >= values.length():
        return 0
    return values[index]
`,
		"else branch": `fn read(values: List[Int], index: Int) -> Int:
    if index < 0 or index >= values.length():
        return 0
    else:
        return values[index]
`,
		"right operand": `fn is_zero(values: List[Int], index: Int) -> Bool:
    return index >= 0 and index < values.length() and values[index] == 0
`,
		"or operand": `fn is_zero(values: List[Int], index: Int) -> Bool:
    return index < 0 or index >= values.length() or values[index] == 0
`,
		"literal index": `fn first(values: List[Int]) -> Int:
    if values.length() > 0:
        return values[0]
    return 0
`,
		"literal length": `fn third(values: List[Int]) -> Int:
    if values.length() >= 3:
        let first: Int = values[0]
        let last: Int = values[2]
        return first + last
    return 0
`,
		"guarded argument": `fn show(value: Int) -> Int:
    return value

fn read(values: List[Int], index: Int) -> Int:
    if index >= 0 and index < values.length():
        return show(values[index])
    return 0
`,
		"optional elements stay optional": `fn read(values: List[Optional[Int]], index: Int) -> Optional[Int]:
    if index >= 0 and index < values.length():
        let value: Optional[Int] = values[index]
        return value
    return none
`,
	}
	for name, source := range cases {
		t.Run(name, func(t *testing.T) {
			if diagnostics := boundsDiagnostics(t, source); len(diagnostics) != 0 {
				t.Fatal(diagnostics)
			}
		})
	}
}

func TestUnprovenIndexStaysOptional(t *testing.T) {
	cases := map[string]string{
		"no guard": `fn read(values: List[Int], index: Int) -> Int:
    return values[index]
`,
		"upper bound only": `fn read(values: List[Int], index: Int) -> Int:
    if index < values.length():
        return values[index]
    return 0
`,
		"lower bound only": `fn read(values: List[Int], index: Int) -> Int:
    if index >= 0:
        return values[index]
    return 0
`,
		"non strict upper bound": `fn read(values: List[Int], index: Int) -> Int:
    if index >= 0 and index <= values.length():
        return values[index]
    return 0
`,
		"guard does not leak": `fn read(values: List[Int], index: Int) -> Int:
    if index >= 0 and index < values.length():
        return 1
    return values[index]
`,
		"index of another list": `fn read(values: List[Int], other: List[Int], index: Int) -> Int:
    if index >= 0 and index < other.length():
        return values[index]
    return 0
`,
		"copied length": `fn read(values: List[Int], index: Int) -> Int:
    let count = values.length()
    if index >= 0 and index < count:
        return values[index]
    return 0
`,
		"index reassigned": `fn read(values: List[Int], index: Int) -> Int:
    var at = index
    if at >= 0 and at < values.length():
        at = at + 1
        return values[at]
    return 0
`,
		"list reassigned": `fn read(values: List[Int], index: Int) -> Int:
    var current = values
    if index >= 0 and index < current.length():
        current = []
        return current[index]
    return 0
`,
		"mutation between": `fn read(values: List[Int], index: Int) -> Int:
    if index >= 0 and index < values.length():
        values.pop()
        return values[index]
    return 0
`,
		"call in same statement": `fn shrink(values: List[Int]) -> Int:
    values.pop()
    return 0

fn read(values: List[Int], index: Int) -> Int:
    if index >= 0 and index < values.length():
        return shrink(values) + values[index]
    return 0
`,
		"closure": `fn read(values: List[Int], index: Int) -> fn() -> Int:
    if index >= 0 and index < values.length():
        return fn() -> Int:
            return values[index]
    return fn() -> Int: return 0
`,
		"loop body mutates": `fn drain(values: List[Int]) -> Int:
    var i = 0
    var total = 0
    while i < values.length():
        values.pop()
        total = total + values[i]
        i = i + 1
    return total
`,
		"loop index can decrease": `fn sum(values: List[Int]) -> Int:
    var total = 0
    var i = 0
    while i < values.length():
        total = total + values[i]
        i = i - 1
    return total
`,
		"loop index starts negative": `fn sum(values: List[Int]) -> Int:
    var total = 0
    var i = -1
    while i < values.length():
        i = i + 1
        total = total + values[i]
    return total
`,
		"outer fact does not survive loop": `fn read(values: List[Int], index: Int) -> Int:
    var at = index
    if at >= 0 and at < values.length():
        while true:
            let value: Int = values[at]
            at = at + 1
    return 0
`,
		"literal beyond length": `fn read(values: List[Int]) -> Int:
    if values.length() > 1:
        return values[2]
    return 0
`,
		"flattened index": `fn read(values: List[Int], row: Int, col: Int) -> Int:
    if row >= 0 and col >= 0 and row * 3 + col < values.length():
        return values[row * 3 + col]
    return 0
`,
	}
	for name, source := range cases {
		t.Run(name, func(t *testing.T) {
			diagnostics := boundsDiagnostics(t, source)
			if len(diagnostics) == 0 {
				t.Fatal("lookup was narrowed without a proof")
			}
			for _, d := range diagnostics {
				if !strings.Contains(d.Message, "Optional") {
					t.Fatalf("unexpected diagnostic: %s", d.Message)
				}
			}
		})
	}
}
