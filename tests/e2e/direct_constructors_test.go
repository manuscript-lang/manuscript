package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestRecordConstructorsWithDefaultsMatchDynamicConstruction(t *testing.T) {
	result := compiler.CompileSource("direct-constructors.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) Unit:
    if not ok:
        return panic(message: name)

fn twice(n: Int) Int: n * 2

type Options:
    count: Int
    total: Int = count + 1
    label: String = "x"
    scale: Float = 1.5
    scaled: Int = twice(n: total)

type Plain:
    name: String = "p"
    size: Int = 3


test "constructors":
    let a = Options(count: 5)
    check(ok: a.total == 6 and a.label == "x" and a.scale == 1.5 and a.scaled == 12, name: "all defaults")
    let b = Options(count: 5, total: 0)
    check(ok: b.total == 0 and b.scaled == 0, name: "skip one")
    let c = Options(count: 1, total: 2, label: "y", scale: 2.0, scaled: 9)
    check(ok: c.label == "y" and c.scaled == 9 and c.scale == 2.0, name: "all supplied")
    let d = Options(label: "z", count: 4)
    check(ok: d.label == "z" and d.total == 5, name: "reordered")
    let e = Plain()
    check(ok: e.name == "p" and e.size == 3, name: "no args")
    check(ok: Plain(size: 9).size == 9 and Plain(size: 9).name == "p", name: "named")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("constructors changed: %v\n%s", err, output)
	}
}
