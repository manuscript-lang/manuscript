package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestOptionalMembersCallDirectly(t *testing.T) {
	result := compiler.CompileSource("optional-members.ms", `import panic from "@std/faults.ms"
import List from "@std/collections.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn fallback() -> Int: 9

test "optional members":
    let present = some(3)
    let absent: Optional[Int] = none
    check(ok: present.is_some() and not present.is_none(), name: "is_some")
    check(ok: absent.is_none() and not absent.is_some(), name: "is_none")
    check(ok: present.unwrap_or(fallback: 7) == 3, name: "unwrap_or some")
    check(ok: absent.unwrap_or(fallback: 7) == 7, name: "unwrap_or none")
    check(ok: absent.unwrap_or_else(create: fn() -> Int: fallback()) == 9, name: "unwrap_or_else")
    check(ok: present.map(fn(value: Int) -> Int: value + 1).unwrap() == 4, name: "map")
    let items = List[Int]()
    check(ok: items.at(index: 0).is_none(), name: "list.at is_none")
    items.append(value: 5)
    check(ok: items.at(index: 0).is_some() and items.first().unwrap_or(fallback: 0) == 5, name: "list.at is_some")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("optional members changed: %v\n%s", err, output)
	}
}
