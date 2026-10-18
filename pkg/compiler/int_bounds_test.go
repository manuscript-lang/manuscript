package compiler_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestScalarIntBoundsLowering(t *testing.T) {
	for _, tc := range []struct {
		name, prefix, loop, body string
		checked                  bool
	}{
		{"sum induction", "var sum = 0\n    var i = 0", "i < 1000000", "sum += i\n        i += 1", false},
		{"identity", "var sum = 0\n    var i = 0", "i < 1000000", "sum += identity[Int](i)\n        i += 1", false},
		{"conditional", "var sum = 0\n    var i = 0", "i < 1000000", "if flag:\n            sum += 1\n        i += 1", false},
		{"negative descending", "var sum = 0\n    var i = -1", "i > -1000", "sum += i\n        i -= 1", false},
		{"multiple updates", "var sum = 0\n    var i = 0", "i < 1000", "sum += i\n        sum -= 1\n        i += 1", false},
		{"dynamic start", "var sum = 0\n    var i = start", "i < 1000", "sum += i\n        i += 1", true},
		{"dynamic sum", "var sum = start\n    var i = 0", "i < 1000", "sum += i\n        i += 1", true},
		{"overflow", "var sum = 9223372036854775807\n    var i = 0", "i < 1", "sum += 1\n        i += 1", true},
		{"intermediate overflow", "var sum = 1\n    var i = 0", "i < 1", "sum += 9223372036854775807\n        sum -= 9223372036854775807\n        i += 1", true},
		{"after step", "var sum = 9223372036854775807\n    var i = 0", "i < 1", "i += 1\n        sum += i", true},
		{"peer carry", "var sum = 9223372036854775807\n    var peer = 0\n    var i = 0", "i < 2", "sum += peer\n        peer += 1\n        i += 1", true},
		{"self carry", "var sum = 1\n    var i = 0", "i < 1000", "sum += sum\n        i += 1", true},
		{"reset", "var sum = 0\n    var i = 0", "i < 1000", "sum += i\n        i = start\n        i += 1", true},
		{"continue", "var sum = 0\n    var i = 0", "i < 1000", "sum += i\n        if flag:\n            continue\n        i += 1", true},
		{"break", "var sum = 0\n    var i = 0", "i < 1000", "sum += i\n        if flag:\n            break\n        i += 1", true},
		{"nested", "var sum = 0\n    var i = 0", "i < 1000", "sum += i\n        var j = 0\n        while j < 2:\n            j += 1\n        i += 1", true},
		{"effectful result", "var sum = 0\n    var i = 0", "i < 1000", "sum += effect(i)\n        i += 1", true},
		{"distance overflow", "var sum = 0\n    var i = -9223372036854775808", "i < 9223372036854775807", "sum += i\n        i += 1", true},
		{"expression write", "var sum = 0\n    var i = 0", "i < 2", "let x = match some(0):\n            some(n):\n                sum = start\n                n\n            none: 0\n        sum += i\n        i += 1", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := "fn identity[T](value: T) T: return value\nfn effect(value: Int) Int: return value + 1\n" +
				"fn probe(start: Int, flag: Bool) Int:\n    " + tc.prefix + "\n    while " + tc.loop + ":\n        " + tc.body + "\n    return sum\n"
			r := compiler.CompileSource("bounds.ms", source, compiler.Options{})
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			if got := strings.Contains(r.Source, "sum = rt.IntAdd("); got != tc.checked {
				t.Fatalf("checked=%v want %v:\n%s", got, tc.checked, r.Source)
			}
		})
	}
}

func TestScalarIntBoundsIsolateBranchesAndClosures(t *testing.T) {
	for _, source := range []string{
		`fn probe(value: Int, flag: Bool) Int:
    var sum = value
    if flag:
        sum = 0
    else:
        sum += 1
    return sum
`,
		`fn probe(value: Int) Int:
    var sum = 0
    let callback = fn() Int:
        return sum + value
    sum = value
    return callback()
`,
		`fn probe(value: Int, flag: Bool) Int:
    var sum = 0
    if flag:
        sum = value
    sum += 1
    return sum
`,
	} {
		r := compiler.CompileSource("bounds.ms", source, compiler.Options{})
		if !r.Success() || !strings.Contains(r.Source, "rt.IntAdd(") {
			t.Fatalf("lost checked arithmetic: %v\n%s", r.Diagnostics, r.Source)
		}
	}
}

func TestScalarIntBoundsPreserveDebugChecks(t *testing.T) {
	r := compiler.CompileSource("bounds.ms", `fn probe() Int:
    var sum = 0
    var i = 0
    while i < 100:
        sum += i
        i += 1
    return sum
`, compiler.Options{BuildType: compiler.Debug})
	if !r.Success() || !strings.Contains(r.Source, "sum = rt.IntAdd(") {
		t.Fatalf("Debug lost checked source arithmetic: %v\n%s", r.Diagnostics, r.Source)
	}
}

func BenchmarkScalarIntBoundsScaling(b *testing.B) {
	for _, n := range []int{128, 256, 512} {
		var source strings.Builder
		source.WriteString("fn probe() Int:\n    var sum = 0\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&source, "    var i%d = 0\n    while i%d < 100:\n        sum += i%d\n        i%d += 1\n", i, i, i, i)
		}
		source.WriteString("    return sum\n")
		text := source.String()
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				result := compiler.CompileSource("scaling.ms", text, compiler.Options{})
				if !result.Success() {
					b.Fatal(result.Diagnostics)
				}
			}
		})
	}
}

func TestScalarIntMultiplyBounds(t *testing.T) {
	for _, tc := range []struct {
		value, operand string
		checked        bool
	}{
		{"12", "7", false}, {"-12", "-7", false}, {"-9223372036854775808", "-1", true},
		{"3037000499", "3037000499", false}, {"3037000500", "3037000500", true},
		{"9223372036854775807", "2", true},
	} {
		source := "fn probe() Int:\n    let value = " + tc.value + "\n    return value * " + tc.operand + "\n"
		r := compiler.CompileSource("multiply.ms", source, compiler.Options{})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if got := strings.Contains(r.Source, "rt.IntMultiply("); got != tc.checked {
			t.Fatalf("%s*%s checked=%v want %v:\n%s", tc.value, tc.operand, got, tc.checked, r.Source)
		}
		if !tc.checked && !strings.Contains(r.Source, " * ") {
			t.Fatalf("lost multiplication operator:\n%s", r.Source)
		}
	}
}
