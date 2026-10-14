package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestTypedAlternativeLetsKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("alt-lets.ms", `import panic from "@std/faults.ms"

fn halve(n: Int) -> Optional[Int]:
    if n % 2 != 0:
        return none
    return some(value: n / 2)

fn parse(n: Int) -> Result[Int, String]:
    if n < 0:
        return error(cause: "negative")
    return ok(value: n)

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn matched(n: Int) -> Int:
    let found = halve(n: n)
    match found:
        some(v):
            return v
        none:
            return 0 - 1

fn twice(n: Int) -> Int:
    let found = halve(n: n)
    var total = 0
    match found:
        some(v):
            total = total + v
        none:
            total = total + 100
    match found:
        some(v):
            total = total + v
        none:
            total = total + 1000
    return total

fn results(n: Int) -> String:
    let parsed = parse(n: n)
    match parsed:
        ok(v):
            return "ok {v}"
        error(cause):
            return cause

fn formatted(n: Int) -> String:
    let found = halve(n: n)
    return "{found}"

fn captured(n: Int) -> Int:
    let found = halve(n: n)
    let read = fn() -> Int:
        match found:
            some(v):
                return v
            none:
                return 0 - 1
    return read()

test "typed alternative lets":
    check(ok: matched(n: 8) == 4, name: "some")
    check(ok: matched(n: 7) == 0 - 1, name: "none")
    check(ok: twice(n: 8) == 8, name: "twice some")
    check(ok: twice(n: 7) == 1100, name: "twice none")
    check(ok: results(n: 3) == "ok 3", name: "ok")
    check(ok: results(n: 0 - 3) == "negative", name: "error")
    check(ok: formatted(n: 8) == formatted(n: 8), name: "formatted")
    check(ok: captured(n: 8) == 4, name: "captured")
    check(ok: captured(n: 7) == 0 - 1, name: "captured none")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "1 tests, 0 failed") && !strings.Contains(string(output), "PASS") {
		t.Fatalf("typed alternative lets changed: %v\n%s", err, output)
	}
}
