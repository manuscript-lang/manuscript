package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestIntLiteralDivisorsKeepSemantics(t *testing.T) {
	result := compiler.CompileSource("int-literal-divisor.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) Unit:
    if not ok:
        return panic(message: name)

test "literal divisors":
    let n = -7
    check(ok: n / 2 == -3, name: "truncates toward zero")
    check(ok: n % 3 == -1, name: "remainder keeps dividend sign")
    check(ok: 9 % 2 == 1, name: "positive remainder")
    var i = 0
    var hits = 0
    while i < 100:
        if i % 3 == 0:
            hits = hits + 1
        i = i + 1
    check(ok: hits == 34, name: "loop remainder")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("literal divisor semantics changed: %v\n%s", err, output)
	}
}
