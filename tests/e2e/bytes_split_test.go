package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestBytesSplitLimitFaultLocations(t *testing.T) {
	for _, test := range []struct {
		name, source, frame string
	}{
		{"empty direct", `export fn main() -> Int:
    let data = Bytes([])
    let parts = data.split(Bytes([0]), -7)
    return parts.length
`, "byte-split-fault.ms:4 in main"},
		{"bound", `export fn main() -> Int:
    let data = Bytes([1, 0, 2])
    let split = data.split
    let parts = split(max_parts: -7, separator: Bytes([0]))
    return parts.length
`, "byte-split-fault.ms:5 in main"},
		{"explicit optional", `export fn main() -> Int:
    let cap: Optional[Int] = some(-7)
    let parts = Bytes([1]).split(Bytes([]), cap)
    return parts.length
`, "byte-split-fault.ms:4 in main"},
	} {
		t.Run(test.name, func(t *testing.T) {
			source := "import Bytes from \"@std/bytes.ms\"\n" + test.source
			result := compiler.CompileSource("byte-split-fault.ms", source, compiler.Options{Entry: true})
			data, err := execute(t, result)
			if err == nil {
				t.Fatalf("expected byte split fault: %s", data)
			}
			if !strings.Contains(string(data), "split: max_parts must be nonnegative, found -7") {
				t.Fatalf("wrong byte split fault: %s", data)
			}
			var frames []string
			for _, line := range strings.Split(string(data), "\n") {
				if frame, ok := strings.CutPrefix(line, "  at "); ok {
					frames = append(frames, frame)
				}
			}
			if len(frames) != 1 || frames[0] != test.frame {
				t.Fatalf("byte split frames = %q, want %q; transcript:\n%s", frames, test.frame, data)
			}
		})
	}
}
