package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestPrimitiveListLiteralsOwnFreshStorage(t *testing.T) {
	result := compiler.CompileSource("list-literals.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) Unit:
    if not ok:
        return panic(message: name)

fn fresh() List[Int]:
    return [1, 2, 3]

test "literals":
    let a = fresh()
    let b = fresh()
    a.append(value: 4)
    check(ok: a.length() == 4 and b.length() == 3, name: "each evaluation is fresh")
    let floats = [1.5, 2.5]
    let flags = [true, false, true]
    let words = ["a", "b"]
    let empty = List[Int]()
    check(ok: floats.length() == 2 and flags.length() == 3 and words.length() == 2 and empty.length() == 0, name: "lengths")
    floats.append(value: 3.5)
    words.append(value: "c")
    check(ok: floats.at(index: 2) == some(3.5) and words.at(index: 2) == some("c"), name: "append typed")
    check(ok: [1, 2] == [1, 2] and not ([1, 2] == [2, 1]), name: "equality")
    let rows = [[1], [2, 3]]
    check(ok: rows.at(index: 1) == some([2, 3]), name: "nested")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("list literals changed: %v\n%s", err, output)
	}
}
