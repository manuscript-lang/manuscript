package e2e_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestInherentImplDeclaresTypeMethods(t *testing.T) {
	result := compiler.CompileSource("inherent.ms", `import panic from "@std/faults.ms"

interface Show:
    fn show() -> String

type Counter:
    value: Int

type Box[T]:
    item: T

type Shape:
    case Circle(r: Int)
    case Square(s: Int)

impl Counter:
    fn double() -> Int:
        return self.value * 2
    fn bump(by: Int = 1) -> Counter:
        return Counter(value: self.value + by)
    fn depth(n: Int) -> Int:
        if n == 0:
            return self.value
        return self.depth(n: n - 1) + 1

impl Counter:
    fn overflow() -> Int:
        return self.value * self.value

impl Show for Counter:
    fn show() -> String:
        return "counter"

impl Box[T]:
    fn get() -> T:
        return self.item

impl Shape:
    fn area() -> Int:
        match self:
        Circle(r): return r * r * 3
        Square(s): return s * s

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

test "inherent methods":
    let counter = Counter(value: 4)
    check(ok: counter.double() == 8, name: "double")
    check(ok: counter.bump().value == 5, name: "default argument")
    check(ok: counter.bump(by: 3).value == 7, name: "explicit argument")
    check(ok: counter.depth(n: 5) == 9, name: "recursion")
    check(ok: counter.show() == "counter", name: "contract beside inherent")
    check(ok: Box(item: 7).get() == 7, name: "generic receiver")
    check(ok: Shape.Square(s: 3).area() == 9, name: "alternative receiver")
    check(ok: Circle(r: 2).area() == 12, name: "unqualified case")
test "inherent fault frame":
    Counter(value: 9223372036854775807).overflow()
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	text := string(output)
	if err == nil || !strings.Contains(text, "2 tests, 1 failed") || !strings.Contains(text, "in Counter.overflow") {
		t.Fatalf("inherent methods changed: %v\n%s", err, text)
	}
	if strings.Contains(text, "FAIL inherent.ms::inherent methods") {
		t.Fatalf("inherent methods failed:\n%s", text)
	}
}

func TestInherentImplRejections(t *testing.T) {
	for _, item := range []struct{ source, want string }{
		{"type A:\n    x: Int\n    fn f() -> Int:\n        return 1\n", "a type declares only fields or cases"},
		{"interface I:\n    fn f() -> Int\nimpl I:\n    fn f() -> Int:\n        return 1\n", "I is an interface"},
		{"import Duration from \"@std/time.ms\"\nimpl Duration:\n    fn f() -> Int:\n        return 1\n", "inherent methods belong in the module that declares Duration"},
		{"type B[T]:\n    x: T\nimpl B:\n    fn f() -> Int:\n        return 1\n", "impl must repeat the type parameters of B"},
		{"type B:\n    x: Int\nimpl B:\n    fn m[U](u: U) -> U:\n        return u\n", "declares its own type parameters"},
		{"type B:\n    x: Int\nimpl B:\n    fn m() -> Int:\n        return 1\nimpl B:\n    fn m() -> Int:\n        return 2\n", "duplicate implementation operation m"},
		{"type B:\n    x: Int\nimpl B:\n    fn m() -> Int:\n", "reachable fallthrough"},
	} {
		result := compiler.CompileSource("rejected.ms", item.source, compiler.Options{AnalyzeOnly: true})
		if result.Success() || !strings.Contains(fmt.Sprint(result.Diagnostics), item.want) {
			t.Errorf("expected %q: %v", item.want, result.Diagnostics)
		}
	}
}
