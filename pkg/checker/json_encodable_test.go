package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

const jsonHeader = "import {stringify, JsonEncodable, JsonValue} from \"@std/json.ms\"\nimport Map from \"@std/collections.ms\"\nimport Decimal from \"@std/decimal.ms\"\nimport Bytes from \"@std/bytes.ms\"\n"

func jsonDiagnostics(t *testing.T, source string) []syntax.Diagnostic {
	t.Helper()
	m, err := parser.Parse("json.ms", jsonHeader+source)
	if err != nil {
		t.Fatal(err)
	}
	return checker.Check([]*syntax.Module{m}, nil).Diagnostics
}

// stringify accepts a type by shape, with no JsonValue construction, and names
// the offending field path when a type has no JSON form.
func TestStringifyAcceptsEncodableShapes(t *testing.T) {
	cases := []struct{ name, source, want string }{
		{"scalars", "fn f() -> Unit:\n    stringify(value: 1)\n    stringify(value: 1.5)\n    stringify(value: \"s\")\n    stringify(value: true)\n", ""},
		{"json value", "fn f(v: JsonValue) -> Unit:\n    stringify(value: v)\n", ""},
		{"record with optional and collections", "type Request:\n    model: String\n    user: Optional[String]\n    tags: List[String]\n    limits: Map[String, Int]\n    ids: Set[Int]\nfn f(r: Request) -> Unit:\n    stringify(value: r)\n", ""},
		{"alternative", "type Shape:\n    case Circle(radius: Float)\n    case Dot\nfn f(s: Shape) -> Unit:\n    stringify(value: s)\n", ""},
		{"generic record", "type Box[T]:\n    value: T\nfn f(b: Box[Int]) -> Unit:\n    stringify(value: b)\n", ""},
		{"recursive type", "type Tree:\n    children: List[Tree]\nfn f(t: Tree) -> Unit:\n    stringify(value: t)\n", ""},
		{"decimal", "fn f(d: Decimal) -> Unit:\n    stringify(value: d)\n", ""},
		{"bounded generic wrapper", "fn dump[T: JsonEncodable](v: T) -> Unit:\n    stringify(value: v)\n", ""},
		{"function field", "type Request:\n    callback: fn() -> Int\nfn f(r: Request) -> Unit:\n    stringify(value: r)\n", "field callback of Request: functions cannot be encoded"},
		{"non-String map key", "fn f(m: Map[Int, String]) -> Unit:\n    stringify(value: m)\n", "map keys must be String"},
		{"nested optional", "type Request:\n    value: Optional[Optional[Int]]\nfn f(r: Request) -> Unit:\n    stringify(value: r)\n", "nested Optional is ambiguous"},
		{"bytes", "fn f(b: Bytes) -> Unit:\n    stringify(value: b)\n", "standard-library type with no JSON form"},
		{"result", "fn f(r: Result[Int, Error]) -> Unit:\n    stringify(value: r)\n", "standard-library type with no JSON form"},
		{"unit", "fn f() -> Unit:\n    stringify(value: unit)\n", "Unit has no JSON form"},
		{"interface", "interface Named:\n    fn name() -> String\ntype Holder:\n    named: Named\nfn f(h: Holder) -> Unit:\n    stringify(value: h)\n", "interface"},
		{"alternative payload", "type Job:\n    case Run(action: fn() -> Int)\nfn f(j: Job) -> Unit:\n    stringify(value: j)\n", "field action of Job.Run"},
		{"unbounded generic wrapper", "fn dump[T](v: T) -> Unit:\n    stringify(value: v)\n", "needs the bound T: JsonEncodable"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			diagnostics := jsonDiagnostics(t, c.source)
			if c.want == "" {
				if len(diagnostics) != 0 {
					t.Fatal(diagnostics)
				}
				return
			}
			for _, d := range diagnostics {
				if strings.Contains(d.Message, "does not satisfy JsonEncodable") && strings.Contains(d.Message, c.want) {
					return
				}
			}
			t.Fatalf("want %q, got %v", c.want, diagnostics)
		})
	}
}
