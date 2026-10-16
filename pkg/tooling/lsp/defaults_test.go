package lsp

import (
	"strings"
	"testing"
)

func TestDefaultClosureAssignmentReferencesAndListHints(t *testing.T) {
	source := `fn answer(value: Int = (fn() -> Int:
    var current = 0
    current = current + 1
    return current
)()) -> Int:
    let callbacks = [
        fn() -> Int:
            let nested = 1
            return nested
    ]
    return value + callbacks.length()
`
	d := document{"file:///tmp/nested-defaults.ms", source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	p := Position(source, strings.Index(source, "current = 0"))
	refs := references(result, d, p, true)
	if len(refs) != 4 {
		t.Fatal("default closure assignment omitted from references", refs)
	}
	hints := inlayHints(result, d, span{position{0, 0}, Position(source, len(source))})
	positionOfNested := Position(source, strings.Index(source, "nested =")+len("nested"))
	found := false
	for _, hint := range hints {
		if hint.(map[string]any)["position"] == positionOfNested {
			found = true
		}
	}
	if !found {
		t.Fatal("closure inside list lost its inferred-local hint", hints)
	}
}

func TestDefaultArgumentEditorSupport(t *testing.T) {
	source := "fn subtract(amount: Int, deduction: Int = 1) -> Int:\n    return amount - deduction\nfn call() -> Int:\n    return sub|\n"
	item := itemNamed(completeSource(t, source), "subtract")
	if item == nil || !strings.Contains(item.Detail, "deduction: Int = ...") {
		t.Fatal("default not shown in completion", item)
	}
	text := item.TextEdit.(map[string]any)["newText"].(string)
	if text != "subtract(amount: ${1:amount})$0" {
		t.Fatal("snippet should omit optional parameter", text)
	}
	signature := signatureSource(t, strings.Replace(source, "sub|", "subtract(amount: 5, |", 1))
	label := signature["signatures"].([]any)[0].(map[string]any)["label"]
	if label != "subtract(amount: Int, deduction: Int = ...) -> Int" {
		t.Fatal(label)
	}
	items := completeSource(t, "fn combine(first: Int = 3, second: Int = fir|) -> Int:\n    return second\n")
	if itemNamed(items, "first") == nil || itemNamed(items, "second") != nil {
		t.Fatal("default scope should expose earlier parameters", items)
	}
}

func TestRenameParameterUsedInDefault(t *testing.T) {
	source := "fn combine(first: Int = 3, second: Int = first) -> Int:\n    return first + second\n"
	d := document{"file:///tmp/defaults.ms", source, 1}
	docs := map[string]document{d.URI: d}
	result := analyze(d, docs)
	renamed, err := rename(result, d, Position(source, strings.Index(source, "first:")), "input", docs)
	if err != nil {
		t.Fatal(err)
	}
	edits := renamed.(map[string]any)["documentChanges"].([]any)[0].(map[string]any)["edits"].([]any)
	if len(edits) != 3 {
		t.Fatal("rename missed default reference", renamed)
	}
}

func TestFieldDefaultNavigationAndRename(t *testing.T) {
	source := "type Options:\n    first: Int = 3\n    second: Int = first + 1\nfn read() -> Int: return Options().first\n"
	d := document{"file:///tmp/field-defaults.ms", source, 1}
	docs := map[string]document{d.URI: d}
	result := analyze(d, docs)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	pos := Position(source, strings.Index(source, "first + 1"))
	target := navigation(result, d, pos, "textDocument/definition")
	if target == nil || target.([]any)[0].(map[string]any)["range"].(span).Start != Position(source, strings.Index(source, "first:")) {
		t.Fatal("missing field definition in default", target)
	}
	renamed, err := rename(result, d, pos, "initial", docs)
	if err != nil {
		t.Fatal(err)
	}
	edits := renamed.(map[string]any)["documentChanges"].([]any)[0].(map[string]any)["edits"].([]any)
	if len(edits) != 3 {
		t.Fatal("rename missed field/default references", renamed)
	}
}

func TestFieldDefaultCompletionAndSignature(t *testing.T) {
	items := completeSource(t, "type Options:\n    first: Int = 3\n    second: Int = fir|\n    later: Int = 7\n")
	if itemNamed(items, "first") == nil || itemNamed(items, "second") != nil || itemNamed(items, "later") != nil {
		t.Fatal("incorrect field-default scope", items)
	}
	source := "type Options:\n    required: Int\n    count: Int = 3\nfn read() -> Options:\n    return Options(required: 1, |)\n"
	help := signatureSource(t, source)
	label := help["signatures"].([]any)[0].(map[string]any)["label"].(string)
	if !strings.Contains(label, "required: Int, count: Int = ...") {
		t.Fatal("field default missing from constructor signature", label)
	}
}
