package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/ir"
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

func (g *generator) primitiveEquality(x ir.Binary) ast.Expr {
	typ := primitiveEqualityType(x.LeftType)
	if !equalityIsPrimitive(x) {
		return nil
	}
	op := token.EQL
	if x.Op == "!=" {
		op = token.NEQ
	}
	// Operands that cannot be changed by the other operand compare directly.
	if isLiteral(x.Left) || isLiteral(x.Right) || g.effectFree(x.Left) && g.effectFree(x.Right) {
		return &ast.BinaryExpr{X: paren(g.irScalar(x.Left, typ)), Op: op, Y: paren(g.irScalar(x.Right, typ))}
	}
	// Capture once in source order. A Go binary expression can read an earlier
	// local after a later operand's call/match has mutated it. The explicit
	// statements also keep source returns and short-circuiting in their region.
	a, b := g.temp(), g.temp()
	extract := func(value ast.Expr) ast.Expr {
		return &ast.TypeAssertExpr{X: call(runtimeName("Value"), value), Type: ident(typ)}
	}
	return call(closure(nil, ident("bool"),
		define(a, extract(g.irValue(x.Left))),
		define(b, extract(g.irValue(x.Right))),
		returned(sourceAt(x.Pos, &ast.BinaryExpr{X: ident(a), Op: op, Y: ident(b)})),
	))
}

// equalityIsPrimitive reports whether both operands share one builtin primitive type.
func equalityIsPrimitive(x ir.Binary) bool {
	typ := primitiveEqualityType(x.LeftType)
	return typ != "" && x.LeftType.ID == x.RightType.ID && primitiveEqualityType(x.RightType) == typ
}

func isLiteral(x ir.Expr) bool {
	switch x := x.(type) {
	case ir.IntLiteral, ir.FloatLiteral, ir.DecimalLiteral, ir.BoolLiteral:
		return true
	case ir.Deferred:
		return x.Source.Kind == syntax.KindNumber || x.Source.Kind == syntax.KindBool
	}
	return false
}

// effectFree reports whether evaluating x runs no user code and assigns no
// variable, so it cannot change what a sibling operand reads.
func (g *generator) effectFree(x ir.Expr) bool {
	switch x := x.(type) {
	case ir.IntLiteral, ir.FloatLiteral, ir.DecimalLiteral, ir.BoolLiteral, ir.Local:
		return true
	case ir.Binary:
		return g.native(x) != "" && g.effectFree(x.Left) && g.effectFree(x.Right)
	case ir.Deferred:
		switch x.Source.Kind {
		case syntax.KindNumber, syntax.KindBool, syntax.KindName:
			return g.program.Info(x.Source).Method == nil
		}
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
