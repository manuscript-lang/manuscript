package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestCounterAggregateSelection(t *testing.T) {
	for _, tc := range []struct {
		name, prefix, body, identity string
		aggregate                    bool
	}{
		{"constant", "", "sum += 3\n        i += 1", "", true},
		{"subtract", "", "sum -= 3\n        i += 1", "", true},
		{"affine", "", "sum += i\n        i += 1", "", true},
		{"affine subtract", "", "sum -= i\n        i += 1", "", true},
		{"identity", "", "sum += identity(i)\n        i += 1", "fn identity(n: Int) Int: return n\n", true},
		{"generic identity", "", "sum += identity[Int](i)\n        i += 1", "fn identity[T](n: T) T: return n\n", true},
		{"default identity", "", "sum += identity(i)\n        i += 1", "fn identity(n: Int = 0) Int: return n\n", false},
		{"changed return", "", "sum += identity(i)\n        i += 1", "fn identity(n: Int) Int: return n + 1\n", false},
		{"captured carry", "let read = fn() Int: sum\n    sum = 0\n    i = 0\n    ", "sum += 3\n        i += 1", "", false},
		{"captured counter", "let read = fn() Int: i\n    i = 0\n    sum = 0\n    ", "sum += 3\n        i += 1", "", false},
		{"captured stride", "var stride = 3\n    let read = fn() Int: stride\n    stride = 3\n    sum = 0\n    i = 0\n    ", "sum += stride\n        i += 1", "", false},
		{"default capture", "let read = fn(value: Int = sum) Int: value\n    sum = 0\n    i = 0\n    ", "sum += 3\n        i += 1", "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := tc.identity + "fn probe() Int:\n    var sum = 0\n    var i = 0\n    " + tc.prefix + "while i < 321:\n        " + tc.body + "\n    return sum\n"
			for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
				r := compiler.CompileSource("aggregate.ms", source, compiler.Options{BuildType: kind})
				if !r.Success() {
					t.Fatal(r.Diagnostics)
				}
				if got, want := strings.Contains(r.Source, " := 321 - i"), tc.aggregate && kind == compiler.Release; got != want {
					t.Fatalf("aggregate=%v want %v (%s):\n%s", got, want, kind, r.Source)
				}
			}
		})
	}
}

func TestCounterAggregateRejectsUnsafePrefixes(t *testing.T) {
	for _, source := range []string{
		`fn probe() Int:
    var sum = 9223372036854775807
    var i = 0
    while i < 321:
        sum += i
        i += 1
    return sum
`,
		`fn probe() Int:
    var sum = 0
    var i = -9223372036854775808
    while i < -9223372036854775487:
        sum += i
        i += 1
    return sum
`,
	} {
		r := compiler.CompileSource("unsafe.ms", source, compiler.Options{})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if !strings.Contains(r.Source, "sum = rt.IntAdd(") || strings.Contains(r.Source, " / 2") {
			t.Fatalf("unsafe source aggregated:\n%s", r.Source)
		}
	}
}

func TestCounterAggregatePrivateCellSelection(t *testing.T) {
	for _, alias := range []bool{false, true} {
		prefix := ""
		if alias {
			prefix = "let alias = cell\n    "
		}
		r := compiler.CompileSource("cell.ms", recordCellSource+"fn probe() Int:\n    let cell = Cell(0)\n    "+prefix+"var i = 0\n    while i < 321:\n        cell.bump(3)\n        i += 1\n    return cell.total\n", compiler.Options{})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if got := strings.Contains(r.Source, " := 321 - i"); got == alias {
			t.Fatalf("cell alias=%v aggregate=%v:\n%s", alias, got, r.Source)
		}
	}
}
