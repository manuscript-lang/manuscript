package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestDirectMethodsKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("methods.ms", `import panic from "@std/faults.ms"
import List from "@std/collections.ms"

interface Shape:
    fn area() -> Int
    fn scaled(by: Int) -> Int
    fn checked(limit: Int) -> Result[Int, String]
    fn grow(depth: Int) -> Int

type Rect:
    w: Int
    h: Int

type Sign:
    case Plus(n: Int)
    case Minus(n: Int)

impl Shape for Rect:
    fn area() -> Int:
        return self.w * self.h
    fn scaled(by: Int) -> Int:
        return self.area() * by
    fn checked(limit: Int) -> Result[Int, String]:
        if self.area() > limit:
            return error(cause: "too big")
        return ok(value: self.area())
    fn grow(depth: Int) -> Int:
        if depth == 0:
            return self.w
        return self.grow(depth: depth - 1) + 1

impl Shape for Sign:
    fn area() -> Int:
        match self:
            Plus(n): return n
            Minus(n): return 0 - n
    fn scaled(by: Int) -> Int:
        return self.area() * by
    fn checked(limit: Int) -> Result[Int, String]:
        return ok(value: self.area())
    fn grow(depth: Int) -> Int:
        return depth

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn through(shape: Shape) -> Int:
    return shape.scaled(by: 2)

fn tried(rect: Rect, limit: Int) -> Result[Int, String]:
    let first = try rect.checked(limit: limit)
    return ok(value: first + (try rect.checked(limit: limit + 100)))

fn order(rect: Rect, log: List[String]) -> Int:
    log.append(value: "receiver")
    return rect.scaled(by: id(log: log))

fn id(log: List[String]) -> Int:
    log.append(value: "argument")
    return 1

test "direct methods":
    let rect = Rect(w: 3, h: 4)
    check(ok: rect.area() == 12, name: "area")
    check(ok: rect.scaled(by: 3) == 36, name: "nested method call")
    check(ok: through(shape: Shape(value: rect)) == 24, name: "view call")
    check(ok: through(shape: Shape(value: Plus(n: 5))) == 10, name: "alternative through view")
    check(ok: Minus(n: 4).area() == 0 - 4, name: "alternative receiver")
    check(ok: rect.grow(depth: 10) == 13, name: "recursion")
    match tried(rect: rect, limit: 12):
        ok(value): check(ok: value == 24, name: "tried")
        error(cause): panic(message: cause)
    match tried(rect: rect, limit: 11):
        ok(value): panic(message: "expected failure")
        error(cause): check(ok: cause == "too big", name: "tried cause")
    let log = List[String]()
    check(ok: order(rect: rect, log: log) == 12, name: "order result")
    check(ok: log.join(separator: ",") == "receiver,argument", name: "receiver before arguments")
test "method fault frame":
    let rect = Rect(w: 9223372036854775807, h: 2)
    rect.area()
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	text := string(output)
	if err == nil || !strings.Contains(text, "2 tests, 1 failed") || !strings.Contains(text, "in Rect.area") {
		t.Fatalf("direct methods changed: %v\n%s", err, text)
	}
	if strings.Contains(text, "FAIL methods.ms::direct methods") {
		t.Fatalf("direct methods failed:\n%s", text)
	}
}
