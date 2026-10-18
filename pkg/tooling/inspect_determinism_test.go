package tooling_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"strings"
	"testing"
)

func TestInspectionDeterminismAndOriginalSpans(t *testing.T) {
	source := "fn one() Int:\r\n    return 1\r\ntest \"calls\":\r\n    if one() != 1:\r\n        return\r\n"
	result := compiler.CompileSource("inspect.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	first := tooling.Inspect(result.Program)
	second := tooling.Inspect(result.Program)
	if first.BuildID != second.BuildID || len(first.Calls) != 1 {
		t.Fatal("unstable inspection")
	}
	call := first.Calls[0]
	if !strings.HasPrefix(source[call.Span.Start:], "one()") || call.Span.End > len(source) {
		t.Fatal(call.Span)
	}
	diagram := tooling.Diagram(first)
	if !strings.Contains(diagram, "flowchart TD") || !strings.Contains(diagram, "inspect.ms::one") {
		t.Fatal(diagram)
	}
}

func TestInspectInterface(t *testing.T) {
	source := "export interface Read[T]:\n    fn get() T\n"
	result := compiler.CompileSource("interface.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	inspection := tooling.Inspect(result.Program)
	if len(inspection.Entities) != 1 {
		t.Fatal(inspection.Entities)
	}
	entity := inspection.Entities[0]
	if entity.Kind != "interface" || entity.Name != "Read" || !entity.Exported || entity.Span.Start != 7 {
		t.Fatalf("incorrect interface entity: %+v", entity)
	}
}
