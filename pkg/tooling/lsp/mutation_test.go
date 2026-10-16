package lsp

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestFieldWritesAndClonesKeepEditorNavigation(t *testing.T) {
	source := `type Val:
    val: Int
fn work(value: Val) -> Unit:
    let callback = fn() -> Unit:
        value.val = value.val + 1
    callback()
    let copy = value.clone()
    let list = [copy]
    list.clone().append(value)
`
	result := compiler.CompileSource("mutation-editor.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	foundWrite := false
	for _, occurrence := range sourceIndex(result) {
		if occurrence.pos.Offset == strings.Index(source, "val =") {
			foundWrite = occurrence.write && strings.HasPrefix(occurrence.key, "field:")
		}
	}
	if !foundWrite {
		t.Fatal("field assignment in closure lost write navigation")
	}
}
