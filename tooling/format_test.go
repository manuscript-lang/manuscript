package tooling_test

import (
	"github.com/manuscript-lang/manuscript/compiler"
	"github.com/manuscript-lang/manuscript/lexer"
	"github.com/manuscript-lang/manuscript/tooling"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFormatFixturesPreservesMeaningAndIsIdempotent(t *testing.T) {
	files, _ := filepath.Glob("../tests/e2e/testdata/accept/*.ms")
	for _, filename := range files {
		t.Run(filepath.Base(filename), func(t *testing.T) {
			input, err := os.ReadFile(filename)
			if err != nil {
				t.Fatal(err)
			}
			formatted, err := tooling.Format(filename, string(input))
			if err != nil {
				t.Fatal(err)
			}
			originalTokens, _ := lexer.Lex(filename, string(input))
			formattedTokens, _ := lexer.Lex(filename, formatted)
			if len(originalTokens) != len(formattedTokens) {
				t.Fatal("formatting changed tokens")
			}
			for i, token := range originalTokens {
				if token.Kind != formattedTokens[i].Kind || token.Text != formattedTokens[i].Text {
					t.Fatal("formatting changed token meaning")
				}
			}
			twice, err := tooling.Format(filename, formatted)
			if err != nil || formatted != twice {
				t.Fatal("formatter is not idempotent", err)
			}
			original := compiler.CompileSource("fixture.ms", string(input), compiler.Options{Tests: true})
			changed := compiler.CompileSource("fixture.ms", formatted, compiler.Options{Tests: true})
			if !original.Success() || !changed.Success() {
				t.Fatal(original.Diagnostics, changed.Diagnostics)
			}
		})
	}
}
func TestFormatCommentsAndErrors(t *testing.T) {
	input := "# leading\r\nfn sum( left:Int,right:Int )->Int: # sum\r\n    return left+right # trailing\r\n"
	want := "# leading\nfn sum(left: Int, right: Int) -> Int:  # sum\n    return left + right  # trailing\n"
	formatted, err := tooling.Format("sum.ms", input)
	if err != nil || formatted != want {
		t.Fatalf("got %q, err %v", formatted, err)
	}
	formatted, err = tooling.Format("bad.ms", "fn bad():\n  return\n")
	if err == nil || formatted != "" {
		t.Fatal("invalid syntax produced output")
	}
}
func TestInspectionDeterminismAndOriginalSpans(t *testing.T) {
	source := "fn one() -> Int:\r\n    return 1\r\ntest \"calls\":\r\n    if one() != 1:\r\n        return\r\n"
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
	source := "export interface Read[T]:\n    fn get() -> T\n"
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

func TestFormatGroupedImports(t *testing.T) {
	input := "import { List,Map, } from \"@std/collections.ms\" # collections\n"
	want := "import {List, Map,} from \"@std/collections.ms\"  # collections\n"
	formatted, err := tooling.Format("imports.ms", input)
	if err != nil || formatted != want {
		t.Fatalf("got %q, err %v", formatted, err)
	}
	twice, err := tooling.Format("imports.ms", formatted)
	if err != nil || twice != formatted {
		t.Fatal("formatting is not idempotent", err)
	}
}
