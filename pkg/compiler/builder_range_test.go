package compiler_test

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestClosedBuilderGrouping(t *testing.T) {
	for _, tc := range []struct {
		name, prefix, fragment, suffix string
		selected                       bool
	}{
		{"literal", "", "\"x\"", "", true},
		{"empty", "", "\"\"", "", true},
		{"unicode", "", "\"é日\\n\"", "", true},
		{"maximum literal", "", fmt.Sprintf("%q", strings.Repeat("x", 128)), "", true},
		{"large literal", "", fmt.Sprintf("%q", strings.Repeat("x", 129)), "", false},
		{"alias", "let alias = b\n    ", "\"x\"", "", false},
		{"capture", "let read = fn() String: b.freeze()\n    ", "\"x\"", "", false},
		{"default capture", "let read = fn(value: String = b.freeze()) String: value\n    ", "\"x\"", "", false},
		{"early freeze", "let frozen = b.freeze()\n    ", "\"x\"", "", false},
		{"conditional freeze", "if flag: b.freeze()\n    ", "\"x\"", "", false},
		{"nested freeze", "", "b.freeze()", "", false},
		{"effectful fragment", "", "fragment()", "", false},
		{"late append", "", "\"x\"", "    b.append(\"later\")\n", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := "import StringBuilder from \"@std/string.ms\"\nfn fragment() String: return \"x\"\nfn probe(flag: Bool) String:\n    let b = StringBuilder()\n    " + tc.prefix + "var i = 0\n    while i < 321:\n        b.append(" + tc.fragment + ")\n        i += 1\n    let result = b.freeze()\n" + tc.suffix + "    return result\n"
			for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
				r := compiler.CompileSource("builder.ms", source, compiler.Options{BuildType: kind})
				if !r.Success() {
					t.Fatal(r.Diagnostics)
				}
				if got, want := strings.Contains(r.Source, " := 321 - i"), tc.selected && kind == compiler.Release; got != want {
					t.Fatalf("grouped=%v want%v\n%s", got, want, r.Source)
				}
			}
		})
	}
}

func TestClosedRangeGrouping(t *testing.T) {
	for _, n := range []int{0, 1, 63, 64, 65, 255, 256, 257, 319, 320, 321} {
		for _, mode := range []string{"add", "subtract", "alias", "capture", "changed", "overflow"} {
			t.Run(fmt.Sprintf("%d/%s", n, mode), func(t *testing.T) {
				items := strings.TrimSuffix(strings.Repeat("1,", n), ",")
				prefix, initial, update := "", "0", "sum += x"
				switch mode {
				case "subtract":
					update = "sum -= x"
				case "alias":
					prefix = "let alias = values\n    "
				case "capture":
					prefix = "let read = fn() Int: sum\n    sum = 0\n    "
				case "changed":
					update = "sum += 2 * x"
				case "overflow":
					initial = "9223372036854775807"
				}
				source := "fn probe() Int:\n    let values: List[Int] = [" + items + "]\n    var sum = " + initial + "\n    " + prefix + "for x in values:\n        " + update + "\n    return sum\n"
				for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
					r := compiler.CompileSource("range.ms", source, compiler.Options{BuildType: kind})
					if !r.Success() {
						t.Fatal(r.Diagnostics)
					}
					if got, want := strings.Contains(r.Source, " >= 3"), n >= 256 && (mode == "add" || mode == "subtract") && kind == compiler.Release; got != want {
						t.Fatalf("grouped=%v want%v\n%s", got, want, r.Source)
					}
				}
			})
		}
	}
}
