package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"testing"
)

func TestInspectionCallableEntryExcludesDefaults(t *testing.T) {
	source := "fn answer(operation: fn() -> Int = fn() -> Int: 7) -> Int:\n    let result = operation()\n    return result\nexport fn main() -> Int:\n    return answer()\n"
	result := compiler.CompileSource("main.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	inspection := Inspect(result.Program)
	if len(inspection.Statements) == 0 || inspection.Statements[0].Line != 1 {
		t.Fatal("fixture lacks default callback statement", inspection.Statements)
	}
	for _, entity := range inspection.Entities {
		if entity.Name == "answer" && (entity.Entry == nil || entity.Entry.File != "main.ms" || entity.Entry.Line != 2) {
			t.Fatal("entry selected default callback", entity)
		}
	}
}
