package e2e_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestNumericPreconditionDiagnostics(t *testing.T) {
	cases := []struct{ call, message string }{
		{"1 |/ 0", "Int./: division by zero; right must be nonzero, found 0"},
		{"1 |% 0", "Int.%: remainder by zero; right must be nonzero, found 0"},
		{"(-9223372036854775808) |/ -1", "Int./: overflow; found left -9223372036854775808 and right -1; result must be between -9223372036854775808 and 9223372036854775807"},
		{"1d |/ 0d", "Decimal./: division by zero; right must be nonzero, found 0"},
		{"minimum.|divide(0)", "Duration.divide: division by zero; divisor must be nonzero, found 0"},
		{"minimum.|divide(-1)", "Duration.divide: overflow; found value (nanoseconds) -9223372036854775808 and divisor -1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{"maximum.|add(duration(1))", "Duration.add: overflow; found value (nanoseconds) 9223372036854775807 and right (nanoseconds) 1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{"minimum.|add(duration(-1))", "Duration.add: overflow; found value (nanoseconds) -9223372036854775808 and right (nanoseconds) -1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{"minimum.|subtract(duration(1))", "Duration.subtract: overflow; found value (nanoseconds) -9223372036854775808 and right (nanoseconds) 1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{"maximum.|subtract(duration(-1))", "Duration.subtract: overflow; found value (nanoseconds) 9223372036854775807 and right (nanoseconds) -1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{"maximum.|multiply(2)", "Duration.multiply: overflow; found value (nanoseconds) 9223372036854775807 and factor 2; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{"minimum.|multiply(-1)", "Duration.multiply: overflow; found value (nanoseconds) -9223372036854775808 and factor -1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{"duration(-1).|multiply(-9223372036854775808)", "Duration.multiply: overflow; found value (nanoseconds) -1 and factor -9223372036854775808; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{"minimum.|negate()", "Duration.negate: value (nanoseconds) must be between -9223372036854775807 and 9223372036854775807, found -9223372036854775808"},
		{"minimum.|abs()", "Duration.abs: value (nanoseconds) must be between -9223372036854775807 and 9223372036854775807, found -9223372036854775808"},
		{"maximum |+ duration(1)", "Duration.+: overflow; found left (nanoseconds) 9223372036854775807 and right (nanoseconds) 1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{"minimum |- duration(1)", "Duration.-: overflow; found left (nanoseconds) -9223372036854775808 and right (nanoseconds) 1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{"(9223372036855).|milliseconds", "Int.milliseconds: value must be between -9223372036854 and 9223372036854, found 9223372036855"},
		{"(-9223372036855).|milliseconds", "Int.milliseconds: value must be between -9223372036854 and 9223372036854, found -9223372036855"},
		{"(9223372037).|seconds", "Int.seconds: value must be between -9223372036 and 9223372036, found 9223372037"},
		{"(-9223372037).|seconds", "Int.seconds: value must be between -9223372036 and 9223372036, found -9223372037"},
		{"(153722868).|minutes", "Int.minutes: value must be between -153722867 and 153722867, found 153722868"},
		{"(-153722868).|minutes", "Int.minutes: value must be between -153722867 and 153722867, found -153722868"},
		{"|divide(0)", "Duration.divide: division by zero; divisor must be nonzero, found 0"},
		{"(1 |/ 0).seconds", "Int./: division by zero; right must be nonzero, found 0"},
	}
	source := `import {duration} from "@std/time.ms"
import Decimal from "@std/decimal.ms"
`
	var frames []string
	for i, tc := range cases {
		name := fmt.Sprintf("numeric %d", i)
		source += fmt.Sprintf("test %q:\n    let minimum = duration(-9223372036854775808)\n    let maximum = duration(9223372036854775807)\n    let divide = minimum.divide\n", name)
		line := strings.Count(source, "\n") + 1
		call := "    let impossible = " + tc.call
		column := strings.IndexByte(call, '|') + 1
		frames = append(frames, fmt.Sprintf("numeric-preconditions.ms:%d:%d in test %s", line, column, name))
		source += strings.ReplaceAll(call, "|", "") + "\n"
	}
	source += "test \"continues after numeric faults\":\n    let valid = 1\n"
	data, err := execute(t, compiler.CompileSource("numeric-preconditions.ms", source, compiler.Options{Tests: true}))
	if err == nil {
		t.Fatalf("expected programming faults:\n%s", data)
	}
	output := string(data)
	for i, tc := range cases {
		want := fmt.Sprintf("FAIL numeric-preconditions.ms::numeric %d: %s\n  at %s\n", i, tc.message, frames[i])
		if !strings.Contains(output, want) {
			t.Errorf("missing diagnostic/frame %q:\n%s", want, output)
		}
	}
	var actual []string
	for _, line := range strings.Split(output, "\n") {
		if frame, ok := strings.CutPrefix(line, "  at "); ok {
			actual = append(actual, frame)
		}
	}
	if strings.Join(actual, "\n") != strings.Join(frames, "\n") {
		t.Errorf("frames = %q, want %q", actual, frames)
	}
	if !strings.Contains(output, "PASS numeric-preconditions.ms::continues after numeric faults") || !strings.HasSuffix(strings.TrimSpace(output), fmt.Sprintf("%d tests, %d failed", len(cases)+1, len(cases))) {
		t.Errorf("runner did not continue after all faults:\n%s", output)
	}
}
