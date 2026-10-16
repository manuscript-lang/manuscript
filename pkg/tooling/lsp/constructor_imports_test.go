package lsp

import (
	"strings"
	"testing"
)

func TestConstructorImportsRemainAvailableInEditor(t *testing.T) {
	source := `import SetBuilder from "@std/collections.ms"
import CsvOptions from "@std/csv.ms"
fn example() -> Unit:
    SetBuilder[String]()
    CsvOptions(delimiter: ",", line_ending: "\n")
`
	d := document{"file:///tmp/constructor-imports.ms", source, 1}
	checked := analyze(d, map[string]document{d.URI: d})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	actions := editorActions(d, checked, span{position{}, Position(source, len(source))}, []string{"quickfix"})
	if len(actions) != 0 {
		t.Fatal("used constructor imports offered for removal", actions)
	}
	for _, name := range []string{"SetBuilder", "CsvOptions"} {
		pos := Position(source, strings.LastIndex(source, name))
		if navigation(checked, d, pos, "textDocument/definition") == nil {
			t.Fatal("constructor definition missing", name)
		}
		localReferences := 0
		for _, ref := range references(checked, d, pos) {
			if ref.(map[string]any)["uri"] == d.URI {
				localReferences++
			}
		}
		if localReferences != 2 {
			t.Fatalf("%s references should include import and constructor; got %d", name, localReferences)
		}
	}
}
