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
		{"unknown export", "import nope from \"@std/faults.ms\"\nfn f() -> Unit:\n    return\n", []string{"module does not export nope", "@std/faults.ms exports:"}, 1},
		{"annotated binding survives bad initializer", "fn f() -> Int:\n    let x: Int = 3.5\n    let y = x + 1\n    return y\n", []string{"expected Int, found Float"}, 1},
		{"unimported Map call", "fn f() -> Int:\n    let m = Map[String, Int]()\n    return 0\n", []string{"unknown binding Map", "import Map from \"@std/collections.ms\""}, 1},
		{"unimported Set call", "fn f() -> Int:\n    let s = Set[String]()\n    return 0\n", []string{"unknown binding Set", "import Set from \"@std/collections.ms\""}, 1},
		{"unimported List annotation and literal", "fn f() -> Int:\n    var xs: List[Int] = []\n    return 0\n", []string{"unknown type List", "import List from \"@std/collections.ms\""}, 1},
		{"missing labels on generic call", "import List from \"@std/collections.ms\"\nfn pick[T](items: List[T], keep: fn(value: T) -> Bool) -> Optional[T]:\n    return none\nfn f() -> Int:\n    let nums = [1, 2]\n    let hit = pick(nums, fn(value: Int) -> Bool: value > 1)\n    return hit.unwrap_or(0)\n", []string{"write pick(items: nums, keep: fn(value: Int) -> Bool: value > 1)"}, 1},
		{"member synonym on String", "fn f() -> Int:\n    let n = \"abc\".length()\n    return 0\n", []string{"did you mean 'byte_length' or 'scalar_length'?"}, 1},
		{"member list is complete", "fn f() -> Int:\n    let n = \"abc\".foo()\n    return 0\n", []string{"available: at,", "upper"}, 1},
		{"join on non-String list", "import List from \"@std/collections.ms\"\nfn f() -> String:\n    return [1].join(separator: \",\")\n", []string{"only available on List[String]", "separator"}, 1},
		{"callback label mismatch is one error", "import List from \"@std/collections.ms\"\nfn double(n: Int) -> Int:\n    return n * 2\nfn f() -> Int:\n    return [1, 2].map(double).length()\n", []string{"the function's parameter is named n", "expects value"}, 1},
		{"non-generic callback label mismatch", "import List from \"@std/collections.ms\"\nfn positive(n: Int) -> Bool:\n    return n > 0\nfn f() -> Int:\n    return [1].filter(positive).length()\n", []string{"expected fn(value: Int)->Bool", "expects value"}, 1},
		{"binding catch-all arm", "type S:\n    case A\n    case B\nfn f(s: S) -> Int:\n    match s:\n        A:\n            return 1\n        other:\n            return 2\n", []string{"'other' is not a case of S", "use '_'"}, 1},
		{"with on Result suggests unwrapping", "import Closeable from \"@std/cleanup.ms\"\ntype R:\n    n: Int\nimpl Closeable for R:\n    fn close() -> Unit:\n        return unit\nfn mk() -> Result[R, String]:\n    return ok(R(n: 1))\nfn f() -> Int:\n    with x = mk():\n        return 1\n    return 0\n", []string{"with needs a Closeable value", "Result[R, String]", "'try'", "'match'"}, 1},
		{"statement match with value arm", "import List from \"@std/collections.ms\"\nfn f(xs: List[Int]) -> Int:\n    var seen = xs\n    match xs.first():\n        some(value):\n            seen.concat(xs)\n        none:\n            seen = []\n    return seen.length()\n", []string{"arm at line 6", "let ignored"}, 1},
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

func TestWrongImportListsOnlyDeclaredExports(t *testing.T) {
	for _, tc := range []struct{ name, declarations, want string }{
		{"money", "export type MoneyError:\n    case Invalid\nexport fn parse_cents() -> Int: 0\nexport fn format_cents() -> String: \"0\"\n", "./money.ms exports: MoneyError, format_cents, parse_cents; namespace imports are unsupported"},
		{"missing", "fn hidden() -> Int: 0\n", "./money.ms exports nothing; namespace imports are unsupported"},
		{"hidden", "fn hidden() -> Int: 0\n", "not exported, so write 'export'"},
		{"parse_cent", "export fn parse_cents() -> Int: 0\n", "did you mean 'parse_cents'?"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			money, err := parser.Parse("money.ms", "import panic from \"@std/faults.ms\"\n"+tc.declarations)
			if err != nil {
				t.Fatal(err)
			}
			source := "import " + tc.name + " from \"./money.ms\"\n"
			main, err := parser.Parse("main.ms", source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{money, main}, map[*syntax.Import]string{main.Imports[0]: money.File})
			if len(p.Diagnostics) != 1 {
				t.Fatal(p.Diagnostics)
			}
			d := p.Diagnostics[0]
			if !strings.Contains(d.Message, tc.want) || strings.Contains(d.Message, "Bool") || strings.Contains(d.Message, "panic") || d.Fix != nil || d.Code() != "MS2002" {
				t.Fatalf("incorrect exports/fix/code: %+v", d)
			}
			if d.End == nil || source[d.Position.Offset:d.End.Offset] != tc.name {
				t.Fatalf("incorrect import range: %+v", d)
			}
		})
	}
}
