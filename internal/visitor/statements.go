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

	if ifStmtCtx := ctx.IfStmt(); ifStmtCtx != nil {
		if concreteIfStmtCtx, ok := ifStmtCtx.(*parser.IfStmtContext); ok {
			return v.VisitIfStmt(concreteIfStmtCtx)
		} else {
			v.addError("Internal error: Failed to process if statement structure: "+ifStmtCtx.GetText(), ifStmtCtx.GetStart())
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

// VisitIfStmt processes an if statement, including any else or else-if branches.
func (v *ManuscriptAstVisitor) VisitIfStmt(ctx *parser.IfStmtContext) interface{} {
	// Visit the condition expression
	condExprRaw := v.Visit(ctx.Expr())
	var condExpr ast.Expr
	if expr, ok := condExprRaw.(ast.Expr); ok {
		condExpr = expr
	} else {
		v.addError("If condition did not resolve to a valid expression: "+ctx.Expr().GetText(), ctx.Expr().GetStart())
		return nil
	}

	// Visit the "then" block
	thenBlockRaw := v.Visit(ctx.CodeBlock(0))
	var thenBlock *ast.BlockStmt
	if block, ok := thenBlockRaw.(*ast.BlockStmt); ok {
		thenBlock = block
	} else {
		v.addError("If body did not resolve to a valid block: "+ctx.CodeBlock(0).GetText(), ctx.CodeBlock(0).GetStart())
		return nil
	}

	// Create the if statement
	ifStmt := &ast.IfStmt{
		Cond: condExpr,
		Body: thenBlock,
	}

	// Handle the else clause if it exists
	if ctx.ELSE() != nil {
		// Get the else block (second code block)
		elseBlockRaw := v.Visit(ctx.CodeBlock(1))
		if elseBlock, ok := elseBlockRaw.(*ast.BlockStmt); ok {
			// Check if this is an "else if" statement (a block with exactly one if statement)
			if len(elseBlock.List) == 1 {
				if elseIf, ok := elseBlock.List[0].(*ast.IfStmt); ok {
					// This is an "else if" - connect it directly as the Else branch
					ifStmt.Else = elseIf
					return ifStmt
				}
			}
			// Regular else block
			ifStmt.Else = elseBlock
		} else {
			v.addError("Else body did not resolve to a valid block", ctx.GetStart())
		}
	}

	return ifStmt
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
