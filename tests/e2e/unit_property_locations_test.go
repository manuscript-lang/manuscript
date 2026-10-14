package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestDurationUnitPropertySourceFrames(t *testing.T) {
	// Both counts also fit signed32: the test isolates location/evaluation order
	// and does not commit to the default integer width or a new overflow message.
	source := `test "positive unit overflow":
    let impossible = (153722868).minutes
test "negative unit overflow":
    let impossible = (-153722868).minutes
test "receiver fault comes first":
    let impossible = (1 / 0).minutes
test "continues with valid units":
    let valid = (1).seconds
`
	data, err := execute(t, compiler.CompileSource("unit-properties.ms", source, compiler.Options{Tests: true}))
	if err == nil {
		t.Fatalf("expected unit/receiver faults:\n%s", data)
	}
	var frames []string
	for _, line := range strings.Split(string(data), "\n") {
		if frame, ok := strings.CutPrefix(line, "  at "); ok {
			frames = append(frames, frame)
		}
	}
	want := []string{
		"unit-properties.ms:2 in test positive unit overflow",
		"unit-properties.ms:4 in test negative unit overflow",
		"unit-properties.ms:6 in test receiver fault comes first",
	}
	if strings.Join(frames, "\n") != strings.Join(want, "\n") || !strings.Contains(string(data), "PASS unit-properties.ms::continues with valid units") || !strings.HasSuffix(strings.TrimSpace(string(data)), "4 tests, 3 failed") {
		t.Fatalf("wrong source frames/evaluation/continuation: %q, want %q; transcript:\n%s", frames, want, data)
	}
}
