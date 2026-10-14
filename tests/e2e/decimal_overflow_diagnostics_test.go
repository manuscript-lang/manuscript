package e2e_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestDecimalOverflowDiagnostics(t *testing.T) {
	const maximum = "9.999999999999999999999999999999999e6144"
	cases := []struct{ expression, operator, left, right string }{
		{"1e6144d |* 10d", "*", "1e6144", "10"},
		{"(-1e6144d) |* 10d", "*", "-1e6144", "10"},
		{"1e6144d |/ 1e-6176d", "/", "1e6144", "1e-6176"},
		{maximum + "d |+ " + maximum + "d", "+", maximum, maximum},
		{"(-" + maximum + "d) |- " + maximum + "d", "-", "-" + maximum, maximum},
	}
	source := "import Decimal from \"@std/decimal.ms\"\n"
	var frames, messages []string
	for i, tc := range cases {
		name := fmt.Sprintf("decimal overflow %d", i)
		source += fmt.Sprintf("test %q:\n", name)
		line := strings.Count(source, "\n") + 1
		expression := "    let impossible = " + tc.expression
		frames = append(frames, fmt.Sprintf("decimal-overflow.ms:%d:%d in test %s", line, strings.IndexByte(expression, '|')+1, name))
		messages = append(messages, fmt.Sprintf("Decimal.%s: overflow; found left %s and right %s; rounded magnitude must be at most %s (34 significant digits)", tc.operator, strings.ReplaceAll(tc.left, "e6144", "e+6144"), strings.ReplaceAll(tc.right, "e6144", "e+6144"), maximum))
		source += strings.ReplaceAll(expression, "|", "") + "\n"
	}
	source += "test \"continues after decimal overflow\":\n    let finite = 1d / 3d\n"
	output, err := execute(t, compiler.CompileSource("decimal-overflow.ms", source, compiler.Options{Tests: true}))
	if err == nil {
		t.Fatalf("expected Decimal faults:\n%s", output)
	}
	text := string(output)
	for i := range cases {
		want := fmt.Sprintf("FAIL decimal-overflow.ms::decimal overflow %d: %s\n  at %s\n", i, messages[i], frames[i])
		if !strings.Contains(text, want) {
			t.Errorf("missing exact diagnostic/frame %q:\n%s", want, text)
		}
	}
	var actual []string
	for _, line := range strings.Split(text, "\n") {
		if frame, ok := strings.CutPrefix(line, "  at "); ok {
			actual = append(actual, frame)
		}
	}
	if strings.Join(actual, "\n") != strings.Join(frames, "\n") || !strings.HasSuffix(strings.TrimSpace(text), "6 tests, 5 failed") || !strings.Contains(text, "PASS decimal-overflow.ms::continues after decimal overflow") {
		t.Errorf("unexpected source frames or continuation:\n%s", text)
	}
}
