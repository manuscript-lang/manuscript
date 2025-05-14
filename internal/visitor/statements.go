package visitor

import (
	"go/ast"
	"log"
	"manuscript-co/manuscript/internal/parser"
)

// TODO: Implement other Visit methods based on the action plan (Phase 2 onwards)
// e.g., VisitProgramItem, VisitStmt, VisitExprStmt, VisitLetDecl, VisitAssignmentExpr, etc.

// VisitStmt handles different kinds of statements.
func (v *ManuscriptAstVisitor) VisitStmt(ctx *parser.StmtContext) interface{} {
	log.Printf("VisitStmt: Called for '%s'", ctx.GetText()) // Log entry

	if ctx.LetDecl() != nil {
		log.Printf("VisitStmt: Found LetDecl: %s", ctx.LetDecl().GetText())
		return v.VisitLetDecl(ctx.LetDecl().(*parser.LetDeclContext))
	}

	if exprStmtCtx := ctx.ExprStmt(); exprStmtCtx != nil {
		log.Printf("VisitStmt: Found ExprStmt: %s", exprStmtCtx.GetText())
		if concreteExprStmtCtx, ok := exprStmtCtx.(*parser.ExprStmtContext); ok {
			log.Printf("VisitStmt: Asserted ExprStmtContext, calling VisitExprStmt for '%s'", concreteExprStmtCtx.GetText())
			return v.VisitExprStmt(concreteExprStmtCtx)
		} else {
			log.Printf("VisitStmt: Failed to assert ExprStmtContext type for '%s'", exprStmtCtx.GetText())
			return nil
		}
	}

	if ctx.SEMICOLON() != nil {
		log.Printf("VisitStmt: Found SEMICOLON (empty statement): %s", ctx.GetText())
		return nil
	}

	log.Printf("VisitStmt: Unhandled statement type for '%s'", ctx.GetText())
	return nil // Return nil if unhandled
}

// VisitExprStmt processes an expression statement.
func (v *ManuscriptAstVisitor) VisitExprStmt(ctx *parser.ExprStmtContext) interface{} {
	// Explicitly visit only the expression part, ignore the semicolon child
	visitedExprRaw := v.Visit(ctx.Expr()) // Visit the core expression
	// Add detailed logging here:
	log.Printf("VisitExprStmt: Visited ctx.Expr() for '%s', got type %T, value: %+v", ctx.Expr().GetText(), visitedExprRaw, visitedExprRaw)

	if expr, ok := visitedExprRaw.(ast.Expr); ok {
		// Wrap the resulting expression in an ast.ExprStmt
		log.Printf("VisitExprStmt: Successfully asserted ast.Expr for '%s'", ctx.Expr().GetText()) // Log success
		return &ast.ExprStmt{X: expr}
	}

	// Log if the assertion failed
	log.Printf("VisitExprStmt: Failed to assert ast.Expr for '%s'. Got type %T instead.", ctx.Expr().GetText(), visitedExprRaw)
	return nil // Return nil if the expression visit failed
}

// VisitCodeBlock handles a block of statements.
// { stmt1; stmt2; ... }
func (v *ManuscriptAstVisitor) VisitCodeBlock(ctx *parser.CodeBlockContext) interface{} {
	log.Printf("VisitCodeBlock: Called for '%s'", ctx.GetText())
	var stmts []ast.Stmt
	for _, stmtCtx := range ctx.AllStmt() {
		visitedStmt := v.VisitStmt(stmtCtx.(*parser.StmtContext)) // VisitStmt should handle all statement types
		if astStmt, ok := visitedStmt.(ast.Stmt); ok {
			if astStmt != nil { // Ensure we don't append nil statements (e.g. from empty semicolons)
				stmts = append(stmts, astStmt)
			}
		} else if visitedStmt != nil { // If it's not nil, but not ast.Stmt, it's an unexpected type
			log.Printf("VisitCodeBlock: Expected ast.Stmt from VisitStmt, got %T for '%s'", visitedStmt, stmtCtx.GetText())
			// Decide on error handling: skip, return nil for block, or panic
			// For now, skipping the problematic statement
		}
	}
	return &ast.BlockStmt{
		List: stmts,
		// Lbrace and Rbrace positions can be set if needed, e.g., ctx.LBRACE().GetSymbol().GetStart()
	}
}
