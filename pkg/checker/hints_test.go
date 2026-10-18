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
		{"misspelled name", "fn f(count: Int) Int:\n    return cuont\n", []string{"unknown binding cuont", "did you mean 'count'?"}, 1},
		{"unimported standard name", "fn f() Unit:\n    return panic(message: \"x\")\n", []string{"unknown binding panic", "import panic from \"@std/faults.ms\""}, 1},
		{"undeclared name", "fn f() Int:\n    return missing\n", []string{"unknown binding missing", "let missing = ..."}, 1},
		{"misspelled type", "fn f(x: Strin) Unit:\n    return\n", []string{"unknown type Strin", "did you mean 'String'?"}, 1},
		{"immutable assignment", "fn f() Int:\n    let x = 1\n    x = 2\n    return x\n", []string{"cannot assign immutable binding x", "var x = ..."}, 1},
		{"missing argument", "fn g(a: Int) Int:\n    return a\nfn f() Int:\n    return g()\n", []string{"missing argument a: Int in call to g", "add 'a: <Int>'"}, 1},
		{"unknown argument", "fn g(amount: Int) Int:\n    return amount\nfn f() Int:\n    return g(amunt: 1)\n", []string{"unknown argument amunt", "did you mean 'amount'?"}, 2},
		{"member from two interfaces is ambiguous", "interface I:\n    fn m() Int\ninterface J:\n    fn m() Int\ntype A:\n    n: Int\nimpl I for A:\n    fn m() Int: return 1\nimpl J for A:\n    fn m() Int: return 2\nfn f(a: A) Int:\n    return a.m()\n", []string{"ambiguous member m on A", "provided by I, J", "I(value: ...).m()"}, 1},
		{"generic function value is one error", "fn id[T](x: T) T:\n    return x\nfn f() Int:\n    let g = id\n    return g(1)\n", []string{"generic function value requires explicit specialization"}, 1},
		{"uninferable generic call reports no missing argument", "fn g[T](x: T) Int:\n    return 0\nfn f() Int:\n    return g()\n", []string{"cannot infer type argument T"}, 1},
		{"declaration reuses prelude type", "type Optional:\n    x: Int\nfn f(o: Optional[Int]) Int:\n    return 0\n", []string{"declaration Optional reuses a prelude name", "rename it"}, 1},
		{"callback arity mismatch is one error", "fn start[T](operation: fn() T) Int:\n    return 0\nfn work(n: Int) Int:\n    return n\nfn f() Int:\n    return start(work)\n", []string{"callback mismatch", "takes 1 parameter but this position expects 0"}, 1},
		{"unknown member", "type P:\n    x: Int\nfn f(p: P) Int:\n    return p.y\n", []string{"unknown or ambiguous member y on P", "available: x"}, 1},
		{"set insert hint", "fn f(values: Set[Int]) Unit:\n    values.insert(1)\n", []string{"unknown or ambiguous member insert", "did you mean 'add'?"}, 1},
		{"list delete hint", "fn f(values: List[Int]) Unit:\n    values.delete(0)\n", []string{"unknown or ambiguous member delete", "did you mean 'remove'"}, 1},
		{"non-exhaustive", "type S:\n    case A\n    case B\n    case C\nfn f(s: S) Int:\n    match s:\n        A:\n            return 1\n    return 0\n", []string{"non-exhaustive match", "missing cases: B, C"}, 1},
		{"operand mismatch is one error", "fn f() Int:\n    return \"a\" + 1\n", []string{"found String + Int", "to_string()"}, 1},
		{"capitalized Optional arms", "fn f(o: Optional[Int]) Int:\n    match o:\n        Some(v):\n            return v\n        None:\n            return 0\n", []string{"unknown case Some of Optional", "did you mean 'some'?"}, 2},
		{"optional compared with plain value", "fn f(n: Optional[Int]) Int:\n    if n == 0:\n        return 1\n    return 0\n", []string{"found Optional[Int] == Int", "may be absent", "get(default)"}, 1},
		{"plain value added to optional", "fn f(n: Optional[Int]) Int:\n    return 1 + n\n", []string{"found Int + Optional[Int]", "may be absent"}, 1},
		{"result added to plain value", "fn p() Result[Int, Error]:\n    return ok(1)\nfn f() Int:\n    return p() + 1\n", []string{"found Result[Int, Error] + Int", "unwrap it with 'try'"}, 1},
		{"optional where plain value expected", "fn f(n: Optional[Int]) Int:\n    return n\n", []string{"expected Int, found Optional[Int]", "may be absent", "get(default)"}, 1},
		{"int where float expected", "fn f() Float:\n    let x: Float = 3\n    return x\n", []string{"expected Float, found Int", "write a Float literal such as 3.0", "to_float()"}, 1},
		{"float where int expected", "fn f() Int:\n    return 3.5\n", []string{"expected Int, found Float", "truncate_to_int()", "get(0)"}, 1},
		{"operation named without a call", "fn f() Int:\n    return [1, 2].length\n", []string{"expected Int, found fn() Int", "call it with parentheses"}, 1},
		{"print is not built in", "fn f() Unit:\n    println(\"hi\")\n", []string{"unknown binding println", "import stdout from \"@std/io.ms\""}, 1},
		{"null is not a value", "fn f() Int:\n    let s = null\n    return 0\n", []string{"unknown binding null", "absence is an Optional, written none"}, 1},
		{"not a function", "fn f() Int:\n    let x = 1\n    return x()\n", []string{"x is not a function (it has type Int)"}, 1},
		{"unknown export", "import nope from \"@std/faults.ms\"\nfn f() Unit:\n    return\n", []string{"module does not export nope", "@std/faults.ms exports:"}, 1},
		{"annotated binding survives bad initializer", "fn f() Int:\n    let x: Int = 3.5\n    let y = x + 1\n    return y\n", []string{"expected Int, found Float"}, 1},
		{"unimported type in a generic callback", "import Scheduler from \"@std/tasks.ms\"\nfn f() Int:\n    let s = Scheduler(reporter: fn(failure: SchedulerFailure) Unit: return unit)\n    return 0\n", []string{"unknown type SchedulerFailure", "import SchedulerFailure from \"@std/tasks.ms\""}, 1},
		{"qualified case of a generic alternative", "type Choice[T]:\n    case Found(value: T)\n    case Missing\nfn f(c: Choice[Int], o: Optional[Int]) Int:\n    match o:\n        Optional.some(n): return n\n        Optional.none: return 0\n    match c:\n        Choice.Found(v): return v\n        Choice.Missing: return 0\n", nil, 0},
		{"qualified case of another instantiation", "type Choice[T]:\n    case Found(value: T)\n    case Missing\nfn f(c: Choice[Int]) Int:\n    match c:\n        Choice[String].Found(v): return 1\n        Choice[String].Missing: return 0\n", []string{"pattern belongs to a different alternative"}, 2},
		{"unimported Set call", "fn f() Int:\n    let s = Set[String]()\n    return 0\n", nil, 0},
		{"unimported SetBuilder call", "fn f() Int:\n    let s = SetBuilder[String]()\n    return 0\n", []string{"unknown binding SetBuilder", "import SetBuilder from \"@std/collections.ms\""}, 1},
		{"positional generic call", "fn pick[T](items: List[T], keep: fn(value: T) Bool) Optional[T]:\n    return none\nfn f() Int:\n    let nums = [1, 2]\n    let hit = pick(nums, fn(value: Int) Bool: value > 1)\n    return hit.get(0)\n", nil, 0},
		{"String length is a declared member", "fn f() Int:\n    return \"abc\".length()\n", nil, 0},
		{"member synonym on String", "fn f() Int:\n    let n = \"abc\".len()\n    return 0\n", []string{"did you mean", "'length'", "'byte_length'", "'scalar_length'"}, 1},
		{"member list is complete", "fn f() Int:\n    let n = \"abc\".foo()\n    return 0\n", []string{"available: at,", "upper"}, 1},
		{"join on non-String list", "fn f() String:\n    return [1].join(separator: \",\")\n", []string{"only available on List[String]", "separator"}, 1},
		{"callback label mismatch is one error", "fn double(n: Int) Int:\n    return n * 2\nfn f() Int:\n    return [1, 2].map(double).length()\n", []string{"the function's parameter is named n", "expects value"}, 1},
		{"non-generic callback label mismatch", "fn positive(n: Int) Bool:\n    return n > 0\nfn f() Int:\n    return [1].filter(positive).length()\n", []string{"expected fn(value: Int) Bool", "expects value"}, 1},
		{"binding catch-all arm", "type S:\n    case A\n    case B\nfn f(s: S) Int:\n    match s:\n        A:\n            return 1\n        other:\n            return 2\n", []string{"'other' is not a case of S", "use '_'"}, 1},
		{"with on Result suggests unwrapping", "import Closeable from \"@std/cleanup.ms\"\ntype R:\n    n: Int\nimpl Closeable for R:\n    fn close() Unit:\n        return unit\nfn mk() Result[R, Error]:\n    return ok(R(n: 1))\nfn f() Int:\n    with x = mk():\n        return 1\n    return 0\n", []string{"with needs a Closeable value", "Result[R, Error]", "'try'", "'if let'"}, 1},
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
			if tt.count == 0 {
				return
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
	m, err := parser.Parse("call.ms", "fn g(a: Int) Int:\n    return a\nfn f() Int:\n    return g()\n")
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
		{"money", "export type MoneyError:\n    case Invalid\nexport fn parse_cents() Int: 0\nexport fn format_cents() String: \"0\"\n", "./money.ms exports: MoneyError, format_cents, parse_cents; namespace imports are unsupported"},
		{"missing", "fn hidden() Int: 0\n", "./money.ms exports nothing; namespace imports are unsupported"},
		{"hidden", "fn hidden() Int: 0\n", "not exported, so write 'export'"},
		{"parse_cent", "export fn parse_cents() Int: 0\n", "did you mean 'parse_cents'?"},
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
