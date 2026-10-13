package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestMutationAliasesScopedImplementations(t *testing.T) {
	data, err := execute(t, compiler.CompileFile("testdata/projects/map_remove/main.ms", compiler.Options{Tests: true}))
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(data)), "1 tests, 0 failed") {
		t.Fatalf("Map.remove scope: %v\n%s", err, data)
	}
}

func TestMutationAliasesRetainSpliceFaults(t *testing.T) {
	source := `test "old start":
    [1].with_values(-1, 0, [])
test "new start":
    [1].splice(-1, 0, [])
test "old count":
    [1].with_values(0, 2, [])
test "new count":
    [1].splice(0, 2, [])
test "bound start":
    let splice = [1].splice
    splice(2, 0, [])
test "bound count":
    let splice = [1].splice
    splice(0, -1, [])
test "continues":
    let values = [1].splice(0, 1, [])
    values.append(2)
`
	data, err := execute(t, compiler.CompileSource("splice-faults.ms", source, compiler.Options{Tests: true}))
	if err == nil {
		t.Fatalf("missing splice faults: %s", data)
	}
	output := string(data)
	for _, names := range [][2]string{{"old start", "new start"}, {"old count", "new count"}} {
		messages := [2]string{}
		for i, name := range names {
			_, tail, found := strings.Cut(output, "FAIL splice-faults.ms::"+name+": ")
			if !found {
				t.Fatal(output)
			}
			messages[i], _, _ = strings.Cut(tail, "\n")
		}
		if messages[0] != messages[1] {
			t.Fatalf("changed legacy fault: %q != %q", messages[0], messages[1])
		}
	}
	for _, frame := range []string{"splice-faults.ms:4:9", "splice-faults.ms:8:9", "splice-faults.ms:11:5", "splice-faults.ms:14:5", "7 tests, 6 failed"} {
		if !strings.Contains(output, frame) {
			t.Errorf("missing %s: %s", frame, output)
		}
	}
}
