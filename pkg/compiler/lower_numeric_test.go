package compiler_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestNumericLoweringAvoidsParsingAndDynamicDispatch(t *testing.T) {
	result := compiler.CompileSource("numeric.ms", `fn calculate(value: Int) -> Int:
    let minimum = -9223372036854775808
    let leading = 9
    if value < 5:
        return (value + leading) * 3 - minimum % 7
    return value / 2
fn fraction(value: Float) -> Float:
    if value >= 1e-3: return value * 2.5 + 1.0 / 0.0
    return value - 5e-324
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, forbidden := range []string{"rt.Integer(", "rt.Float(", "rt.Binary("} {
		if strings.Contains(result.Source, forbidden) {
			t.Fatalf("numeric hot path still contains %s", forbidden)
		}
	}
	for _, required := range []string{"int64(-9223372036854775808)", "int64(9)", "rt.IntAdd(", "rt.IntSubtract(", "rt.IntMultiply(", "rt.IntDivide(", "rt.IntRemainder(", "rt.FloatValue("} {
		if !strings.Contains(result.Source, required) {
			t.Fatalf("missing typed lowering %s", required)
		}
	}
}

func TestDirectNativeCollectionLowering(t *testing.T) {
	result := compiler.CompileSource("collections.ms", `import List from "@std/collections.ms"
fn read(values: List[Int], index: Int) -> Int:
    return values.at(index).unwrap()
fn bound(values: List[Int]) -> Optional[Int]:
    let at = values.at
    return at(0)
type Custom:
    value: Int
interface At:
    fn at(index: Int) -> Int
impl At for Custom:
    fn at(index: Int) -> Int: return self.value + index
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, operation := range []string{"rt.ListAt(", "rt.OptionalUnwrap(", "rt.NativeMemberResult(", "rt.Invoke("} {
		if !strings.Contains(result.Source, operation) {
			t.Fatalf("missing expected dispatch %s", operation)
		}
	}
}
