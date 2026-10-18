package lsp

import (
	"strings"
	"testing"
)

func TestInvalidBoundsKeepEditorRecovery(t *testing.T) {
	source := "type Box[Error: Error]:\n    cause: Error\nimpl Error for Box[Error]:\n    fn message() String: self.cause.message()\ntype Neighbor:\n    value: Int\nfn read(item: Neighbor) Int: item.value\n"
	d := document{"file:///tmp/bound-recovery.ms", source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if result.Success() || !strings.Contains(result.Diagnostics[0].Message, "Error resolves to a type parameter") {
		t.Fatal(result.Diagnostics)
	}
	use := Position(source, strings.LastIndex(source, "value"))
	if navigation(result, d, use, "textDocument/definition") == nil {
		t.Fatal("lost neighboring declaration after invalid bound")
	}
	completeSource(t, strings.Replace(source, "self.cause.message()", "self.cause.|", 1))
	items := completeSource(t, strings.Replace(source, "item.value", "item.|", 1))
	if itemNamed(items, "value") == nil {
		t.Fatal("lost neighbor completion", items)
	}
}

func TestSelfReferencingInterfaceBoundKeepsCompletion(t *testing.T) {
	source := "interface Compare[T]:\n    fn compare(other: T) Int\nfn compare[T: Compare[T]](first: T, second: T) Int: first.|\n"
	if itemNamed(completeSource(t, source), "compare") == nil {
		t.Fatal("lost valid recursive interface bound")
	}
}
