package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// VisitUnaryExpr is the main entry for unary expressions, dispatching to the correct sub-visitor.
func (v *ManuscriptAstVisitor) VisitUnaryExpr(ctx *parser.UnaryExprContext) interface{} {
	if ctx == nil {
		v.addError("VisitUnaryExpr called with nil context", nil)
		return &ast.BadExpr{}
	}
	// Handle operator cases
	if ctx.PLUS() != nil {
		operand := v.Visit(ctx.UnaryExpr())
		if expr, ok := operand.(ast.Expr); ok {
			return &ast.UnaryExpr{Op: token.ADD, X: expr}
		}
		v.addError("Operand for unary plus did not resolve to ast.Expr", ctx.GetStart())
		return &ast.BadExpr{}
	}
	if ctx.MINUS() != nil {
		operand := v.Visit(ctx.UnaryExpr())
		if expr, ok := operand.(ast.Expr); ok {
			return &ast.UnaryExpr{Op: token.SUB, X: expr}
		}
		v.addError("Operand for unary minus did not resolve to ast.Expr", ctx.GetStart())
		return &ast.BadExpr{}
	}
	if ctx.EXCLAMATION() != nil {
		operand := v.Visit(ctx.UnaryExpr())
		if expr, ok := operand.(ast.Expr); ok {
			return &ast.UnaryExpr{Op: token.NOT, X: expr}
		}
		v.addError("Operand for logical not did not resolve to ast.Expr", ctx.GetStart())
		return &ast.BadExpr{}
	}
	if ctx.TRY() != nil {
		// Custom handling for try, as before
		operand := v.Visit(ctx.UnaryExpr())
		if expr, ok := operand.(ast.Expr); ok {
			// Use the previous buildUnaryOpExpr logic for try
			return v.buildUnaryOpExpr(ctx.TRY().GetSymbol(), expr)
		}
		v.addError("Operand for try did not resolve to ast.Expr", ctx.GetStart())
		return &ast.BadExpr{}
	}
	if ctx.AwaitExpr() != nil {
		return v.Visit(ctx.AwaitExpr())
	}
	v.addError("Unknown or unsupported unary expression", ctx.GetStart())
	return &ast.BadExpr{}
}

// buildUnaryOpExpr is a helper to construct Go AST for unary operators
func (v *ManuscriptAstVisitor) buildUnaryOpExpr(opToken antlr.Token, operandExpr ast.Expr) ast.Expr {
	opPos := v.pos(opToken)
	switch opToken.GetTokenType() {
	case parser.ManuscriptTRY:
		recoverFuncBody := &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.IfStmt{
					Init: &ast.AssignStmt{
						Lhs: []ast.Expr{ast.NewIdent("r")},
						Tok: token.DEFINE,
						Rhs: []ast.Expr{&ast.CallExpr{Fun: ast.NewIdent("recover")}},
					},
					Cond: &ast.BinaryExpr{X: ast.NewIdent("r"), Op: token.NEQ, Y: ast.NewIdent("nil")},
					Body: &ast.BlockStmt{
						List: []ast.Stmt{
							&ast.AssignStmt{
								Lhs: []ast.Expr{ast.NewIdent("err")},
								Tok: token.ASSIGN,
								Rhs: []ast.Expr{&ast.CallExpr{
									Fun:  &ast.SelectorExpr{X: ast.NewIdent("fmt"), Sel: ast.NewIdent("Errorf")},
									Args: []ast.Expr{&ast.BasicLit{Kind: token.STRING, Value: `"panic: %v"`}, ast.NewIdent("r")},
								}},
							},
						},
					},
				},
			},
		}
		deferStmt := &ast.DeferStmt{
			Call: &ast.CallExpr{
				Fun: &ast.FuncLit{Type: &ast.FuncType{Params: &ast.FieldList{}}, Body: recoverFuncBody},
			},
		}
		assignValStmt := &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent("val")},
			Tok: token.ASSIGN,
			Rhs: []ast.Expr{operandExpr},
		}
		happyReturnStmt := &ast.ReturnStmt{
			Results: []ast.Expr{ast.NewIdent("val"), ast.NewIdent("nil")},
		}
		iifeBodyStmts := []ast.Stmt{
			deferStmt,
			assignValStmt,
			happyReturnStmt,
		}
		iifeFuncLit := &ast.FuncLit{
			Type: &ast.FuncType{
				Params: &ast.FieldList{},
				Results: &ast.FieldList{
					List: []*ast.Field{
						{Names: []*ast.Ident{ast.NewIdent("val")}, Type: ast.NewIdent("interface{}")},
						{Names: []*ast.Ident{ast.NewIdent("err")}, Type: ast.NewIdent("error")},
					},
				},
			},
			Body: &ast.BlockStmt{List: iifeBodyStmts, Lbrace: opPos},
		}
		return &ast.CallExpr{
			Fun:    iifeFuncLit,
			Lparen: opPos,
		}
	case parser.ManuscriptPLUS:
		return &ast.UnaryExpr{OpPos: opPos, Op: token.ADD, X: operandExpr}
	case parser.ManuscriptMINUS:
		return &ast.UnaryExpr{OpPos: opPos, Op: token.SUB, X: operandExpr}
	case parser.ManuscriptEXCLAMATION:
		return &ast.UnaryExpr{OpPos: opPos, Op: token.NOT, X: operandExpr}
	default:
		v.addError(fmt.Sprintf("Unsupported unary operator: %s", opToken.GetText()), opToken)
		return &ast.BadExpr{From: opPos, To: opPos + token.Pos(len(opToken.GetText()))}
	}
}
