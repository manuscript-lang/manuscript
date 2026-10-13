package lsp

import (
	"strings"
	"testing"
)

func TestInferredCallbackParameterNavigation(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("import List from \"@std/collections.ms\"\nfn answer() -> Unit:\n    let values = [1, 2].map(fn(value): value + 1)\n", "\n", ending)
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
		if _, err := rename(result, d, declaration, "input"); err == nil {
			t.Fatal("rename must preserve contextual function parameter labels")
		}
	}
}
