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
func primitiveEqualityType(t *checker.Type) string { return ir.Primitive(t) }

func (g *generator) primitiveEquality(e *syntax.Expression) ast.Expr {
	operation := g.ir.Expression(e).Operation
	if operation == nil {
		return nil
	}
	op := token.EQL
	if operation.Identity == "!=" {
		op = token.NEQ
	}
	return g.orderedScalars(e, func(a, b ast.Expr) ast.Expr { return &ast.BinaryExpr{X: a, Op: op, Y: b} })
}
