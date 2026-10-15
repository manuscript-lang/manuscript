package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestPreferredNamesScopedImplementations(t *testing.T) {
	result := compiler.CompileFile("testdata/projects/preferred_names/main.ms", compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(data)), "1 tests, 0 failed") {
		t.Fatalf("preferred names scopes: %v\n%s", err, data)
	}
}

func TestPreferredNamesRetainFaults(t *testing.T) {
	source := `test "new set":
    [1].set(1, 2)
test "bound set":
    let set = [1].set
    set(-2, 2)
test "new remove":
    [1].remove(1)
test "bound remove":
    let remove = [1].remove
    remove(-2)
test "empty set":
    let items: List[Int] = []
    items.set(0, 2)
test "empty remove":
    let items: List[Int] = []
    items.remove(0)
test "old replace":
    "a".replace("a", "b", -1)
test "new replace":
    "a".replace_first("a", "b", -1)
test "bound replace":
    let first = "a".replace_first
    first("a", "b", -1)
test "continues":
    let result = [1].set(0, 2).remove(0)
`
	data, err := execute(t, compiler.CompileSource("preferred-faults.ms", source, compiler.Options{Tests: true}))
	if err == nil {
		t.Fatalf("missing faults: %s", data)
	}
	output := string(data)
	for _, pair := range [][2]string{{"old replace", "new replace"}} {
		messages := [2]string{}
		for i, name := range pair {
			marker := "FAIL preferred-faults.ms::" + name + ": "
			_, tail, ok := strings.Cut(output, marker)
			if !ok {
				t.Fatalf("missing %s: %s", marker, output)
			}
			messages[i], _, _ = strings.Cut(tail, "\n")
		}
		if messages[0] != messages[1] {
			t.Fatalf("alias changed diagnostic: %q != %q", messages[0], messages[1])
		}
	}
	for _, frame := range []string{"preferred-faults.ms:2", "preferred-faults.ms:5", "preferred-faults.ms:7", "preferred-faults.ms:10", "preferred-faults.ms:13", "preferred-faults.ms:16", "preferred-faults.ms:18", "preferred-faults.ms:20", "preferred-faults.ms:23", "10 tests, 9 failed"} {
		if !strings.Contains(output, frame) {
			t.Errorf("missing %s: %s", frame, output)
		}
	}
}

func TestSameTypeNamesAcrossModules(t *testing.T) {
	result := compiler.CompileFile("testdata/projects/same_type_names/main.ms", compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(data)), "1 tests, 0 failed") {
		t.Fatalf("same type names: %v\n%s", err, data)
	}
}
