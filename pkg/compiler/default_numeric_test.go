package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestDefaultNumericLiteralWidths(t *testing.T) {
	for _, source := range []string{"fn identity[T](x:T)->T:x\nfn f()->Optional[Int64]:\n    let small = identity(1)\n    return some(small)\n", "fn fixed(x:Int)->Int:x\nfn f()->Optional[Int64]:some(fixed(1))\n", "fn identity[T](x:T)->T:x\nfn f()->Optional[Int64]:some(identity[Int](1))\n", "fn identity[T](x:T)->T:x\nfn f()->Optional[Float64]:\n    let small = 0.1\n    return some(identity(small))\n", "let x = 2147483648\n", "let x = -2147483649\n", "let x = 1e39\n", "fn f(x: Int64) -> Int64: x\nfn example() -> Unit:\n    let x = 3\n    let y = f(x)\n", "fn f(x: Float64) -> Float64: x\nfn example() -> Unit:\n    let x = 3.0\n    let y = f(x)\n", "let x: Int64 = 3\nlet y = 4\nlet z = x + y\n"} {
		if result := compiler.CompileSource("width.ms", wrapNumericTest(source), compiler.Options{}); result.Success() {
			t.Fatalf("unexpected acceptance: %s", source)
		}
	}
	for _, source := range []string{"let x = -2147483648\nlet y = 2147483647\n", "let x: Int64 = 3000000000\n", "let x: Float64 = 1e300\n", "fn f() -> Int64: 3000000000 + 4\n", "fn identity[T](x:T)->T:x\nfn example() -> Unit:\n    let x: Optional[Int64] = some(identity(3000000000))\n"} {
		if result := compiler.CompileSource("width.ms", wrapNumericTest(source), compiler.Options{}); !result.Success() {
			t.Fatalf("unexpected rejection: %s\n%v", source, result.Diagnostics)
		}
	}
	result := compiler.CompileSource("width.ms", wrapNumericTest("let x = 0.1\nlet y = 1\n"), compiler.Options{})
	if !result.Success() || !strings.Contains(result.Source, "float32(0.1)") || !strings.Contains(result.Source, "int32(1)") {
		t.Fatalf("wrong scalar lowering: %v\n%s", result.Diagnostics, result.Source)
	}
}

func wrapNumericTest(source string) string {
	if strings.HasPrefix(source, "fn ") {
		return source
	}
	return "fn example() -> Unit:\n    " + strings.ReplaceAll(strings.TrimSpace(source), "\n", "\n    ") + "\n"
}
