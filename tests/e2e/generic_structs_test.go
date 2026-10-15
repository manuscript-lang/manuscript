package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestGenericRecordInstantiationsKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("generic-structs.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

type Box[T]:
    v: T
    n: Int

type Pair[A, B]:
    first: A
    second: B

fn wrap[T](value: T) -> Box[T]:
    return Box[T](v: value, n: 1)

fn unwrap[T](b: Box[T]) -> T:
    return b.v

fn bump(b: Box[Int]) -> Int:
    return b.v + b.n

test "generic records":
    let a = Box[Int](v: 4, n: 2)
    check(ok: a.v == 4 and a.n == 2, name: "typed read")
    let dyn = wrap(value: 7)
    check(ok: bump(b: dyn) == 8, name: "dynamic construction read typed")
    check(ok: unwrap(b: a) == 4, name: "typed value read generically")
    let s = Box[String](v: "hi", n: 0)
    check(ok: s.v == "hi" and unwrap(b: s) == "hi", name: "string box")
    let nested = Box[Box[Int]](v: a, n: 3)
    check(ok: nested.v.v == 4 and nested.v == a, name: "nested box")
    let items = Box[List[Int]](v: [1, 2, 3], n: 0)
    check(ok: items.v.length() == 3, name: "list field")
    let pair = Pair[Int, String](first: 1, second: "x")
    check(ok: pair.first == 1 and pair.second == "x", name: "two params")
    check(ok: Box[Int](v: 4, n: 2) == a, name: "equality")
    check(ok: not (Box[Int](v: 5, n: 2) == a), name: "inequality")
    let o = Box[Optional[Int]](v: some(3), n: 0)
    check(ok: o.v == some(3), name: "optional param")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("generic records changed: %v\n%s", err, output)
	}
}
