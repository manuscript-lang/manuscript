package ir_test

import (
	"math"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/frontend"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func resolve(t *testing.T, source string) (*checker.Program, *ir.Program) {
	t.Helper()
	graph := frontend.LoadSource("resolved.ms", source, frontend.Options{})
	if len(graph.Diagnostics) != 0 {
		t.Fatal(graph.Diagnostics)
	}
	checked := checker.CheckWithOptions(graph.Modules, graph.Imports, checker.CheckOptions{})
	if len(checked.Diagnostics) != 0 {
		t.Fatal(checked.Diagnostics)
	}
	return checked, ir.Elaborate(checked)
}

func TestResolvedCallEdgesAndTargets(t *testing.T) {
	checked, p := resolve(t, `import panic from "@std/faults.ms"
fn choose(first: Int, second: Int = 9) -> Int: first + second
fn identity[T](value: T) -> T: value
fn optional(value: Optional[Int]) -> Int: value.unwrap()
fn reordered() -> Int: choose(second: 4, first: panic("first"))
fn omitted() -> Int: choose(7)
fn wrapped() -> Int: optional(7)
fn generic() -> Int: identity(7)
fn indexed(values: List[Int]) -> Int: values.at(panic("index")).unwrap()
`)
	callable := p.Callables[checked.Symbol("resolved.ms", "choose").Decl]
	if len(callable.Bindings) != 2 || !callable.Parameters[1].Omittable || callable.Shared {
		t.Fatal("callable proof lost defaults or binding boundary")
	}
	seen := map[string]bool{}
	for e := range checked.Expressions() {
		x := p.Expression(e)
		if x.Call == nil {
			continue
		}
		call := x.Call
		switch {
		case call.Symbol != nil && call.Symbol.Name == "choose":
			if len(call.Arguments) == 2 {
				if call.Ordered || call.Arguments[0].Slot != 1 || call.Arguments[1].Slot != 0 || !call.Arguments[1].Value.Never || ir.Primitive(call.Arguments[1].Value.Expected) != "int64" {
					t.Fatalf("reordered call %#v", call)
				}
				seen["order"] = true
			} else {
				if !call.Ordered || !call.Parameters[0].Supplied || call.Parameters[1].Supplied || !call.Parameters[1].Omittable || call.Parameters[1].Default == nil {
					t.Fatalf("omission %#v", call)
				}
				seen["default"] = true
			}
		case call.Symbol != nil && call.Symbol.Name == "optional":
			edge := call.Arguments[0].Value
			if edge.Type.ID != "Int" || edge.Expected.ID != "@std/Optional" || edge.Optional == nil {
				t.Fatalf("optional edge %#v", edge)
			}
			seen["optional"] = true
		case call.Symbol != nil && call.Symbol.Name == "identity":
			if call.Native || call.Arguments[0].Value.Expected.ID != "Int" || len(call.TypeArgs) != 1 {
				t.Fatalf("generic boundary %#v", call)
			}
			seen["generic"] = true
		case call.Collection == "ListAt":
			if call.ListSuffix != "Int" || !call.Arguments[0].Value.Never || call.Arguments[0].Value.Expected.ID != "Int" {
				t.Fatalf("index edge %#v", call)
			}
			seen["index"] = true
		case call.Collection == "OptionalUnwrap":
			if call.UnwrapAt != nil {
				seen["unwrap"] = true
			}
		}
		if _, ok := p.Node(e).(ir.ResolvedCall); !ok {
			t.Fatal("call escaped typed IR")
		}
	}
	for _, name := range []string{"order", "default", "optional", "generic", "index", "unwrap"} {
		if !seen[name] {
			t.Fatal("missing", name)
		}
	}
}

