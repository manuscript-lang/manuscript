package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestListCallbacksReuseArgumentsWithoutChangingSemantics(t *testing.T) {
	result := compiler.CompileSource("callbacks.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn keep(list: List[fn() -> Int], value: Int) -> Unit:
    list.append(value: fn() -> Int: value)
    return unit

fn grow(list: List[Int], value: Int) -> Int:
    list.append(value: value)
    return value

fn nested(items: List[Int]) -> List[Int]:
    return items.map(fn(value: Int) -> Int: items.map(fn(inner: Int) -> Int: inner + value).length + value)

test "list callbacks":
    let items = List[Int]()
    var i = 0
    while i < 5:
        items.append(value: i)
        i = i + 1
    let doubled = items.map(fn(value: Int) -> Int: value * 2)
    check(ok: doubled.at(index: 4) == some(8), name: "map")
    let even = items.filter(fn(value: Int) -> Bool: value % 2 == 0)
    check(ok: even.length == 3, name: "filter")
    check(ok: items.fold(initial: 0, step: fn(accumulator: Int, value: Int) -> Int: accumulator + value) == 10, name: "fold")
    check(ok: items.count(predicate: fn(value: Int) -> Bool: value > 1) == 3, name: "count")
    let retained = List[fn() -> Int]()
    items.for_each(operation: fn(value: Int) -> Unit: keep(list: retained, value: value))
    let called = retained.map(fn(value: fn() -> Int) -> Int: value())
    check(ok: called.fold(initial: 0, step: fn(accumulator: Int, value: Int) -> Int: accumulator + value) == 10, name: "captures")
    let grown = List[Int]()
    grown.append(value: 1)
    grown.append(value: 2)
    let seen = grown.map(fn(value: Int) -> Int: grow(list: grown, value: value))
    check(ok: seen.length == 2 and grown.length == 4, name: "append during map")
    check(ok: nested(items: items).at(index: 2) == some(7), name: "reentrant map")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("list callbacks changed: %v\n%s", err, output)
	}
}
