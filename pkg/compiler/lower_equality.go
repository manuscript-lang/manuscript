package compiler

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
	left := g.program.Expressions[e.Left].Type
	right := g.program.Expressions[e.Right].Type
	typ := primitiveEqualityType(left)
	if typ == "" || left.ID != right.ID || primitiveEqualityType(right) != typ {
		return nil
	}
	op := token.EQL
	if e.Text == "!=" {
		op = token.NEQ
	}
	// Operands that cannot be changed by the other operand compare directly.
	if isLiteral(e.Left) || isLiteral(e.Right) || g.effectFree(e.Left) && g.effectFree(e.Right) {
		return &ast.BinaryExpr{X: paren(g.scalar(e.Left, typ)), Op: op, Y: paren(g.scalar(e.Right, typ))}
	}
	// Capture once in source order. A Go binary expression can read an earlier
	// local after a later operand's call/match has mutated it. The explicit
	// statements also keep source returns and short-circuiting in their region.
	a, b := g.temp(), g.temp()
	extract := func(value ast.Expr) ast.Expr {
		return &ast.TypeAssertExpr{X: call(runtimeName("Value"), value), Type: ident(typ)}
	}
	return call(closure(nil, ident("bool"),
		define(a, extract(g.expression(e.Left))),
		define(b, extract(g.expression(e.Right))),
		returned(sourceAt(e.Pos, &ast.BinaryExpr{X: ident(a), Op: op, Y: ident(b)})),
	))
}

func isLiteral(e *syntax.Expression) bool {
	return e.Kind == syntax.KindNumber || e.Kind == syntax.KindBool
}

// effectFree reports whether evaluating e runs no user code and assigns no
// variable, so it cannot change what a sibling operand reads.
func (g *generator) effectFree(e *syntax.Expression) bool {
	switch e.Kind {
	case syntax.KindNumber, syntax.KindBool, syntax.KindName:
		return g.program.Expressions[e].Method == nil
	case syntax.KindBinary:
		info := g.program.Expressions[e]
		return info.ErrorSource == nil && g.nativeType(e) != "" && g.effectFree(e.Left) && g.effectFree(e.Right)
	}
	return false
}

// paren keeps a nested binary expression grouped as one operand.
func paren(e ast.Expr) ast.Expr {
	if _, ok := e.(*ast.BinaryExpr); ok {
		return &ast.ParenExpr{X: e}
	}
	return e
}
