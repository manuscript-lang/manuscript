package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Source implementations cannot replace builtin primitive equality. Nominal
// data, contract views and type variables retain selected runtime dispatch.
func primitiveEqualityType(t *checker.Type) string {
	if t == nil || t.Kind != "primitive" || t.Def != nil || len(t.Args) != 0 {
		return ""
	}
	switch t.ID {
	case "Int":
		return "int64"
	case "Float":
		return "float64"
	case "Bool":
		return "bool"
	case "String":
		return "string"
	}
	return ""
}

func (g *generator) primitiveEquality(e *syntax.Expression) ast.Expr {
	left := g.program.Info(e.Left).Type
	right := g.program.Info(e.Right).Type
	typ := primitiveEqualityType(left)
	if typ == "" || left.ID != right.ID || primitiveEqualityType(right) != typ {
		return nil
	}
	// Capture once in source order. A Go binary expression can read an earlier
	// local after a later operand's call/match has mutated it. The explicit
	// statements also keep source returns and short-circuiting in their region.
	a, b := g.temp(), g.temp()
	extract := func(value ast.Expr) ast.Expr {
		return &ast.TypeAssertExpr{X: call(runtimeName("Value"), value), Type: ident(typ)}
	}
	op := token.EQL
	if e.Text == "!=" {
		op = token.NEQ
	}
	return call(closure(nil, ident("bool"),
		define(a, extract(g.expression(e.Left))),
		define(b, extract(g.expression(e.Right))),
		returned(sourceAt(e.Pos, &ast.BinaryExpr{X: ident(a), Op: op, Y: ident(b)})),
	))
}
