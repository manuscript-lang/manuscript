package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestPrimitiveListAppendAndRangeKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("list-loops.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

test "primitive list loops":
    let ints = List[Int]()
    let floats = List[Float]()
    let bools = List[Bool]()
    let words = List[String]()
    var i = 0
    while i < 5:
        ints.append(value: i)
        floats.append(value: 0.5)
        bools.append(value: i % 2 == 0)
        words.append(value: "w{i}")
        i = i + 1
    var sum = 0
    for v in ints:
        sum = sum + v
        if v == 2:
            ints.append(value: 100)
    check(ok: sum == 10, name: "range sees the captured length")
    check(ok: ints.length() == 6, name: "append during range")
    var total = 0.0
    for f in floats:
        total = total + f
    check(ok: total == 2.5, name: "floats")
    var trues = 0
    for b in bools:
        if b:
            trues = trues + 1
    check(ok: trues == 3, name: "bools")
    var joined = ""
    for w in words:
        joined = joined + w
    check(ok: joined == "w0w1w2w3w4", name: "strings")
    let unique = Set[Int]()
    unique.add(value: 4)
    unique.add(value: 7)
    var seen = 0
    for n in unique:
        seen = seen + n
    check(ok: seen == 11, name: "set of ints")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("primitive list loops changed: %v\n%s", err, output)
	}
}
