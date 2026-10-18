package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestTextInterpolationAndMapLookupKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("text-map.ms", `import panic from "@std/faults.ms"

type Point:
    x: Int
    y: Int

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn halve(n: Int) -> Optional[Int]:
    if n % 2 != 0:
        return none
    return some(value: n / 2)

fn describe(key: Point, m: Map[Point, String]) -> String:
    match m.get(key: key):
    some(v):
        return "found {v}"
    none:
        return "missing"

test "text interpolation":
    let n = 42
    let f = 1.5
    let ok = true
    let s = "hi"
    check(ok: "n={n} f={f} ok={ok} s={s}" == "n=42 f=1.5 ok=true s=hi", name: "scalars")
    check(ok: "{n}" == "42", name: "single part")
    check(ok: "{s}{s}" == "hihi", name: "adjacent")
    check(ok: "".length() == 0, name: "empty")
    check(ok: "héllo {n}".length() == 8, name: "length counts scalars")
    check(ok: "{halve(n: 8)}" == "{halve(n: 8)}", name: "optional")
    let items = List[Int]()
    items.append(value: 1)
    check(ok: "{items}" == "[1]", name: "list")
    check(ok: "{Point(x: 1, y: 2)}".length() > 0, name: "record")

test "map lookup":
    let m = Map[Int, Int]()
    m.add(key: 1, value: 10)
    match m.get(key: 1):
    some(v):
        check(ok: v == 10, name: "present")
    none:
        panic(message: "expected value")
    match m.get(key: 2):
    some(v):
        panic(message: "unexpected {v}")
    none:
        unit
    let points = Map[Point, String]()
    points.add(key: Point(x: 1, y: 2), value: "a")
    check(ok: describe(key: Point(x: 1, y: 2), m: points) == "found a", name: "composite key")
    check(ok: describe(key: Point(x: 2, y: 1), m: points) == "missing", name: "missing composite key")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("text interpolation or map lookup changed: %v\n%s", err, output)
	}
}
