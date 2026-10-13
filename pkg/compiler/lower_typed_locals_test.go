package compiler

import (
	"strings"
	"testing"
)

func TestScalarLocalsAndParametersAreTypedGoVariables(t *testing.T) {
	r := CompileSource("typed.ms", `fn count(limit: Int, ratio: Float, label: String, on: Bool) -> Int:
    var i = 0
    var hits = 0
    while i < limit and on:
        if i % 3 == 0:
            hits = hits + 1
        i = i + 1
    let scaled = ratio * 2.0
    let same = label == "x"
    if scaled > 1.0 and same:
        return hits
    return 0
`, Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, want := range []string{
		"(ctx *rt.Execution, local3_limit int64, local4_ratio float64, local5_label string, local6_on bool) (directResult int64)",
		"var local7_i int64 = int64(0)",
		"var local9_scaled float64 =",
	} {
		if !strings.Contains(r.Source, want) {
			t.Errorf("missing %q\n%s", want, r.Source)
		}
	}
	// No loop variable is boxed: every use stays typed.
	for _, banned := range []string{"rt.IntValue(local7_i)", "rt.IntValue(local8_hits)", "var local7_i rt.Value", "rt.Bool(local6_on)"} {
		if strings.Contains(r.Source, banned) {
			t.Errorf("boxed use %q\n%s", banned, r.Source)
		}
	}
}

func TestConstantFloatArithmeticFollowsRuntimeRules(t *testing.T) {
	r := CompileSource("const.ms", "fn f() -> Float: return 1.0 / 0.0\nfn g() -> Float: return 1.7976931348623157e308 * 2.0\n", Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Contains(r.Source, "float64(1) / float64(0)") || strings.Contains(r.Source, "float64(1.7976931348623157e+308) * float64(2)") {
		t.Fatalf("constant float expression left for the Go compiler\n%s", r.Source)
	}
}