func TestResolvedPrimitiveNeverAndBindingBoundaries(t *testing.T) {
	checked, p := resolve(t, `import panic from "@std/faults.ms"
fn logic() -> Bool: panic("left") and true
fn negation() -> Bool: not panic("operand")
fn conditional() -> Int:
    if panic("condition"): return 1
    return 0
fn value(items: List[Int]) -> Int:
    return match items.at(0):
        some(number): number
        none: panic("arm")
fn captured() -> fn() -> Int:
    let number = 1 + 2
    return fn() -> Int: number
`)
	seen := map[string]bool{}
	for e, info := range checked.Expressions() {
		x := p.Expression(e)
		if op := x.Operation; op != nil {
			if op.Identity == "and" {
				if !op.Left.Never || op.Left.Expected.ID != "Bool" {
					t.Fatal(op)
				}
				seen["and"] = true
			}
			if op.Identity == "not" {
				if !op.Right.Never || op.Right.Expected.ID != "Bool" {
					t.Fatal(op)
				}
				seen["not"] = true
			}
			if _, ok := p.Node(e).(ir.PrimitiveExpression); !ok {
				t.Fatal("primitive escaped IR")
			}
		}
		if e.Kind == syntax.KindMatch {
			for _, edge := range x.Arms {
				if edge.Never {
					if edge.Expected.ID != "Int" {
						t.Fatal(edge)
					}
					seen["arm"] = true
				}
			}
		}
		for _, b := range info.Captures {
			if p.ScalarLocals[b] != "" {
				t.Fatal("captured binding unboxed")
			}
			seen["capture"] = true
		}
		if info.Binding != nil && e.Kind == syntax.KindName {
			if p.Node(e).(ir.Reference).Site.Binding != info.Binding {
				t.Fatal("binding identity changed")
			}
		}
	}
	for _, name := range []string{"and", "not", "arm", "capture"} {
		if !seen[name] {
			t.Fatal("missing", name)
		}
	}
}

func TestIRListExpectationsAndUnaryConstants(t *testing.T) {
	checked, p := resolve(t, `fn minimum() -> List[Int]: [-9223372036854775808, +7]
fn zero() -> List[Float]: [-0.0, 0.0]
`)
	for e := range checked.Expressions() {
		if e.Kind != syntax.KindList {
			continue
		}
		list := p.Node(e).(ir.List)
		if len(list.Elements) != 2 {
			t.Fatal("missing List use edges")
		}
		for _, edge := range list.Elements {
			if !checker.Same(edge.Expected, list.Type.Args[0]) {
				t.Fatal("wrong expected element type")
			}
		}
		if list.Type.Args[0].ID == "Int" && list.Items[0].(ir.IntLiteral).Value != math.MinInt64 {
			t.Fatal("minimum changed")
		}
		if list.Type.Args[0].ID == "Float" && !math.Signbit(list.Items[0].(ir.FloatLiteral).Value) {
			t.Fatal("negative zero lost")
		}
	}
}

func TestResolvedRecordAndRangeFacts(t *testing.T) {
	checked, p := resolve(t, `type Box:
    value: Int
fn read(box: Box) -> Int: box.value
fn made(value: Int) -> Box: Box(value)
fn write(box: Box, value: Int) -> Unit:
    box.value = value
fn total(items: List[Int]) -> Int:
    var result = 0
    for item in items:
        result = result + item
    return result
`)
	if len(p.RecordOrder) != 1 || p.RecordOrder[0].Fields[0].Primitive != "int64" {
		t.Fatal("typed record layout lost")
	}
	recordAccess, construction := false, false
	for e := range checked.Expressions() {
		if p.Fields[e] != nil {
			if _, ok := p.Node(e).(ir.RecordAccess); !ok {
				t.Fatal("field escaped IR")
			}
			recordAccess = true
		}
		if x := p.Expression(e).Call; x != nil && x.Record != nil {
			construction = true
			if x.Arguments[0].Value.Expected.ID != "Int" {
				t.Fatal("constructor field expectation lost")
			}
		}
	}
	if !recordAccess || !construction || len(p.Ranges) != 1 {
		t.Fatal("missing record/range facts")
	}
	for _, r := range p.Ranges {
		if !r.List || r.ListSuffix != "Int" || r.Binding == nil || r.Value.Type.ID != "@std/List" {
			t.Fatal(r)
		}
	}
}
