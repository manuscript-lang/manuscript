package lsp

import (
	"strings"
	"testing"
)

func TestRecursiveFieldsKeepEditorNavigation(t *testing.T) {
	source := "type Node:\n    value: Int\n    next: Optional[Node]\nfn read(node: Node) -> Int:\n    return node.next.unwrap().value\n"
	d := document{"file:///tmp/recursive-editor.ms", source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	use := Position(source, strings.LastIndex(source, "value"))
	definition := navigation(result, d, use, "textDocument/definition")
	if definition == nil || definition.([]any)[0].(map[string]any)["range"].(span).Start != Position(source, strings.Index(source, "value")) {
		t.Fatal("lost recursive field definition", definition)
	}
	if navigation(result, d, use, "textDocument/hover") == nil {
		t.Fatal("lost field hover")
	}
	items := completeSource(t, strings.Replace(source, "unwrap().value", "unwrap().|", 1))
	if itemNamed(items, "value") == nil || itemNamed(items, "next") == nil || itemNamed(items, "hash") != nil {
		t.Fatal("incorrect recursive field members", items)
	}
}

func TestRecursiveGenericEditorDiagnostic(t *testing.T) {
	source := "type Grow[T]:\n    next: fn() -> Grow[List[T]]\n"
	d := document{"file:///tmp/recursive-editor.ms", source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if len(result.Diagnostics) != 1 {
		t.Fatal(result.Diagnostics)
	}
	diagnostic := result.Diagnostics[0]
	if diagnostic.Position.Line != 2 || diagnostic.Position.Column != 5 || !strings.Contains(diagnostic.Message, "Grow.next") {
		t.Fatal(diagnostic)
	}
}
