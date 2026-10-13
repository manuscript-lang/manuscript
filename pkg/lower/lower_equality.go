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
	return g.orderedScalars(e, func(a, b ast.Expr) ast.Expr { return &ast.BinaryExpr{X: a, Op: op, Y: b} })
}
