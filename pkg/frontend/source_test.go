package frontend_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/frontend"
)

func TestParsingPreservesSourceAndRecoveryDiagnostics(t *testing.T) {
	source := "fn value() -> Int:\r\n    return 3\r\nfn broken(\r\n"
	if module, issues := frontend.Parse("editor.ms", source, false); module != nil || len(issues) == 0 {
		t.Fatal("strict parsing accepted unfinished source", module, issues)
	}
	module, issues := frontend.Parse("editor.ms", source, true)
	if module == nil || len(issues) == 0 || len(module.Declarations) != 1 {
		t.Fatal("recovery lost the valid declaration or its diagnostics", module, issues)
	}
	if module.Source != source || module.Declarations[0].Pos.File != "editor.ms" || module.Declarations[0].Body[0].Value.Pos.Offset != 31 {
		t.Fatal("recovery changed source identity or byte positions", module)
	}
}

func TestGraphDeduplicatesImportsInDependencyOrder(t *testing.T) {
	root := t.TempDir()
	files := map[string]string{
		"shared.ms": "export fn value() -> Int: return 3\n",
		"left.ms":   "import value from \"./shared.ms\"\nexport fn left() -> Int: return value()\n",
		"right.ms":  "import value from \"./shared.ms\"\nexport fn right() -> Int: return value()\n",
		"main.ms":   "import left from \"./left.ms\"\nimport right from \"./right.ms\"\nfn result() -> Int: return left() + right()\n",
	}
	for name, source := range files {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	graph := frontend.LoadFile(filepath.Join(root, "main.ms"), frontend.Options{})
	if len(graph.Diagnostics) != 0 || len(graph.Modules) != 4 || graph.Entry != "main.ms" {
		t.Fatal("invalid module graph", graph)
	}
	for index, name := range []string{"shared.ms", "left.ms", "right.ms", "main.ms"} {
		module := graph.Modules[index]
		if module.File != name || module.Source != files[name] {
			t.Fatal("module order or source changed", module)
		}
		for _, item := range module.Imports {
			if graph.Imports[item] == "" {
				t.Fatal("missing canonical import identity", item)
			}
		}
	}
}

func TestRecoveredGraphRetainsImportDiagnosticPosition(t *testing.T) {
	root := t.TempDir()
	file := filepath.Join(root, "main.ms")
	source := "\nimport missing from \"./missing.ms\"\nfn value() -> Int: return 3\n"
	graph := frontend.LoadFile(file, frontend.Options{Recover: true, Overlay: map[string]string{file: source}})
	if len(graph.Modules) != 1 || len(graph.Diagnostics) != 1 {
		t.Fatal("recovery lost the importing module or diagnostic", graph)
	}
	issue := graph.Diagnostics[0]
	if issue.Phase != "resolution" || issue.Position.File != "main.ms" || issue.Position.Line != 2 || issue.Position.Offset != 1 {
		t.Fatal("import diagnostic lost source position", issue)
	}
}

func TestProjectTestsDiscoverTestFiles(t *testing.T) {
	root := t.TempDir()
	files := map[string]string{
		"ms.toml":           "[project]\nname = \"p\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n",
		"src/main.ms":       "export fn main() -> Int: return 0\n",
		"src/calc_test.ms":  "test \"a\":\n    return unit\n",
		"test.ms":           "test \"b\":\n    return unit\n",
		".hidden/x_test.ms": "test \"c\":\n    return unit\n",
	}
	for name, source := range files {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	manifest := filepath.Join(root, "ms.toml")
	if graph := frontend.LoadFile(manifest, frontend.Options{}); len(graph.Modules) != 1 {
		t.Fatal("tests loaded without request", graph.Modules)
	}
	graph := frontend.LoadFile(manifest, frontend.Options{Tests: true})
	if len(graph.Diagnostics) != 0 || len(graph.Modules) != 3 {
		t.Fatal("expected entry plus two test files", graph.Diagnostics, len(graph.Modules))
	}
}
