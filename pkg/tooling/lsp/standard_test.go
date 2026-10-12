package lsp

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestDiskStandardDeclarationsUseOrdinarySyntax(t *testing.T) {
	directory := t.TempDir()
	for _, expected := range checker.StandardModules() {
		t.Run(expected.File, func(t *testing.T) {
			d := document{fileURI(filepath.Join(directory, filepath.Base(expected.File))), expected.Source, 1}
			if _, err := parser.Parse(filepath.Base(expected.File), d.Text); err != nil {
				t.Fatal("stdlib is not valid ordinary syntax", err)
			}
			if _, err := tooling.Format(filepath.Base(expected.File), d.Text); err != nil {
				t.Fatal("stdlib cannot be formatted", err)
			}
			checked := analyze(d, map[string]document{d.URI: d})
			if !checked.Success() || module(checked, d) != expected {
				t.Fatal("missing native binding context", checked.Diagnostics)
			}
			changed := d
			changed.Text += "fn missing_binding() -> Int:\n"
			if result := analyze(changed, map[string]document{changed.URI: changed}); result.Success() {
				t.Fatal("unbound native declaration accepted")
			}
		})
	}
}

func TestDiskCommandsDefinition(t *testing.T) {
	source, err := standardLibrarySource("manuscript-stdlib:/process.ms")
	if err != nil {
		t.Fatal(err)
	}
	d := document{fileURI(filepath.Join(t.TempDir(), "process.ms")), source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	pos := Position(source, strings.Index(source, "commands() -> Commands")+len("commands() -> "))
	if target := navigation(result, d, pos, "textDocument/definition"); target == nil || target.([]any)[0].(map[string]any)["uri"] != "manuscript-stdlib:///process.ms" {
		t.Fatal("missing Commands definition", target)
	}
}
