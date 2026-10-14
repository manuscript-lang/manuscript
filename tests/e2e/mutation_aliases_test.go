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
	source := `test "new start":
    [1].splice(-1, 0, [])
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
	for _, frame := range []string{"List.splice: start must be between 0 and 1, found -1", "splice-faults.ms:2:9", "splice-faults.ms:4:9", "splice-faults.ms:7:5", "splice-faults.ms:10:5", "5 tests, 4 failed"} {
		if !strings.Contains(output, frame) {
			t.Errorf("missing %s: %s", frame, output)
		}
	}
}
