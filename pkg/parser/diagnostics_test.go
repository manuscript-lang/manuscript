package parser_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestUnsupportedCompoundAssignmentDiagnostics(t *testing.T) {
	for _, op := range []string{"+", "-", "*", "/", "%"} {
		for _, newline := range []string{"\n", "\r\n"} {
			source := strings.ReplaceAll("fn f() -> Int:\n    var total = 12\n    total "+op+"= 2 # keep comment\n    return total\n", "\n", newline)
			_, err := parser.Parse("compound.ms", source)
			d, ok := err.(syntax.Diagnostic)
			if !ok || !strings.Contains(d.Message, "compound assignment '"+op+"=' is unsupported; write 'total = total "+op+" 2'") {
				t.Fatalf("%s: %v", op, err)
			}
			at := strings.Index(source, op+"=")
			if d.Code() != "MS1000" || d.Position.Offset != at || d.Position.Line != 3 || d.Position.Column != 11 || d.End == nil || d.End.Offset != at+2 || d.End.Column != 13 {
				t.Fatalf("wrong span/code: %+v", d)
			}
			if d.Fix == nil || d.Fix.Position != d.Position || d.Fix.End != *d.End {
				t.Fatalf("missing exact fix: %+v", d)
			}
			fixed := source[:d.Fix.Position.Offset] + d.Fix.Replacement + source[d.Fix.End.Offset:]
			if _, err := parser.Parse("compound.ms", fixed); err != nil {
				t.Fatalf("invalid fix: %v\n%s", err, fixed)
			}
			if !strings.Contains(fixed, "total = total "+op+" 2 # keep comment") {
				t.Fatal(fixed)
			}
		}
	}
}

func TestCompoundAssignmentDoesNotGuessUnsafeFixes(t *testing.T) {
	for _, statement := range []string{"total *= 2 + 3", "total += get()", "record.total += 1", "get().total += 1", "(total) += 1", "total[0] += 1"} {
		_, err := parser.Parse("unsafe.ms", "fn f() -> Unit:\n    "+statement+"\n")
		d, ok := err.(syntax.Diagnostic)
		if !ok || !strings.Contains(d.Message, "compound assignment") || d.Fix != nil {
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

func TestPartialDiagnosticRebasesRangeAndFix(t *testing.T) {
	source := "fn before() -> Int: 1\r\nfn broken() -> Int:\r\n    var total = 1\r\n    total += 2\r\n    return total\r\nfn after() -> Int: 3\r\n"
	m, diagnostics := parser.ParsePartial("partial.ms", source)
	if len(m.Declarations) != 3 || len(diagnostics) != 1 {
		t.Fatalf("lost declarations or diagnostics: %+v, %v", m, diagnostics)
	}
	d := diagnostics[0]
	at := strings.Index(source, "+=")
	if d.Position.Offset != at || d.Position.Line != 4 || d.End == nil || d.End.Offset != at+2 || d.End.Line != 4 || d.Fix == nil || d.Fix.Position != d.Position || d.Fix.End != *d.End {
		t.Fatalf("unrebased range/fix: %+v", d)
	}
	fixed := source[:d.Fix.Position.Offset] + d.Fix.Replacement + source[d.Fix.End.Offset:]
	if _, err := parser.Parse("partial.ms", fixed); err != nil {
		t.Fatal(err)
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
