package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestIntKeyedMapCallsKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("int-map.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn lookup(m: Map[Int, String], key: Int) -> String:
    match m.get(key: key):
        some(v):
            return v
        none:
            return "missing"

test "int map":
    let m = Map[Int, String]()
    m.add(key: 1, value: "a")
    m.add(key: 2, value: "b")
    m.add(key: 1, value: "c")
    check(ok: m.length() == 2, name: "replace keeps size")
    check(ok: lookup(m: m, key: 1) == "c", name: "replaced value")
    check(ok: lookup(m: m, key: 2) == "b", name: "second")
    check(ok: lookup(m: m, key: 3) == "missing", name: "absent")
    var total = 0
    for entry in m:
        m.add(key: 10 + total, value: "x")
        total = total + 1
    check(ok: total == 2 and m.length() == 4, name: "mutation during iteration")
    check(ok: lookup(m: Map[Int, String](), key: 0) == "missing", name: "empty")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("int map changed: %v\n%s", err, output)
	}
}
