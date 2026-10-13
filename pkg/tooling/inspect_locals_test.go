package tooling

import (
	"encoding/json"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestLocalMetadataIsDeterministic(t *testing.T) {
	source := "fn answer(input: Int) -> Int:\n    let value = input\n    return value\n"
	compile := func() []byte {
		result := compiler.CompileSource("main.ms", source, compiler.Options{})
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
		inspection := Inspect(result.Program)
		if len(inspection.Locals) != 2 {
			t.Fatal(inspection.Locals)
		}
		for _, local := range inspection.Locals {
			if !strings.HasSuffix(local.GoID, "_"+local.Name) || local.Span.File != "main.ms" || local.Type != "Int" {
				t.Fatal(local)
			}
		}
		data, err := json.Marshal(inspection)
		if err != nil {
			t.Fatal(err)
		}
		return data
	}
	first, second := compile(), compile()
	if string(first) != string(second) {
		t.Fatal("inspection depends on map iteration")
	}
}
