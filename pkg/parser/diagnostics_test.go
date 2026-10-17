package parser_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestCompoundAssignmentDesugarsToBinaryAssignment(t *testing.T) {
	for _, op := range []string{"+", "-", "*", "/", "%"} {
		for _, newline := range []string{"\n", "\r\n"} {
			source := strings.ReplaceAll("fn f(record: Box) -> Int:\n    var total = 12\n    total "+op+"= 2 # keep comment\n    record.count "+op+"= total - 1\n    return total\n", "\n", newline)
			module, err := parser.Parse("compound.ms", source)
			if err != nil {
				t.Fatalf("%s: %v", op, err)
			}
			body := module.Declarations[0].Body
			name, field := body[1], body[2]
			if name.Kind != syntax.KindAssign || name.Name != "total" || name.Compound != op || name.Value.Kind != syntax.KindBinary || name.Value.Text != op || name.Value.Left.Text != "total" {
				t.Fatalf("%s: wrong name assignment %+v", op, name)
			}
			if field.Kind != syntax.KindAssign || field.Target == nil || field.Compound != op || field.Value.Left == field.Target || field.Value.Left.Kind != syntax.KindMember || field.Value.Right.Text != "-" {
				t.Fatalf("%s: wrong field assignment %+v", op, field)
			}
		}
	}
}

func TestCompoundAssignmentRejectsReceiversThatWouldRunTwice(t *testing.T) {
	for _, statement := range []string{"get().total += 1", "total[0] += 1", "get(1).total *= 2"} {
		_, err := parser.Parse("unsafe.ms", "fn f() -> Unit:\n    "+statement+"\n")
		d, ok := err.(syntax.Diagnostic)
		if !ok || !strings.Contains(d.Message, "compound assignment") && !strings.Contains(d.Message, "assignment requires") {
			t.Fatalf("%s: %+v", statement, err)
		}
	}
	_, err := parser.Parse("spaced.ms", "fn f() -> Unit:\n    total + = 1\n")
	if err == nil || strings.Contains(err.Error(), "compound assignment") {
		t.Fatalf("separate tokens treated as compound assignment: %v", err)
	}
}

func TestUnsupportedPatternAndNamespaceDiagnostics(t *testing.T) {
	for _, tc := range []struct{ source, token, cause, hint string }{
		{"fn f(command: String) -> Int:\n    match command:\n        \"réport\": return 1\n    return 0\n", "\"réport\"", "string-literal match patterns are unsupported", "compare strings with 'if"},
		{"fn f(r: Result[Optional[Int], String]) -> Int:\n    match r:\n        ok(some(n)): return n\n    return 0\n", "(", "patterns cannot be nested", "separate match or helper function"},
		{"import * as money from \"./money.ms\"\n", "*", "namespace and wildcard imports are unsupported", "import individual exports"},
	} {
		source := strings.ReplaceAll(tc.source, "\n", "\r\n")
		_, err := parser.Parse("unsupported.ms", source)
		d, ok := err.(syntax.Diagnostic)
		if !ok || !strings.Contains(d.Message, tc.cause) || !strings.Contains(d.Message, tc.hint) || d.Fix != nil || d.End == nil {
			t.Fatalf("%+v", err)
		}
		if source[d.Position.Offset:d.End.Offset] != tc.token || d.End.Column-d.Position.Column != len(tc.token) || d.Code() != "MS1000" {
			t.Fatalf("incorrect range/code: %+v", d)
		}
	}
}

func TestPartialDiagnosticRebasesRange(t *testing.T) {
	source := "fn before() -> Int: 1\r\nfn broken(a: Bool, b: Bool) -> Int:\r\n    if a && b:\r\n        return 1\r\n    return 2\r\nfn after() -> Int: 3\r\n"
	m, diagnostics := parser.ParsePartial("partial.ms", source)
	if len(m.Declarations) != 3 || len(diagnostics) != 1 {
		t.Fatalf("lost declarations or diagnostics: %+v, %v", m, diagnostics)
	}
	d := diagnostics[0]
	at := strings.Index(source, "&&")
	if d.Position.Offset != at || d.Position.Line != 3 || d.End == nil || d.End.Line != 3 || d.End.Offset <= at {
		t.Fatalf("unrebased range: %+v", d)
	}
}

func TestInterpolationDiagnosticEndPosition(t *testing.T) {
	source := "fn f() -> String: \"é {1 + * 2}\"\n"
	_, err := parser.Parse("interpolation.ms", source)
	d, ok := err.(syntax.Diagnostic)
	if !ok || d.End == nil || source[d.Position.Offset:d.End.Offset] != "*" {
		t.Fatalf("%+v", err)
	}
}
