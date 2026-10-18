package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestDirectCallsFillOmittedDefaults(t *testing.T) {
	result := compiler.CompileSource("direct-defaults.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn scaled(base: Int, factor: Int = 2, label: String = "x") -> String: "{label}{base * factor}"

fn chained(base: Int, plus: Int = base + 1) -> Int: base + plus

fn maybe(value: Int, extra: Optional[Int] = none) -> Int:
    match extra:
    some(number):
        return value + number
    none:
        return value

fn countdown(n: Int, step: Int = 1) -> Int:
    if n <= 0:
        return 0
    return n + countdown(n: n - step, step: step)

test "omitted defaults":
    check(ok: scaled(base: 3) == "x6", name: "all omitted")
    check(ok: scaled(base: 3, factor: 5) == "x15", name: "one omitted")
    check(ok: scaled(base: 3, factor: 5, label: "y") == "y15", name: "none omitted")
    check(ok: chained(base: 4) == 9 and chained(base: 4, plus: 1) == 5, name: "default reads earlier parameter")
    check(ok: maybe(value: 1) == 1 and maybe(value: 1, extra: some(4)) == 5, name: "optional default")
    check(ok: countdown(n: 4) == 10 and countdown(n: 4, step: 2) == 6, name: "recursive default")
    let callback = scaled
    check(ok: callback(base: 2, factor: 3, label: "z") == "z6", name: "function value still callable")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("direct defaults changed: %v\n%s", err, output)
	}
}
