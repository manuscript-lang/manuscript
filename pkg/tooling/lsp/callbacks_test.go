package lsp

import (
	"strings"
	"testing"
)

func TestInferredCallbackParameterNavigation(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("fn answer() -> Unit:\n    let values = [1, 2].map(fn(value): value + 1)\n", "\n", ending)
		d := document{"file:///tmp/callback.ms", source, 1}
		result := analyze(d, map[string]document{d.URI: d})
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
		declaration := Position(source, strings.Index(source, "value):"))
		use := Position(source, strings.Index(source, "value +"))
		definition := navigation(result, d, use, "textDocument/definition")
		if definition == nil || definition.([]any)[0].(map[string]any)["range"].(span).Start != declaration {
			t.Fatal("lost inferred parameter definition", definition)
		}
		if navigation(result, d, declaration, "textDocument/hover") == nil || len(references(result, d, use, true)) != 2 {
			t.Fatal("lost inferred parameter information")
		}
		if _, err := rename(result, d, declaration, "input"); err != nil {
			t.Fatal("local callback names may be renamed independently of call labels", err)
		}
	}
}

func TestNestedCallbackProbeNavigation(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("fn answer() -> Unit:\n    let offset = 7\n    let values = [1].map(fn(outer): [2].map(fn(inner): outer + inner + offset))\n", "\n", ending)
		d := document{"file:///tmp/nested-callback.ms", source, 1}
		result := analyze(d, map[string]document{d.URI: d})
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
		for _, name := range []string{"outer", "inner", "offset"} {
			declaration := Position(source, strings.Index(source, name))
			use := Position(source, strings.LastIndex(source, name))
			definition := navigation(result, d, use, "textDocument/definition")
			if definition == nil || definition.([]any)[0].(map[string]any)["range"].(span).Start != declaration {
				t.Fatalf("lost %s definition: %v", name, definition)
			}
			if navigation(result, d, use, "textDocument/hover") == nil || len(references(result, d, use, true)) != 2 {
				t.Fatalf("lost %s metadata", name)
			}
			if _, err := rename(result, d, declaration, "renamed"); err != nil {
				t.Fatal(err)
			}
		}
	}
}

func TestRejectedNestedCallbackProbeNavigation(t *testing.T) {
	expression := "[1].map(fn(outer): " + strings.Repeat("[2].map(fn(inner): ", 39) + "outer + missing" + strings.Repeat(")", 40)
	source := "fn answer() -> Unit:\n    let values = " + expression + "\n"
	d := document{"file:///tmp/rejected-callback.ms", source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if len(result.Diagnostics) != 1 || !strings.Contains(result.Diagnostics[0].Message, "missing") {
		t.Fatalf("lost root diagnostic: %v", result.Diagnostics)
	}
	declaration := Position(source, strings.Index(source, "outer"))
	use := Position(source, strings.LastIndex(source, "outer"))
	definition := navigation(result, d, use, "textDocument/definition")
	if definition == nil || definition.([]any)[0].(map[string]any)["range"].(span).Start != declaration {
		t.Fatal("lost rejected callback capture", definition)
	}
	if len(references(result, d, use, true)) != 2 {
		t.Fatal("lost rejected callback references")
	}
}
