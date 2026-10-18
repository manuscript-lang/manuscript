package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestListInsertFaultLocations(t *testing.T) {
	for _, test := range []struct{ name, source, frame, message string }{
		{"past end", `export fn main() Int:
    let values = [1, 2]
    values.insert(3, 9)
    return values.length()
`, "list-insert-fault.ms:3 in main", "List.insert: index must be between -2 and 2 (negative indexes count from the end), found 3"},
		{"before start", `export fn main() Int:
    let values = [1, 2]
    values.insert(-3, 9)
    return values.length()
`, "list-insert-fault.ms:3 in main", "List.insert: index must be between -2 and 2 (negative indexes count from the end), found -3"},
		{"bound", `export fn main() Int:
    let insert = [1].insert
    insert(index: 5, value: 9)
    return 0
`, "list-insert-fault.ms:3 in main", "List.insert: index must be between -1 and 1 (negative indexes count from the end), found 5"},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := compiler.CompileSource("list-insert-fault.ms", test.source, compiler.Options{Entry: true})
			data, err := execute(t, result)
			if err == nil || !strings.Contains(string(data), test.message) {
				t.Fatalf("wrong List.insert failure: %v\n%s", err, data)
			}
			var frames []string
			for _, line := range strings.Split(string(data), "\n") {
				if frame, ok := strings.CutPrefix(line, "  at "); ok {
					frames = append(frames, frame)
				}
			}
			if len(frames) != 1 || frames[0] != test.frame {
				t.Fatalf("List.insert frames = %q, want %q; transcript:\n%s", frames, test.frame, data)
			}
		})
	}
}
