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
    check(ok: m.length == 2, name: "replace keeps size")
    check(ok: lookup(m: m, key: 1) == "c", name: "replaced value")
    check(ok: lookup(m: m, key: 2) == "b", name: "second")
    check(ok: lookup(m: m, key: 3) == "missing", name: "absent")
    var total = 0
    for entry in m:
        m.add(key: 10 + total, value: "x")
        total = total + 1
    check(ok: total == 2 and m.length == 4, name: "mutation during iteration")
    check(ok: lookup(m: Map[Int, String](), key: 0) == "missing", name: "empty")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("int map changed: %v\n%s", err, output)
	}
}

func TestStringKeyedMapCallsKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("string-map.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn lookup(m: Map[String, Int], key: String) -> Int:
    match m.get(key: key):
        some(v):
            return v
        none:
            return -1

test "string map":
    let m = Map[String, Int]()
    m.add(key: "a", value: 1)
    m.add(key: "b", value: 2)
    m.add(key: "a", value: 3)
    check(ok: m.length == 2, name: "replace keeps size")
    check(ok: lookup(m: m, key: "a") == 3 and lookup(m: m, key: "b") == 2, name: "values")
    check(ok: lookup(m: m, key: "c") == -1, name: "absent")
    check(ok: lookup(m: Map[String, Int](), key: "a") == -1, name: "empty")
    m.add(key: "", value: 9)
    check(ok: lookup(m: m, key: "") == 9, name: "empty key")
    var seen = 0
    for entry in m:
        m.add(key: "x{seen}", value: seen)
        seen = seen + 1
    check(ok: seen == 3 and m.length == 6, name: "mutation during iteration")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("string map changed: %v\n%s", err, output)
	}
}
