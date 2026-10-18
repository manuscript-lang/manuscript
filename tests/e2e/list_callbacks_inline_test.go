package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestInlinedListCallbacksKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("inline-callbacks.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) Unit:
    if not ok:
        return panic(message: name)

type Point:
    x: Int

test "inlined callbacks":
    let items = List[Int]()
    var i = 0
    while i < 5:
        items.append(value: i)
        i = i + 1
    let offset = 10
    let shifted = items.map(fn(v: Int) Int: v + offset)
    check(ok: shifted.length() == 5 and shifted.at(index: 4) == some(14), name: "map")
    let labels = items.map(fn(v: Int) String: "n{v}")
    check(ok: labels.at(index: 2) == some("n2"), name: "map to string")
    let floats = items.map(fn(v: Int) Float: 0.5)
    check(ok: floats.length() == 5, name: "map to float")
    let points = items.map(fn(v: Int) Point: Point(x: v))
    check(ok: points.at(index: 3) == some(Point(x: 3)), name: "map to record")
    let evens = items.filter(fn(v: Int) Bool: v % 2 == 0)
    check(ok: evens.length() == 3, name: "filter")
    check(ok: points.filter(fn(p: Point) Bool: p.x > 2).length() == 2, name: "filter records")
    check(ok: items.fold(initial: 0, step: fn(a: Int, v: Int) Int: a + v) == 10, name: "fold")
    check(ok: items.fold(initial: "", step: fn(a: String, v: Int) String: a + "{v}") == "01234", name: "fold string")
    check(ok: items.count(predicate: fn(v: Int) Bool: v > 1) == 3, name: "count")
    check(ok: items.some(predicate: fn(v: Int) Bool: v == 4), name: "some")
    check(ok: not items.some(predicate: fn(v: Int) Bool: v == 9), name: "some none")
    check(ok: items.every(predicate: fn(v: Int) Bool: v < 5), name: "every")
    check(ok: not items.every(predicate: fn(v: Int) Bool: v < 4), name: "every fails")
    let seen = List[Int]()
    items.for_each(operation: fn(v: Int) Unit:
        items.append(value: 100)
        seen.append(value: v)
    )
    check(ok: seen.length() == 5 and items.length() == 10, name: "iterates a snapshot")
    check(ok: List[Int]().map(fn(v: Int) Int: v).length() == 0, name: "empty")
    check(ok: items.map(fn(v: Int) Int: items.filter(fn(w: Int) Bool: w == v).length()).length() == 10, name: "nested")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("inlined callbacks changed: %v\n%s", err, output)
	}
}
