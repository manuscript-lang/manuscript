package stdlib_test

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
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
			_, diagnostics := parser.Parse(entry.Name(), string(source))
			if diagnostics != nil {
				t.Errorf("%s: %v", entry.Name(), diagnostics)
			}
			formatted, err := tooling.Format(entry.Name(), string(source))
			if err != nil {
				t.Errorf("format %s: %v", entry.Name(), err)
				continue
			}
			if again, err := tooling.Format(entry.Name(), formatted); err != nil || again != formatted {
				t.Errorf("format %s is not idempotent: %v", entry.Name(), err)
			}
		}
	}
}
