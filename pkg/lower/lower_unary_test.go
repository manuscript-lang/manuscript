package lower

import (
	"strings"
	"testing"
)

func TestTypedUnaryLowering(t *testing.T) {
	for _, typ := range []string{"Int", "Float"} {
		t.Run(typ, func(t *testing.T) {
			r := compileSource("unary.ms", "fn negate(value: "+typ+") -> "+typ+": -value\nfn positive(value: "+typ+") -> "+typ+": +value\n")
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			if strings.Contains(r.Source, "rt.Unary(") {
				t.Fatal("scalar unary crossed Value ABI", r.Source)
			}
			if typ == "Int" && !strings.Contains(r.Source, "rt.IntSubtractAt(0,") {
				t.Fatal("missing checked negation", r.Source)
			}
		})
	}
	r := compileSource("decimal.ms", "import Decimal from \"@std/decimal.ms\"\nfn negate(value: Decimal) -> Decimal: -value\n")
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if !strings.Contains(r.Source, "rt.Unary(") {
		t.Fatal("Decimal lost its runtime operation", r.Source)
	}
}
