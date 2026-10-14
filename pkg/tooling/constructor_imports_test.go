package tooling

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestConstructorNamesRetainImports(t *testing.T) {
	for _, tc := range []struct {
		name, module, expression string
	}{
		{"SetBuilder", "collections", "SetBuilder[String]()"},
		{"ListBuilder", "collections", "ListBuilder[String]()"},
		{"MapBuilder", "collections", "MapBuilder[String, Int]()"},
		{"Queue", "queues", "Queue[Int]()"},
		{"CsvOptions", "csv", `CsvOptions(delimiter: ",", line_ending: "\\n")`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := "import " + tc.name + " from \"@std/" + tc.module + ".ms\"\nfn example() -> Unit:\n    " + tc.expression + "\n"
			checked := compiler.CompileSource("source.ms", source, compiler.Options{AnalyzeOnly: true})
			if !checked.Success() {
				t.Fatal(checked.Diagnostics)
			}
			for _, finding := range LintProgram(checked.Program) {
				if finding.Code == "MSL102" {
					t.Fatal("constructor import flagged unused", finding)
				}
			}
		})
	}
}

func TestShadowedConstructorNameDoesNotRetainImport(t *testing.T) {
	source := `import CsvOptions from "@std/csv.ms"
fn example(CsvOptions: fn() -> Unit) -> Unit:
    CsvOptions()
`
	checked := compiler.CompileSource("source.ms", source, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	findings := LintProgram(checked.Program)
	if len(findings) != 1 || findings[0].Code != "MSL102" {
		t.Fatal("shadowing callback hid unused constructor import", findings)
	}
}
