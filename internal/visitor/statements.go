package visitor

import (
	"go/ast" // Aliased to avoid conflict with ANTLR's token
	"go/token"
	"manuscript-co/manuscript/internal/parser"
)

// TODO: Implement other Visit methods based on the action plan (Phase 2 onwards)
// e.g., VisitProgramItem, VisitStmt, VisitExprStmt, VisitLetDecl, VisitAssignmentExpr, etc.

// VisitStmt handles different kinds of statements.
func (v *ManuscriptAstVisitor) VisitStmt(ctx *parser.StmtContext) interface{} {
	if ctx == nil {
		return nil
	}

	// Check for break statement
	if ctx.GetSBreak() != nil {
		if !v.isInLoop() {
			v.addError("'break' statement found outside of a loop", ctx.GetSBreak().BREAK().GetSymbol())
		}
		return &ast.BranchStmt{
			TokPos: v.pos(ctx.GetSBreak().BREAK().GetSymbol()),
			Tok:    token.BREAK,
		}
	}

	// Check for continue statement
	if ctx.GetSContinue() != nil {
		if !v.isInLoop() {
			v.addError("'continue' statement found outside of a loop", ctx.GetSContinue().CONTINUE().GetSymbol())
		}
		return &ast.BranchStmt{
			TokPos: v.pos(ctx.GetSContinue().CONTINUE().GetSymbol()),
			Tok:    token.CONTINUE,
		}
	}

	if ctx.LetDecl() != nil {
		if concreteCtx, ok := ctx.LetDecl().(*parser.LetDeclContext); ok {
			return v.VisitLetDecl(concreteCtx)
		}
		v.addError("Internal error: Failed to process let declaration structure: "+ctx.LetDecl().GetText(), ctx.LetDecl().GetStart())
		return nil
	}

	// Handle expression statements directly using ctx.Expr()
	if exprCtx := ctx.Expr(); exprCtx != nil {
		visitedNodeRaw := v.Visit(exprCtx) // exprCtx is IExprContext

		if stmt, ok := visitedNodeRaw.(ast.Stmt); ok {
			return stmt // e.g. ast.AssignStmt from VisitAssignmentExpr
		}
		if expr, ok := visitedNodeRaw.(ast.Expr); ok {
			return &ast.ExprStmt{X: expr} // Wrap other expressions
		}
		v.addError("Expression in statement context did not resolve to a valid Go expression or statement: "+exprCtx.GetText(), exprCtx.GetStart())
		return &ast.BadStmt{}
	}

	if ifStmtCtx := ctx.IfStmt(); ifStmtCtx != nil {
		if concreteCtx, ok := ifStmtCtx.(*parser.IfStmtContext); ok {
			return v.VisitIfStmt(concreteCtx)
		}
		v.addError("Internal error: Failed to process if statement structure: "+ifStmtCtx.GetText(), ifStmtCtx.GetStart())
		return nil
	}

	if whileStmtCtx := ctx.WhileStmt(); whileStmtCtx != nil {
		if concreteCtx, ok := whileStmtCtx.(*parser.WhileStmtContext); ok {
			return v.VisitWhileStmt(concreteCtx)
		}
		v.addError("Internal error: Failed to process while statement structure: "+whileStmtCtx.GetText(), whileStmtCtx.GetStart())
		return nil
	}

	if forStmtCtx := ctx.ForStmt(); forStmtCtx != nil {
		if concreteCtx, ok := forStmtCtx.(*parser.ForStmtContext); ok {
			return v.VisitForStmt(concreteCtx)
		}
		v.addError("Internal error: Failed to process for statement structure: "+forStmtCtx.GetText(), forStmtCtx.GetStart())
		return nil
	}

	if returnStmtCtx := ctx.ReturnStmt(); returnStmtCtx != nil {
		if concreteCtx, ok := returnStmtCtx.(*parser.ReturnStmtContext); ok {
			return v.VisitReturnStmt(concreteCtx)
		}
		v.addError("Internal error: Failed to process return statement structure: "+returnStmtCtx.GetText(), returnStmtCtx.GetStart())
		return nil
	}

	if codeBlockCtx := ctx.CodeBlock(); codeBlockCtx != nil {
		if concreteCtx, ok := codeBlockCtx.(*parser.CodeBlockContext); ok {
			return v.VisitCodeBlock(concreteCtx)
		}
		v.addError("Internal error: Failed to process code block structure: "+codeBlockCtx.GetText(), codeBlockCtx.GetStart())
		return nil
	}

	if ctx.SEMICOLON() != nil {
		return &ast.EmptyStmt{Semicolon: getAntlrTokenPos(ctx.SEMICOLON().GetSymbol())}
	}

	v.addError("Unhandled statement type in VisitStmt: "+ctx.GetText(), ctx.GetStart())
	return nil
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
