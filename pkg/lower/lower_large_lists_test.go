package lower

import (
	"regexp"
	"strings"
	"testing"
)

func largeListSource(typ, element string, n int, extra string) string {
	return "" + extra +
		"fn values(value: Int) -> List[" + typ + "]:\n    return [" + strings.TrimSuffix(strings.Repeat(element+", ", n), ", ") + "]\n"
}

func TestLargeConstantListsLowerToTypedTables(t *testing.T) {
	for _, tc := range []struct {
		typ, element, extra, table string
	}{
		{"Int", "7", "", "[]int64{7, 7"},
		{"Int", "-7", "", "[]int64{-7, -7"},
		{"Int", "-9223372036854775808", "", "[]int64{-9223372036854775808,"},
		{"Float", "1.25", "", "[]float64{1.25, 1.25"},
		{"Bool", "true", "", "[]bool{true, true"},
		{"String", `"λ\n\""`, "", `[]string{"λ\n\"", "λ\n\""`},
		// Go folds -0.0 to positive zero, so negative Floats keep checked lowering.
		{"Float", "-1.25", "", ""},
		{"Float", "-0.0", "", ""},
		{"Int", "value", "", ""},
		{"String", `"v{value}"`, "", ""},
		{"Box", "Box(7)", "type Box:\n    value: Int\n", ""},
		{"List[Int]", "[7]", "", ""},
	} {
		t.Run(tc.typ+tc.element, func(t *testing.T) {
			r := compileSource("literal.ms", largeListSource(tc.typ, tc.element, 300, tc.extra))
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			if tc.table == "" {
				if strings.Contains(r.Source, "rt.ListTable") {
					t.Fatal("ineligible literal lowered to a table")
				}
				return
			}
			if !strings.Contains(r.Source, "var listData0 = "+tc.table) || !strings.Contains(r.Source, "var listTable1 rt.ListTable[") || !strings.Contains(r.Source, "listTable1.List(") {
				t.Fatalf("missing typed table %q\n%s", tc.table, r.Source)
			}
			if strings.Contains(r.Source, "rt.Value{") {
				t.Fatal("table literal still builds boxed items in the function body")
			}
		})
	}
}

func TestLargeListThreshold(t *testing.T) {
	for _, n := range []int{largeListThreshold - 1, largeListThreshold} {
		r := compileSource("literal.ms", largeListSource("Int", "7", n, ""))
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if strings.Contains(r.Source, "rt.ListTable") != (n >= largeListThreshold) {
			t.Fatal("incorrect threshold", n)
		}
	}
}

var chunkPattern = regexp.MustCompile(`func\(temporary\d+ \*\[(\d+)\]rt\.Value\)`)

// A computed literal is evaluated in order by bounded closures; each one
// holds at most largeListChunk item assignments.
func TestLargeComputedListsAreChunked(t *testing.T) {
	source := largeListSource("Int", "value + 1", 300, "")
	r := compileSource("literal.ms", source)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	var sizes []string
	for _, match := range chunkPattern.FindAllStringSubmatch(r.Source, -1) {
		sizes = append(sizes, match[1])
	}
	if strings.Join(sizes, ",") != "64,64,64,64,44" {
		t.Fatalf("chunks %v\n%s", sizes, r.Source)
	}
	if strings.Count(r.Source, "] = rt.IntAddAt(") != 300 {
		t.Fatal("not every item is assigned once")
	}
	// Debug builds keep the existing lowering pinned by the debugger tests.
	analyzed := analyzeSource("literal.ms", source)
	debug, err := Go(analyzed.Program, "literal.ms", Options{DebugLiterals: true})
	if err != nil {
		t.Fatal(err)
	}
	if chunkPattern.MatchString(debug) || strings.Contains(debug, "rt.ListTable") {
		t.Fatal("Debug lowering changed")
	}
}
