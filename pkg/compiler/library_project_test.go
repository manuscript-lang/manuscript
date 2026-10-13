package compiler

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func libraryProject(t *testing.T) (string, func(string, string)) {
	t.Helper()
	root := t.TempDir()
	write := func(name, text string) {
		t.Helper()
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(text), 0600); err != nil {
			t.Fatal(err)
		}
	}
	write("ms.toml", "# library\n[project]\nname = \"library\"\nsource = \"src\"\n[aliases]\n\"@lib\" = \"src\"\n")
	write("src/value.ms", "export fn value() -> Int: return 3\n")
	return filepath.Join(root, "ms.toml"), write
}

func TestLibraryProjectChecksAllSourcesAndTests(t *testing.T) {
	manifest, write := libraryProject(t)
	write("src/unimported.ms", "fn broken() -> Int: return \"bad\"\n")
	write("tests/value_test.ms", "import value from \"@lib/value.ms\"\ntest \"value\":\n    let n = value()\n")
	for _, options := range []Options{{AnalyzeOnly: true, Entry: true}, {AnalyzeOnly: true}, {Tests: true}} {
		result := CompileFile(manifest, options)
		if result.Success() || len(result.Diagnostics) != 1 || result.Diagnostics[0].Position.File != "src/unimported.ms" {
			t.Fatalf("library skipped unimported error: %v", result.Diagnostics)
		}
	}
	write("src/unimported.ms", "export fn other() -> Int: return 4\n")
	for _, options := range []Options{{AnalyzeOnly: true, Entry: true}, {AnalyzeOnly: true}, {Tests: true}} {
		result := CompileFile(manifest, options)
		if !result.Success() || result.Program == nil || len(result.Program.ModuleSymbols("src/unimported.ms")) == 0 || len(result.Program.ModuleSymbols("tests/value_test.ms")) == 0 {
			t.Fatalf("library modules missing: %+v", result)
		}
	}
	result := CompileFile(manifest, Options{Entry: true})
	if result.Success() || result.Source != "" || len(result.Diagnostics) != 1 || result.Diagnostics[0].Position.File != "ms.toml" || result.Diagnostics[0].Position.Line != 2 || !strings.Contains(result.Diagnostics[0].Message, "add entry =") {
		t.Fatalf("executable library diagnostic: %+v", result)
	}
}

func TestEmptyLibraryCanBeCheckedAndTested(t *testing.T) {
	manifest, _ := libraryProject(t)
	if err := os.Remove(filepath.Join(filepath.Dir(manifest), "src/value.ms")); err != nil {
		t.Fatal(err)
	}
	for _, options := range []Options{{AnalyzeOnly: true}, {Tests: true}} {
		result := CompileFile(manifest, options)
		if !result.Success() || result.Program == nil || options.Tests && result.Source == "" {
			t.Fatalf("empty library: %+v", result)
		}
	}
}

func TestManifestErrorsMapProjectLocationsToSyntax(t *testing.T) {
	manifest, write := libraryProject(t)
	source := "\ufeff# café\r\n[project]\r\nname = \"library\"\r\nsource = \"src\"\r\n[aliases]\r\n  \"@std\" = \"src\"\r\n"
	write("ms.toml", source)
	result := CompileFile(manifest, Options{AnalyzeOnly: true})
	if result.Success() || len(result.Diagnostics) != 1 {
		t.Fatal(result.Diagnostics)
	}
	pos := result.Diagnostics[0].Position
	if pos.File != "ms.toml" || pos.Line != 6 || pos.Column != 3 || pos.Offset != strings.Index(source, "\"@std\"") || strings.Contains(result.Diagnostics[0].Message, "ms.toml:") {
		t.Fatalf("position was flattened: %+v", result.Diagnostics)
	}
}
