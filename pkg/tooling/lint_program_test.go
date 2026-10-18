package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"os"
	"path/filepath"
	"testing"
)

func TestSemanticLintUsesReadsAndControlFlow(t *testing.T) {
	source := "import ListBuilder from \"@std/collections.ms\"\nfn answer() Int:\n    let unused = 1\n    var written = 2\n    written = 3\n    return 0\n    return 1\n"
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
		"import parse from \"@std/json.ms\"\nfn answer(parse: Int) Int:\n    return parse\n",
		"import parse from \"@std/json.ms\"\ntype Item:\n    parse: Int\nfn answer() Item:\n    return Item(parse: 1)\n",
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
		"value.ms":  "export fn value() Int:\n    return 1\n",
		"helper.ms": "import value from \"./value.ms\"\nexport fn helper() Int:\n    return 2\n",
		"main.ms":   "import value from \"./value.ms\"\nimport helper from \"./helper.ms\"\nfn answer() Int:\n    return value() + helper()\n",
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

func unreadBindings(t *testing.T, source string) []string {
	t.Helper()
	checked := compiler.CompileSource("source.ms", source, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	var names []string
	for _, finding := range LintProgram(checked.Program) {
		if finding.Code == "MSL101" {
			names = append(names, finding.Message)
		}
	}
	return names
}

func TestSelfAssignmentDoesNotCountAsRead(t *testing.T) {
	flagged := "fn answer() Int:\n    var total = 0\n    total = total + 2\n    return 0\n"
	if got := unreadBindings(t, flagged); len(got) != 1 || got[0] != "Local binding total is never read" {
		t.Fatal("a binding read only by assignments to itself must be unread", got)
	}
	for name, source := range map[string]string{
		"returned":     "fn answer() Int:\n    var total = 0\n    total = total + 2\n    return total\n",
		"other target": "fn answer() Int:\n    var total = 0\n    var other = 0\n    other = total + 1\n    total = total + 2\n    return other\n",
		"condition":    "fn answer() Int:\n    var total = 0\n    total = total + 2\n    if total > 1:\n        return 1\n    return 0\n",
	} {
		if got := unreadBindings(t, source); len(got) != 0 {
			t.Fatal(name, "binding is observable", got)
		}
	}
}

func TestMatchArmPayloadBindingsAreLinted(t *testing.T) {
	prefix := "fn parse(text: String) Result[Int, String]:\n    return ok(1)\n"
	flagged := prefix + "fn answer() Int:\n    match parse(\"1\"):\n        ok(value): return 1\n        error(e): return 2\n"
	if got := unreadBindings(t, flagged); len(got) != 2 {
		t.Fatal("unread payload bindings must be reported", got)
	}
	clean := prefix + "fn answer() Int:\n    match parse(\"1\"):\n        ok(value): return value\n        error(_): return 2\n"
	if got := unreadBindings(t, clean); len(got) != 0 {
		t.Fatal("read or ignored payload bindings must not be reported", got)
	}
}

func TestListLiteralNeedsNoImport(t *testing.T) {
	source := "fn answer() Int:\n    let items = [1, 2, 3]\n    return items.length()\n"
	checked := compiler.CompileSource("source.ms", source, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	for _, finding := range LintProgram(checked.Program) {
		if finding.Code == "MSL102" {
			t.Fatal("prelude literal flagged unused", finding)
		}
	}
}
