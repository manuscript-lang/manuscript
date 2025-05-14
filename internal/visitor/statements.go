package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// TODO: Implement other Visit methods based on the action plan (Phase 2 onwards)
// e.g., VisitProgramItem, VisitStmt, VisitExprStmt, VisitLetDecl, VisitAssignmentExpr, etc.

// VisitStmt handles different kinds of statements.
func (v *ManuscriptAstVisitor) VisitStmt(ctx *parser.StmtContext) interface{} {

	if ctx.LetDecl() != nil {
		return v.VisitLetDecl(ctx.LetDecl().(*parser.LetDeclContext))
	}

	if exprStmtCtx := ctx.ExprStmt(); exprStmtCtx != nil {
		if concreteExprStmtCtx, ok := exprStmtCtx.(*parser.ExprStmtContext); ok {
			return v.VisitExprStmt(concreteExprStmtCtx)
		} else {
			v.addError("Internal error: Failed to process expression statement structure: "+exprStmtCtx.GetText(), exprStmtCtx.GetStart())
			return nil
		}
	}

	if ctx.SEMICOLON() != nil {
		return &ast.EmptyStmt{}
	}

	v.addError("Unhandled statement type: "+ctx.GetText(), ctx.GetStart())
	return nil
}

// VisitExprStmt processes an expression statement.
func (v *ManuscriptAstVisitor) VisitExprStmt(ctx *parser.ExprStmtContext) interface{} {
	// Explicitly visit only the expression part, ignore the semicolon child
	visitedExprRaw := v.Visit(ctx.Expr()) // Visit the core expression

	if expr, ok := visitedExprRaw.(ast.Expr); ok {
		// Wrap the resulting expression in an ast.ExprStmt
		return &ast.ExprStmt{X: expr}
	}

	v.addError("Expression statement did not resolve to a valid expression: "+ctx.Expr().GetText(), ctx.Expr().GetStart())
	return nil // Return nil if the expression visit failed
}

// VisitCodeBlock handles a block of statements.
// { stmt1; stmt2; ... }
func (v *ManuscriptAstVisitor) VisitCodeBlock(ctx *parser.CodeBlockContext) interface{} {
	var stmts []ast.Stmt
	for _, stmtCtx := range ctx.AllStmt() {
		visitedStmt := v.VisitStmt(stmtCtx.(*parser.StmtContext)) // VisitStmt should handle all statement types
		if astStmt, ok := visitedStmt.(ast.Stmt); ok {
			if astStmt != nil { // Ensure we don't append nil statements (e.g. from empty semicolons)
				stmts = append(stmts, astStmt)
			}
		} else if visitedStmt != nil { // If it's not nil, but not ast.Stmt, it's an unexpected type
			v.addError("Internal error: Statement processing in code block returned unexpected type for: "+stmtCtx.GetText(), stmtCtx.GetStart())
		}
	}
	return &ast.BlockStmt{
		List: stmts,
		// Lbrace and Rbrace positions can be set if needed, e.g., ctx.LBRACE().GetSymbol().GetStart()
	}
}
