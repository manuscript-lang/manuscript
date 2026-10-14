package ir_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/frontend"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func elaborate(t *testing.T, source string) (*checker.Program, *syntax.Expression) {
	t.Helper()
	graph := frontend.LoadSource("main.ms", source, frontend.Options{})
	if len(graph.Diagnostics) != 0 {
		t.Fatal(graph.Diagnostics)
	}
	program := checker.CheckWithOptions(graph.Modules, graph.Imports, checker.CheckOptions{})
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	for e := range program.Expressions() {
		if e.Pos.File == "main.ms" && e.Kind == syntax.KindList {
			return program, e
		}
	}
	t.Fatal("no expression of interest")
	return nil, nil
}

func TestLiteralsAreClassifiedByWrittenForm(t *testing.T) {
	for _, tc := range []struct {
		written string
		check   func(ir.Expr) bool
	}{
		{"1", func(x ir.Expr) bool { v, ok := x.(ir.IntLiteral); return ok && v.Value == 1 }},
		{"2.5", func(x ir.Expr) bool { v, ok := x.(ir.FloatLiteral); return ok && v.Value == 2.5 }},
		{"3d", func(x ir.Expr) bool { v, ok := x.(ir.DecimalLiteral); return ok && v.Text == "3d" }},
		{"true", func(x ir.Expr) bool { v, ok := x.(ir.BoolLiteral); return ok && v.Value }},
		{"\"a\"", func(x ir.Expr) bool { v, ok := x.(ir.Text); return ok && len(v.Parts) == 1 && v.Parts[0].Text == "a" }},
	} {
		t.Run(tc.written, func(t *testing.T) {
			program, e := elaborate(t, "import Decimal from \"@std/decimal.ms\"\nfn values() -> Bool: ["+tc.written+"].is_empty()\n")
			list := ir.NewElaborator(program).Value(e, program.Info(e)).(ir.List)
			if len(list.Items) != 1 || !tc.check(list.Items[0]) {
				t.Fatalf("got %#v", list.Items)
			}
		})
	}
}

func TestUnmigratedOperandsStayDeferred(t *testing.T) {
	program, e := elaborate(t, "fn values(xs: List[Int]) -> Bool: [xs[0]].is_empty()\n")
	list := ir.NewElaborator(program).Value(e, program.Info(e)).(ir.List)
	if _, ok := list.Items[0].(ir.Deferred); !ok {
		t.Fatalf("index = %#v", list.Items[0])
	}
}

func TestCallsCarryArgumentsAndCallee(t *testing.T) {
	program, e := elaborate(t, "fn id(n: Int) -> Int: n\nfn values() -> Bool: [id(1)].is_empty()\n")
	list := ir.NewElaborator(program).Value(e, program.Info(e)).(ir.List)
	call, ok := list.Items[0].(ir.Call)
	if !ok || len(call.Args) != 1 || call.Args[0].Name != "n" || call.Info.Symbol == nil {
		t.Fatalf("call = %#v", list.Items[0])
	}
	if v, ok := call.Args[0].Value.(ir.IntLiteral); !ok || v.Value != 1 {
		t.Fatalf("argument = %#v", call.Args[0].Value)
	}
}

// expression finds the first expression of the given kind written in main.ms.
func expression(t *testing.T, program *checker.Program, kind string) *syntax.Expression {
	t.Helper()
	for e := range program.Expressions() {
		if e.Pos.File == "main.ms" && e.Kind == kind {
			return e
		}
	}
	t.Fatal("no " + kind)
	return nil
}

func TestOperatorsAndLocalsAreElaborated(t *testing.T) {
	program, _ := elaborate(t, "fn f(a: Int, b: Int) -> Bool:\n    let c = a + b < 3\n    return [not c].is_empty()\n")
	el := ir.NewElaborator(program)
	var sum *syntax.Expression
	for e := range program.Expressions() {
		if e.Pos.File == "main.ms" && e.Kind == syntax.KindBinary && e.Text == "+" {
			sum = e
		}
	}
	if sum == nil {
		t.Fatal("no sum")
	}
	x, ok := el.Operand(sum).(ir.Binary)
	if !ok || x.Op != "+" {
		t.Fatalf("binary = %#v", el.Operand(sum))
	}
	if _, ok := x.Left.(ir.Local); !ok {
		t.Fatalf("operand = %#v", x.Left)
	}
	if x.LeftType.ID != "Int" || x.RightType.ID != "Int" {
		t.Fatalf("operand types = %v, %v", x.LeftType, x.RightType)
	}
	unary := expression(t, program, syntax.KindUnary)
	if u, ok := el.Operand(unary).(ir.Unary); !ok || u.Op != "not" {
		t.Fatalf("unary = %#v", el.Operand(unary))
	}
}

func TestMinimumIntegerLiteralAndConstantFold(t *testing.T) {
	program, _ := elaborate(t, "fn f() -> Bool: [-9223372036854775808, 1].is_empty() or not false\n")
	el := ir.NewElaborator(program)
	var sawMinimum, sawFold bool
	for e := range program.Expressions() {
		if e.Pos.File != "main.ms" {
			continue
		}
		switch x := el.Operand(e).(type) {
		case ir.IntLiteral:
			sawMinimum = sawMinimum || x.Value == -9223372036854775808
		case ir.BoolLiteral:
			sawFold = sawFold || x.Value
		}
	}
	if !sawMinimum || !sawFold {
		t.Fatalf("minimum literal %v, folded not false %v", sawMinimum, sawFold)
	}
}

func TestSymbolNamesStayDeferred(t *testing.T) {
	program, _ := elaborate(t, "fn id(n: Int) -> Int: n\nfn f() -> Bool: [id(1)].is_empty()\n")
	el := ir.NewElaborator(program)
	for e := range program.Expressions() {
		if e.Pos.File == "main.ms" && e.Kind == syntax.KindName && e.Text == "id" {
			if _, ok := el.Operand(e).(ir.Deferred); !ok {
				t.Fatalf("symbol name = %#v", el.Operand(e))
			}
			return
		}
	}
	t.Fatal("no symbol name")
}

func TestMemberReadsCarryTheirResolution(t *testing.T) {
	program, _ := elaborate(t, "type Point:\n    x: Int\nfn f(p: Point) -> Bool: [p.x].is_empty()\n")
	el := ir.NewElaborator(program)
	for e := range program.Expressions() {
		if e.Pos.File != "main.ms" || e.Kind != syntax.KindMember || e.Text != "x" {
			continue
		}
		m, ok := el.Operand(e).(ir.Member)
		if !ok || m.Name != "x" || m.ReceiverType == nil || m.ReceiverType.ID == "" || m.Info != program.Info(e) {
			t.Fatalf("member = %#v", el.Operand(e))
		}
		if _, ok := m.Receiver.(ir.Local); !ok {
			t.Fatalf("receiver = %#v", m.Receiver)
		}
		return
	}
	t.Fatal("no member read")
}
