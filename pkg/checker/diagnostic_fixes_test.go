package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Each case pins the diagnostics for a reported checker defect: no panic,
// the fix named in the message, and no follow-up errors that restate it.
func TestDiagnosticFixes(t *testing.T) {
	for _, tt := range []struct {
		name, source string
		want         []string // substrings of the joined diagnostics
		absent       []string
		count        int // 0 means do not check
	}{
		{"bare Result impl receiver does not panic", "import Error from \"@std/errors.ms\"\nimpl Error for Result:\n    fn message() -> String:\n        return \"x\"\nfn general(value: Result) -> Error:\n    return value\n", []string{"Result requires 2 type arguments, found 0"}, nil, 0},
		{"short Result impl receiver does not panic through error()", "impl Error for Result[Int]:\n    fn message() -> String:\n        return \"x\"\nfn f(x: Result[Int]) -> Result[Int, Error]:\n    return error(x)\n", []string{"Result requires 2 type arguments, found 1"}, nil, 0},
		{"type parameter named Equal", "fn f[Equal](a: Equal) -> Unit:\n    return\n", []string{"duplicate or intrinsic type parameter Equal"}, nil, 1},
		{"type parameter named Hashable on a type", "type Box[Hashable]:\n    v: Hashable\n", []string{"duplicate or intrinsic type parameter Hashable"}, nil, 1},
		{"Float is not Hashable", "import Set from \"@std/collections.ms\"\nfn f() -> Int:\n    let s = Set[Float]()\n    return 0\n", []string{"Float has no Hashable implementation", "Decimal"}, []string{"add 'impl"}, 1},
		{"List is not Hashable", "import {Map, List} from \"@std/collections.ms\"\nfn f() -> Int:\n    let m = Map[List[Int], Int]()\n    return 0\n", []string{"collections have no Hashable implementation", "record key"}, []string{"add 'impl"}, 1},
		{"record still suggests impl", "import Set from \"@std/collections.ms\"\ntype K:\n    v: Float\nimpl Equal for K:\n    fn equals(other: Equal) -> Bool:\n        return true\nfn f() -> Int:\n    let s = Set[K]()\n    return 0\n", []string{"add 'impl Hashable for K:'"}, nil, 1},
		{"test try", "import Result from \"@std/result.ms\"\nfn g() -> Result[Int, String]:\n    return ok(1)\ntest \"x\":\n    let v = try g()\n", []string{"try is not available in a test", "panic(message: ...)"}, nil, 1},
		{"assign to function", "fn helper() -> Int:\n    return 1\nfn f() -> Int:\n    helper = 2\n    return 0\n", []string{"cannot assign to function helper"}, []string{"unknown binding"}, 1},
		{"assign to type", "type Point:\n    x: Int\nfn f() -> Int:\n    Point = 2\n    return 0\n", []string{"cannot assign to type Point"}, []string{"unknown binding"}, 1},
		{"assign to import", "import panic from \"@std/faults.ms\"\nfn f() -> Int:\n    panic = 2\n    return 0\n", []string{"cannot assign to imported function panic"}, []string{"unknown binding", "add: import"}, 1},
		{"Synchronized value", "import Synchronized from \"@std/sync.ms\"\nfn f(s: Synchronized[Int]) -> Int:\n    s.value = 5\n    return s.value\n", []string{"not readable or assignable", "operations: lock"}, []string{"available: lock, value", "record field"}, 2},
		{"identical diagnostics print once", "interface I:\n    fn n() -> Int\ntype Pair[A, B]:\n    a: A\n    b: B\nimpl I for Pair[A, A]:\n    fn n() -> Int:\n        return 1\nexport fn main() -> Int:\n    return I(value: Pair[Int, String](a: 1, b: \"x\")).n()\n", []string{"does not implement I"}, nil, 1},
		{"type named like a built-in has one error", "type Int:\n    x: Int\nfn f() -> Int:\n    let t = Int(x: 2)\n    return 0\n", []string{"duplicate or intrinsic name Int"}, []string{"no source constructor"}, 1},
		{"missing import is reported once", "fn f() -> Int:\n    let a = Set[Int]()\n    let b = Set[Int]()\n    let m = Queue[Int]()\n    let n = Queue[Int]()\n    return 0\n", []string{"import Set from", "import Queue from"}, []string{"cannot infer"}, 2},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("fix.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			var all []string
			for _, d := range p.Diagnostics {
				all = append(all, d.Message)
			}
			text := strings.Join(all, "\n")
			if strings.Contains(text, "internal") {
				t.Fatalf("checker failed: %s", text)
			}
			if tt.count != 0 && len(all) != tt.count {
				t.Fatalf("expected %d diagnostics, got %q", tt.count, all)
			}
			for _, want := range tt.want {
				if !strings.Contains(text, want) {
					t.Errorf("diagnostics %q lack %q", all, want)
				}
			}
			for _, bad := range tt.absent {
				if strings.Contains(text, bad) {
					t.Errorf("diagnostics %q contain %q", all, bad)
				}
			}
		})
	}
}

// A match used as a statement discards its result, so arms may end in values
// of different types; a match whose value is used still requires agreement.
func TestStatementMatchDiscardsArmValues(t *testing.T) {
	prefix := "import {List, Map} from \"@std/collections.ms\"\n"
	for _, tt := range []struct {
		name, source string
		count        int
	}{
		{"mixed arm values", prefix + "fn f(counts: Map[String, Int], names: List[String], found: Optional[Int]) -> Unit:\n    match found:\n        some(n):\n            counts.with_entry(key: \"a\", value: n)\n        none:\n            names.append(\"x\")\n", 0},
		{"value arm and assignment arm", prefix + "fn f(xs: List[Int], o: Optional[Int]) -> Unit:\n    var n = 0\n    match o:\n        some(v):\n            n = v\n            xs.with_value(index: 0, value: 5)\n        none:\n            n = 2\n    xs.append(n)\n", 0},
		{"used match still unifies", prefix + "fn f(xs: List[Int], o: Optional[Int]) -> Unit:\n    let r = match o:\n        some(v):\n            xs.with_value(index: 0, value: v)\n        none:\n            xs.length()\n", 1},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("match.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != tt.count {
				t.Fatalf("expected %d diagnostics, got %v", tt.count, p.Diagnostics)
			}
		})
	}
}
