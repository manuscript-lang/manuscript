package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Diagnostics read "<cause>; <fix>": each case pins the cause and the
// concrete fix an agent can apply, and the number of diagnostics emitted.
func TestDiagnosticsStateCauseAndFix(t *testing.T) {
	for _, tt := range []struct {
		name, source string
		want         []string
		count        int
	}{
		{"misspelled name", "fn f(count: Int) -> Int:\n    return cuont\n", []string{"unknown binding cuont", "did you mean 'count'?"}, 1},
		{"unimported standard name", "fn f() -> Unit:\n    return panic(message: \"x\")\n", []string{"unknown binding panic", "import panic from \"@std/faults.ms\""}, 1},
		{"undeclared name", "fn f() -> Int:\n    return missing\n", []string{"unknown binding missing", "let missing = ..."}, 1},
		{"misspelled type", "fn f(x: Strin) -> Unit:\n    return\n", []string{"unknown type Strin", "did you mean 'String'?"}, 1},
		{"immutable assignment", "fn f() -> Int:\n    let x = 1\n    x = 2\n    return x\n", []string{"cannot assign immutable binding x", "var x = ..."}, 1},
		{"missing argument", "fn g(a: Int) -> Int:\n    return a\nfn f() -> Int:\n    return g()\n", []string{"missing argument a: Int in call to g", "add 'a: <Int>'"}, 1},
		{"unknown argument", "fn g(amount: Int) -> Int:\n    return amount\nfn f() -> Int:\n    return g(amunt: 1)\n", []string{"unknown argument amunt", "did you mean 'amount'?"}, 2},
		{"unknown member", "type P:\n    x: Int\nfn f(p: P) -> Int:\n    return p.y\n", []string{"unknown or ambiguous member y on P", "available: x"}, 1},
		{"non-exhaustive", "type S:\n    case A\n    case B\n    case C\nfn f(s: S) -> Int:\n    match s:\n        A:\n            return 1\n    return 0\n", []string{"non-exhaustive match", "missing cases: B, C"}, 1},
		{"operand mismatch is one error", "fn f() -> Int:\n    return \"a\" + 1\n", []string{"found String + Int", "toString()"}, 1},
		{"not a function", "fn f() -> Int:\n    let x = 1\n    return x()\n", []string{"x is not a function (it has type Int)"}, 1},
		{"list constructor", "import List from \"@std/collections.ms\"\nfn f() -> Int:\n    let xs: List[Int] = List[Int](1, 2)\n    return xs.length()\n", []string{"standard type has no source constructor: List[Int]", "let xs: List[Int] = []"}, 1},
		{"unknown export", "import nope from \"@std/faults.ms\"\nfn f() -> Unit:\n    return\n", []string{"module does not export nope", "@std/faults.ms exports:"}, 1},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("hints.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != tt.count {
				t.Fatalf("expected %d diagnostics, got %v", tt.count, p.Diagnostics)
			}
			message := p.Diagnostics[0].Message
			for _, want := range tt.want {
				if !strings.Contains(message, want) {
					t.Errorf("message %q lacks %q", message, want)
				}
			}
		})
	}
}

func TestMissingArgumentIsReportedAtTheCall(t *testing.T) {
	m, err := parser.Parse("call.ms", "fn g(a: Int) -> Int:\n    return a\nfn f() -> Int:\n    return g()\n")
	if err != nil {
		t.Fatal(err)
	}
	p := checker.Check([]*syntax.Module{m}, nil)
	if len(p.Diagnostics) != 1 || p.Diagnostics[0].Position.Line != 4 {
		t.Fatalf("expected one diagnostic on line 4, got %v", p.Diagnostics)
	}
}

// Rule codes classify the cause only, never the fix text after "; ".
func TestDiagnosticCodeIgnoresFix(t *testing.T) {
	d := syntax.Diagnostic{Phase: "resolution", Message: "unknown binding x; add: import x from \"@std/y.ms\""}
	if d.Code() != "MS2001" {
		t.Fatalf("code %s", d.Code())
	}
}
