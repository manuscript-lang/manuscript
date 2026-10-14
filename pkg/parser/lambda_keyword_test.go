package parser_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestBlockLambdaCommaDiagnostic(t *testing.T) {
	for _, newline := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("fn before() -> Int: 0\nfn broken() -> Int:\n    return apply(\n        op: fn(value: Int) -> Int:\n            return value + 1,\n        times: 3\n    )\nfn after() -> Int: 2\n", "\n", newline)
		_, err := parser.Parse("comma.ms", source)
		d, ok := err.(syntax.Diagnostic)
		if !ok || !strings.Contains(d.Message, "comma on its own line dedented to the fn header") || d.Position.Offset != strings.Index(source, ",") || d.Position.Line != 5 {
			t.Fatalf("wrong comma diagnostic: %v", err)
		}
		module, diagnostics := parser.ParsePartial("comma.ms", source)
		if len(diagnostics) != 1 || diagnostics[0].Message != d.Message || diagnostics[0].Position != d.Position || len(module.Declarations) != 2 || module.Declarations[1].Name != "after" {
			t.Fatalf("recovery lost neighbors or diagnostic: %+v, %v", module, diagnostics)
		}
		fixed := strings.Replace(source, "value + 1,", "value + 1"+newline+"        ,", 1)
		if _, err := parser.Parse("comma.ms", fixed); err != nil {
			t.Fatal(err)
		}
		if _, diagnostics := parser.ParsePartial("comma.ms", fixed); len(diagnostics) != 0 {
			t.Fatal(diagnostics)
		}
	}
	// An ordinary function must retain the general statement diagnostic.
	_, err := parser.Parse("ordinary.ms", "fn f() -> Int:\n    return 1,\n")
	if err == nil || strings.Contains(err.Error(), "dedented") {
		t.Fatal(err)
	}
}

func TestUnitBindingKeywordDiagnostic(t *testing.T) {
	for _, binding := range []string{"let unit", "var unit", "let [unit]", "let {value: unit}"} {
		source := "fn before() -> Unit: unit\nfn broken() -> Unit:\n    " + binding + " = read_hex4()\nfn after() -> Unit: unit\n"
		_, err := parser.Parse("unit.ms", source)
		d, ok := err.(syntax.Diagnostic)
		if !ok || !strings.Contains(d.Message, "unit is a reserved value keyword") || !strings.Contains(d.Message, "choose another name") || d.Position.Line != 3 {
			t.Fatalf("%s: %v", binding, err)
		}
		module, diagnostics := parser.ParsePartial("unit.ms", source)
		if len(module.Declarations) != 3 || len(diagnostics) != 1 || diagnostics[0].Position != d.Position || diagnostics[0].Message != d.Message {
			t.Fatalf("%+v: %v", module, diagnostics)
		}
	}
	if _, err := parser.Parse("unit.ms", "fn f() -> Unit:\n    let code_unit = unit\n    return code_unit\n"); err != nil {
		t.Fatal(err)
	}
}
