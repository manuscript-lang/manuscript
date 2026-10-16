package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestListTakeDropFaultLocations(t *testing.T) {
	for _, method := range []string{"take", "drop"} {
		for _, test := range []struct{ name, source, frame string }{
			{"direct", `export fn main() -> Int:
    let values = [1, 2]
    let part = values.METHOD(-7)
    return part.length
`, "list-copy-fault.ms:3 in main"},
			{"bound", `export fn main() -> Int:
    let copy = [1, 2].METHOD
    let part = copy(count: -7)
    return part.length
`, "list-copy-fault.ms:3 in main"},
			{"empty", `export fn main() -> Int:
    let empty: List[Int] = []
    let part = empty.METHOD(-7)
    return part.length
`, "list-copy-fault.ms:3 in main"},
		} {
			t.Run(method+"/"+test.name, func(t *testing.T) {
				result := compiler.CompileSource("list-copy-fault.ms", strings.ReplaceAll(test.source, "METHOD", method), compiler.Options{Entry: true})
				data, err := execute(t, result)
				if err == nil || !strings.Contains(string(data), "List."+method+": count must be nonnegative, found -7") {
					t.Fatalf("wrong List copy failure: %v\n%s", err, data)
				}
				var frames []string
				for _, line := range strings.Split(string(data), "\n") {
					if frame, ok := strings.CutPrefix(line, "  at "); ok {
						frames = append(frames, frame)
					}
				}
				if len(frames) != 1 || frames[0] != test.frame {
					t.Fatalf("List copy frames = %q, want %q; transcript:\n%s", frames, test.frame, data)
				}
			})
		}
	}
}
