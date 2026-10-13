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
		"parameter":                       "fn accept(value: Int64) -> Int64: value\nfn f() -> Int64: accept(3000000000)\n",
		"explicit generic":                "fn identity[T](value: T) -> T: value\nfn f() -> Int64: identity[Int64](3000000000)\n",
		"generic result":                  "fn identity[T](value: T) -> T: value\nfn f() -> Float64: identity(1e300)\n",
		"optional argument":               "fn accept(value: Optional[Int64]) -> Int64: value.unwrap()\nfn f() -> Int64: accept(3000000000)\n",
		"default":                         "fn accept(value: Int64 = 3000000000) -> Int64: value\nfn f() -> Int64: accept()\n",
		"record":                          "type Wide:\n    value: Int64 = 3000000000\nfn f() -> Int64: Wide().value\n",
		"list":                            "fn f() -> List[Int64]: [3000000000, 4000000000]\n",
		"map":                             "fn f() -> Map[Int64, Int64]: {3000000000: 4000000000}\n",
		"arithmetic":                      "fn f() -> Int64: (3000000000 + 1) * 2\n",
		"known left":                      "fn f(value: Int64) -> Int64: value + 3000000000\n",
		"known right":                     "fn f(value: Int64) -> Int64: 3000000000 + value\n",
		"callback":                        "fn f() -> fn() -> Float64: fn(): 1e300\n",
		"function result":                 "fn thunk[T](value: T) -> fn() -> T: fn(): value\nfn f() -> fn() -> Float64: thunk(1e300)\n",
		"producer evidence":               "fn choose[T](value: T, producer: fn() -> T) -> T: value\nfn f() -> Unit:\n    let wide = choose(1e300, fn() -> Float64: 1e300)\n    let checked: Float64 = wide\n",
		"typed other argument evidence":   "fn identity[T](value:T)->T:value\nfn choose[T](left:T,right:T)->T:left\nfn f()->Unit:\n    let known: Float64 = 0.1\n    let wide = choose(identity(0.1), known)\n    let checked: Float64 = wide\n",
		"producer typed input":            "fn choose[T](value: T, producer: fn(input: Int) -> T) -> T: value\nfn f() -> Unit:\n    let wide = choose(0.1, fn(input: Int) -> Float64: 0.1)\n    let checked: Float64 = wide\n",
		"optional small integer":          "fn identity[T](value:T)->T:value\nfn f()->Optional[Int64]: some(identity(1))\n",
		"optional large integer":          "fn identity[T](value:T)->T:value\nfn f()->Optional[Int64]: some(identity(3000000000))\n",
		"optional small float":            "fn identity[T](value:T)->T:value\nfn f()->Optional[Float64]: some(identity(0.1))\n",
		"optional large float":            "fn identity[T](value:T)->T:value\nfn f()->Optional[Float64]: some(identity(1e300))\n",
		"explicit optional small integer": "fn identity[T](value:T)->T:value\nfn f()->Optional[Int64]: Optional[Int64].some(identity(1))\n",
		"explicit optional small float":   "fn identity[T](value:T)->T:value\nfn f()->Optional[Float64]: Optional[Float64].some(identity(0.1))\n",
		"match":                           "fn f(value: Optional[Int]) -> Float64:\n    return match value:\n        some(_): 1e300\n        none: 2e300\n",
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource("wide-context.ms", source, compiler.Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}
