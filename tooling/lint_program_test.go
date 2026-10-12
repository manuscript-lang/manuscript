package tooling

import (
	"github.com/manuscript-lang/manuscript/compiler"
	"testing"
)

func TestSemanticLintUsesReadsAndControlFlow(t *testing.T) {
	source := "import List from \"@std/collections.ms\"\nfn answer() -> Int:\n    let unused = 1\n    var written = 2\n    written = 3\n    return 0\n    return 1\n"
	checked := compiler.CompileSource("source.ms", source, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	findings := LintProgram(checked.Program)
	counts := map[string]int{}
	for _, issue := range findings {
		counts[issue.Code]++
	}
	if counts["MSL101"] != 2 || counts["MSL102"] != 1 || counts["MSL103"] != 1 {
		t.Fatal(findings)
	}
}

func TestListLiteralRetainsItsRequiredImport(t *testing.T) {
	source := "import List from \"@std/collections.ms\"\nfn answer() -> Int:\n    let items = [1, 2, 3]\n    return items.length()\n"
	checked := compiler.CompileSource("source.ms", source, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	for _, finding := range LintProgram(checked.Program) {
		if finding.Code == "MSL102" {
			t.Fatal("required literal import flagged unused", finding)
		}
	}
}
