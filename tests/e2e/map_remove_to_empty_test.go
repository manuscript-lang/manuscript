package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Removing the only entry and then adding distinct keys must keep them distinct.
func TestMapAndSetRemoveToEmptyThenAdd(t *testing.T) {
	source := `import panic from "@std/faults.ms"

export fn main() Int:
    let m = Map[String, Int]()
    m.add(key: "cap", value: 1)
    m.remove("cap")
    m.add(key: "pen", value: 2)
    m.add(key: "cap", value: 3)
    if m.length() != 2: return panic("without: length {m.length()}")
    if m.get("pen").unwrap() != 2: return panic("without: pen")
    if m.get("cap").unwrap() != 3: return panic("without: cap")

    let n = Map[Int, Int]()
    n.add(key: 1, value: 10)
    n.remove(key: 1)
    n.add(key: 2, value: 20)
    n.add(key: 1, value: 30)
    if n.length() != 2: return panic("remove: length {n.length()}")
    if n.get(2).unwrap() != 20: return panic("remove: 2")
    if n.get(1).unwrap() != 30: return panic("remove: 1")

    let s = Set[String]()
    s.add("cap")
    s.remove("cap")
    s.add("pen")
    s.add("cap")
    if s.length() != 2: return panic("set: length {s.length()}")
    return 0
`
	result := compiler.CompileSource("remove-to-empty.ms", source, compiler.Options{Entry: true})
	data, err := execute(t, result)
	if err != nil || strings.TrimSpace(string(data)) != "" {
		t.Fatalf("remove-to-empty failed: %v\n%s", err, data)
	}
}
