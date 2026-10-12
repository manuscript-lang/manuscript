package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"os"
	"path/filepath"
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

func TestUnusedImportsFollowResolvedNames(t *testing.T) {
	for _, source := range []string{
		"import normalize from \"@std/string.ms\"\nfn answer(normalize: Int) -> Int:\n    return normalize\n",
		"import normalize from \"@std/string.ms\"\ntype Item:\n    normalize: Int\nfn answer() -> Item:\n    return Item(normalize: 1)\n",
	} {
		checked := compiler.CompileSource("source.ms", source, compiler.Options{AnalyzeOnly: true})
		if !checked.Success() {
			t.Fatal(checked.Diagnostics)
		}
		found := false
		for _, issue := range LintProgram(checked.Program) {
			if issue.Code == "MSL102" {
				found = true
			}
		}
		if !found {
			t.Fatal("a shadowing local or field label concealed an unused import")
		}
	}
}

func TestImportUsesStayWithinTheirModule(t *testing.T) {
	root := t.TempDir()
	for name, source := range map[string]string{
		"value.ms":  "export fn value() -> Int:\n    return 1\n",
		"helper.ms": "import value from \"./value.ms\"\nexport fn helper() -> Int:\n    return 2\n",
		"main.ms":   "import value from \"./value.ms\"\nimport helper from \"./helper.ms\"\nfn answer() -> Int:\n    return value() + helper()\n",
	} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	checked := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	var unused []string
	for _, issue := range LintProgram(checked.Program) {
		if issue.Code == "MSL102" {
			unused = append(unused, issue.Position.File)
		}
	}
	if len(unused) != 1 || unused[0] != "helper.ms" {
		t.Fatal("import used in another module hid an unused local import", unused)
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
