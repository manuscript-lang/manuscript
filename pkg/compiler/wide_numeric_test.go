package compiler_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestWideNumericTypeBoundaries(t *testing.T) {
	for _, source := range []string{
		"fn f() -> Int64:\n    let value = 1\n    return value\n",
		"fn f() -> Float64:\n    let value = 1.0\n    return value\n",
		"fn f() -> Int:\n    let value: Int64 = 1\n    return value\n",
		"fn f() -> Float:\n    let value: Float64 = 1.0\n    return value\n",
		"fn f() -> Int64:\n    let small = 1\n    let wide: Int64 = 1\n    return small + wide\n",
		"fn f() -> Float64:\n    let small = 1.0\n    let wide: Float64 = 1.0\n    return small + wide\n",
		"fn f() -> Int64: return 9223372036854775808\n",
		"fn f() -> Int64: return -9223372036854775809\n",
		"fn f() -> Int64: return 1.5\n",
		"fn f() -> Float64: return 1e400\n",
		"fn f() -> Unit: let x = Map[Float64, Int]()\n",
	} {
		t.Run(source, func(t *testing.T) {
			result := compiler.CompileSource("wide.ms", source, compiler.Options{AnalyzeOnly: true})
			if len(result.Diagnostics) == 0 {
				t.Fatal("accepted incompatible wide numeric source")
			}
		})
	}
}

func TestWideLiteralLoweringHasExplicitRuntimeIdentity(t *testing.T) {
	result := compiler.CompileSource("wide.ms", "fn f() -> Int64: return -9223372036854775808\nfn g() -> Float64: return 1e300\n", compiler.Options{})
	if len(result.Diagnostics) != 0 {
		t.Fatal(result.Diagnostics)
	}
	if !strings.Contains(result.Source, "rt.Int64(-9223372036854775808)") || !strings.Contains(result.Source, "rt.Float64(1e+300)") {
		t.Fatal(result.Source)
	}
}

func TestWideLiteralContexts(t *testing.T) {
	for name, source := range map[string]string{
		"parameter":         "fn accept(value: Int64) -> Int64: value\nfn f() -> Int64: accept(3000000000)\n",
		"explicit generic":  "fn identity[T](value: T) -> T: value\nfn f() -> Int64: identity[Int64](3000000000)\n",
		"generic result":    "fn identity[T](value: T) -> T: value\nfn f() -> Float64: identity(1e300)\n",
		"optional argument": "fn accept(value: Optional[Int64]) -> Int64: value.unwrap()\nfn f() -> Int64: accept(3000000000)\n",
		"default":           "fn accept(value: Int64 = 3000000000) -> Int64: value\nfn f() -> Int64: accept()\n",
		"record":            "type Wide:\n    value: Int64 = 3000000000\nfn f() -> Int64: Wide().value\n",
		"list":              "fn f() -> List[Int64]: [3000000000, 4000000000]\n",
		"map":               "fn f() -> Map[Int64, Int64]: {3000000000: 4000000000}\n",
		"arithmetic":        "fn f() -> Int64: (3000000000 + 1) * 2\n",
		"known left":        "fn f(value: Int64) -> Int64: value + 3000000000\n",
		"known right":       "fn f(value: Int64) -> Int64: 3000000000 + value\n",
		"callback":          "fn f() -> fn() -> Float64: fn(): 1e300\n",
		"match":             "fn f(value: Optional[Int]) -> Float64:\n    return match value:\n        some(_): 1e300\n        none: 2e300\n",
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource("wide-context.ms", source, compiler.Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}
