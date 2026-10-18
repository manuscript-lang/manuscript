package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestIntIdentitiesKeepBoundariesAndOperandEffects(t *testing.T) {
	result := compiler.CompileSource("int-identities.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool) -> Unit:
    if not ok: return panic("integer identity")

fn touch(log: List[Int], value: Int) -> Int:
    log.append(value)
    return value

test "identities":
    for x in [-9223372036854775808, 9223372036854775807, -7, 0, 1]:
        check(x + 0 == x)
        check(0 + x == x)
        check(x - 0 == x)
        check(x * 0 == 0)
        check(0 * x == 0)
        check(x * 1 == x)
        check(1 * x == x)
        check(x / 1 == x)
        check(x % 1 == 0)
    let log: List[Int] = []
    check(touch(log, 1) * 0 == 0)
    check(0 * touch(log, 2) == 0)
    check(touch(log, 3) * 1 == 3)
    check(1 * touch(log, 4) == 4)
    check(touch(log, 5) + 0 == 5)
    check(0 + touch(log, 6) == 6)
    check(touch(log, 7) - 0 == 7)
    check(touch(log, 8) / 1 == 8)
    check(touch(log, 9) % 1 == 0)
    check(log == [1, 2, 3, 4, 5, 6, 7, 8, 9])
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("integer identities changed: %v\n%s", err, output)
	}
}
