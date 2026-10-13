package lsp

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestExpectedGenericResultEditorInformation(t *testing.T) {
	source := `fn absent[T]() -> Optional[T]: none
fn transform[T, U](callback: fn(value: T) -> U) -> fn(value: T) -> U: callback
fn answer() -> Unit:
    let empty: Optional[Int] = absent()
    let callback: fn(value: Int) -> String = transform(fn(item): item.toString())
`
	d := document{"file:///tmp/contextual-generics.ms", source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	declaration := Position(source, strings.Index(source, "item):"))
	use := Position(source, strings.Index(source, "item.toString"))
	definition := navigation(result, d, use, "textDocument/definition")
	if definition == nil || definition.([]any)[0].(map[string]any)["range"].(span).Start != declaration {
		t.Fatal("lost result-context parameter definition", definition)
	}
	hover := navigation(result, d, use, "textDocument/hover")
	data, err := json.Marshal(hover)
	if err != nil || !strings.Contains(string(data), "Int") {
		t.Fatalf("missing inferred parameter type: %s, %v", data, err)
	}
	call := Position(source, strings.LastIndex(source, "absent()"))
	hover = navigation(result, d, call, "textDocument/hover")
	data, err = json.Marshal(hover)
	if err != nil || !strings.Contains(string(data), "Optional[Int]") {
		t.Fatalf("missing inferred result: %s, %v", data, err)
	}
}

func TestExpectedGenericResultEditorConflict(t *testing.T) {
	source := `fn identity[T](value: T) -> T: value
fn first() -> String: identity(1)
fn second() -> Int: identity(2)
`
	d := document{"file:///tmp/contextual-generic-conflict.ms", source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if len(result.Diagnostics) != 1 || !strings.Contains(result.Diagnostics[0].Message, "expected String, found Int") {
		t.Fatalf("expected one conflict diagnostic, got %v", result.Diagnostics)
	}
	call := Position(source, strings.LastIndex(source, "identity(2)"))
	if navigation(result, d, call, "textDocument/definition") == nil {
		t.Fatal("conflict erased independent declaration information")
	}
}
