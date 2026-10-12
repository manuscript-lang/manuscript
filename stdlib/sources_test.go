package stdlib_test

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/manuscript-lang/manuscript/parser"
	"github.com/manuscript-lang/manuscript/stdlib"
)

func TestPinnedSources(t *testing.T) {
	directory := t.TempDir()
	if err := stdlib.Materialize(directory); err != nil {
		t.Fatal(err)
	}
	entries, err := stdlib.Sources.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		source, err := stdlib.Sources.ReadFile(entry.Name())
		if err != nil {
			t.Fatal(err)
		}
		actual, err := os.ReadFile(filepath.Join(directory, entry.Name()))
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(source, actual) {
			t.Errorf("materialized %s differs", entry.Name())
		}
		if filepath.Ext(entry.Name()) == ".ms" {
			_, diagnostics := parser.ParseLibrary("@std/"+entry.Name(), string(source))
			if diagnostics != nil {
				t.Errorf("%s: %v", entry.Name(), diagnostics)
			}
		}
	}
}

func TestLibraryDeclarationsRequireLibraryMode(t *testing.T) {
	for _, source := range []string{"export fn native(value: Int) -> Int\n", "export type Opaque\n"} {
		if _, diagnostics := parser.ParseLibrary("library.ms", source); diagnostics != nil {
			t.Fatal(diagnostics)
		}
		if _, diagnostics := parser.Parse("application.ms", source); diagnostics == nil {
			t.Errorf("application accepted native declaration %q", source)
		}
	}
}
