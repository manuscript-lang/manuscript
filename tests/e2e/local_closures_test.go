package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestLocalClosuresKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("local-closures.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn bump(factor: Int) -> Int:
    var offset = 10
    let scale = fn(value: Int) -> Int: value * factor + offset
    offset = 99
    return scale(value: 2)

fn lookup(limit: Int) -> Int:
    let find = fn(key: Int) -> Optional[Int]:
        if key < limit:
            return some(key * 2)
        return none
    var total = 0
    var i = 0
    while i < 5:
        match find(key: i):
            some(found):
                total = total + found
            none:
                total = total + 100
        i = i + 1
    return total

fn parse(text: String) -> Result[Int, String]:
    let guard = fn(number: Int) -> Result[Int, String]:
        if number < 0:
            return Result[Int, String].error("negative")
        return Result[Int, String].ok(number)
    let checked = try guard(number: text.length)
    return Result[Int, String].ok(checked + 1)

fn labels(prefix: String) -> String:
    let join = fn(left: String, right: String) -> String: "{prefix}{left}-{right}"
    return join(left: "a", right: "b")

fn reordered() -> Int:
    let subtract = fn(left: Int, right: Int) -> Int: left - right
    return subtract(right: 2, left: 7)

fn passed() -> List[Int]:
    let double = fn(value: Int) -> Int: value * 2
    return [1, 2, 3].map(double)

fn nested(n: Int) -> Int:
    let inner = fn(x: Int) -> Int: x + 1
    let outer = fn(y: Int) -> Int: inner(x: y) * 2
    return outer(y: n)

test "local closures":
    check(ok: bump(factor: 3) == 16, name: "captures snapshot at creation")
    check(ok: lookup(limit: 3) == 0 + 2 + 4 + 100 + 100, name: "optional result")
    check(ok: parse(text: "abc") == Result[Int, String].ok(4), name: "result with try")
    check(ok: labels(prefix: ">") == ">a-b", name: "string params and captures")
    check(ok: reordered() == 5, name: "reordered arguments")
    check(ok: passed().length == 3 and passed().at(index: 2) == some(6), name: "closure passed as a value")
    check(ok: nested(n: 4) == 10, name: "closure calling closure")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("local closures changed: %v\n%s", err, output)
	}
}

func TestLocalClosureFaultNamesTheLambda(t *testing.T) {
	result := compiler.CompileSource("closure-fault.ms", `import panic from "@std/faults.ms"

fn run() -> Int:
    let boom = fn(value: Int) -> Int: panic(message: "closure failed")
    return boom(value: 1)

test "fault":
    run()
`, compiler.Options{Tests: true})
	output, _ := execute(t, result)
	if !strings.Contains(string(output), "closure failed") || !strings.Contains(string(output), "in <anonymous>") || !strings.Contains(string(output), "in run") {
		t.Fatalf("fault frames lost the lambda\n%s", output)
	}
}
