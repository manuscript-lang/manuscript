package tooling

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestInspectDescribesConstantsAsConstants(t *testing.T) {
	source := "let LIMIT = 10\nfn size() Int:\n    return LIMIT\n"
	result := compiler.CompileSource("main.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	inspection := Inspect(result.Program)
	kinds := map[string]Entity{}
	for _, entity := range inspection.Entities {
		kinds[entity.Name] = entity
	}
	if limit := kinds["LIMIT"]; limit.Kind != "constant" || limit.Type != "Int" || limit.ID != "main.ms#constant#LIMIT" {
		t.Fatalf("constant entity: %+v", limit)
	}
	if size := kinds["size"]; size.Kind != "fn" || size.Type != "fn()->Int" {
		t.Fatalf("function entity: %+v", size)
	}
	if len(inspection.Calls) != 1 || inspection.Calls[0].Kind != "constant" || inspection.Calls[0].Target != "main.ms#constant#LIMIT" {
		t.Fatalf("constant use: %+v", inspection.Calls)
	}
}
