package visitor

import (
	"go/ast"
	"go/token"

	"github.com/antlr4-go/antlr/v4"
)

// getAntlrTokenPos converts an ANTLR token's start position to a go/token.Pos.
// This is a simplification and might need refinement if precise FileSet mapping is required.
func getAntlrTokenPos(tk antlr.Token) token.Pos {
	if tk == nil {
		return token.NoPos
	}
	return token.Pos(tk.GetStart())
}

func (v *ManuscriptAstVisitor) asStmt(val interface{}) ast.Stmt {
	if stmt, ok := val.(ast.Stmt); ok {
		return stmt
	}
	return nil
}

func (v *ManuscriptAstVisitor) asExpr(val interface{}) ast.Expr {
	if expr, ok := val.(ast.Expr); ok {
		return expr
	}
	return nil
}

func (v *ManuscriptAstVisitor) asStmtOrExprStmt(val interface{}) ast.Stmt {
	if stmt, ok := val.(ast.Stmt); ok {
		return stmt
	}
	if expr, ok := val.(ast.Expr); ok && expr != nil {
		return &ast.ExprStmt{X: expr}
	}
	return nil
}

func toSpecSlice(specs []*ast.ImportSpec) []ast.Spec {
	out := make([]ast.Spec, len(specs))
	for i, s := range specs {
		out[i] = s
	}
	return out
}
