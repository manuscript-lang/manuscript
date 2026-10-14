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
			list := ir.Value(program, e, program.Info(e)).(ir.List)
			if len(list.Items) != 1 || !tc.check(list.Items[0]) {
				t.Fatalf("got %#v", list.Items)
			}
		})
	}
}

func TestUnmigratedOperandsStayDeferred(t *testing.T) {
	program, e := elaborate(t, "fn id(n: Int) -> Int: n\nfn values() -> Bool: [id(1)].is_empty()\n")
	list := ir.Value(program, e, program.Info(e)).(ir.List)
	if _, ok := list.Items[0].(ir.Deferred); !ok {
		t.Fatalf("call = %#v", list.Items[0])
	}
}
