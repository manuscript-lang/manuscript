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

	if deferStmtCtx := ctx.DeferStmt(); deferStmtCtx != nil {
		if concreteCtx, ok := deferStmtCtx.(*parser.DeferStmtContext); ok {
			return v.VisitDeferStmt(concreteCtx)
		}
		v.addError("Internal error: Failed to process defer statement structure: "+deferStmtCtx.GetText(), deferStmtCtx.GetStart())
		return nil
	}

	if codeBlockCtx := ctx.CodeBlock(); codeBlockCtx != nil {
		if concreteCtx, ok := codeBlockCtx.(*parser.CodeBlockContext); ok {
			return v.VisitCodeBlock(concreteCtx)
		}
		v.addError("Internal error: Failed to process code block structure: "+codeBlockCtx.GetText(), codeBlockCtx.GetStart())
		return nil
	}

	// Handle empty statement (just a separator)
	if ctx.GetChildCount() == 1 {
		token := ctx.GetStart()
		if token.GetTokenType() == parser.ManuscriptLexerNEWLINE || token.GetTokenType() == parser.ManuscriptLexerSEMICOLON {
			return &ast.EmptyStmt{}
		}
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
		visitedNode := v.VisitStmt(stmtCtx.(*parser.StmtContext)) // VisitStmt returns interface{}

		if visitedNode == nil {
			continue // Skip nil results (e.g. from empty statements or errors handled deeper)
		}

		if singleStmt, ok := visitedNode.(ast.Stmt); ok {
			if _, isEmpty := singleStmt.(*ast.EmptyStmt); !isEmpty {
				stmts = append(stmts, singleStmt)
			}
		} else if multiStmts, ok := visitedNode.([]ast.Stmt); ok {
			for _, stmt := range multiStmts {
				if stmt != nil {
					if _, isEmpty := stmt.(*ast.EmptyStmt); !isEmpty {
						stmts = append(stmts, stmt)
					}
				}
			}
		} else {
			v.addError("Internal error: Statement processing in code block returned unexpected type for: "+stmtCtx.GetText(), stmtCtx.GetStart())
		}
	}
	return &ast.BlockStmt{
		List: stmts,
		// Lbrace and Rbrace positions can be set if needed, e.g., ctx.LBRACE().GetSymbol().GetStart()
	}
}

// VisitReturnStmt handles return statements.
func (v *ManuscriptAstVisitor) VisitReturnStmt(ctx *parser.ReturnStmtContext) interface{} {
	retStmt := &ast.ReturnStmt{
		Return: v.pos(ctx.RETURN().GetSymbol()), // Position of the "return" keyword
	}

	if ctx.ExprList() != nil {
		// VisitExprList should return []ast.Expr or a single ast.Expr if it's just one
		// For now, let's assume VisitExprList correctly returns []ast.Expr
		// The grammar is exprList: expr (COMMA expr)* (COMMA)?;
		// So, v.Visit(ctx.ExprList()) might return that list.

		// Let's refine how to get []ast.Expr from ExprListContext
		// ExprListContext has AllExpr() []IExprContext
		exprListCtx := ctx.ExprList().(*parser.ExprListContext) // Cast to concrete type
		var results []ast.Expr
		for _, exprNode := range exprListCtx.AllExpr() {
			visitedExpr := v.Visit(exprNode)
			if astExpr, ok := visitedExpr.(ast.Expr); ok {
				results = append(results, astExpr)
			} else {
				v.addError("Return statement contains a non-expression.", exprNode.GetStart())
				// Add a bad expression to signify error but keep arity if possible
				results = append(results, &ast.BadExpr{From: v.pos(exprNode.GetStart()), To: v.pos(exprNode.GetStop())})
			}
		}
		retStmt.Results = results
	}

	return retStmt
}

// VisitDeferStmt handles defer statements.
func (v *ManuscriptAstVisitor) VisitDeferStmt(ctx *parser.DeferStmtContext) interface{} {
	if ctx == nil {
		return nil
	}

	// Get the expression to be deferred
	exprCtx := ctx.Expr()
	if exprCtx == nil {
		v.addError("Defer statement is missing an expression", ctx.DEFER().GetSymbol())
		return &ast.BadStmt{}
	}

	// Visit the expression to get its Go AST representation
	exprAst := v.Visit(exprCtx)
	if exprAst == nil {
		v.addError("Failed to process expression in defer statement", exprCtx.GetStart())
		return &ast.BadStmt{}
	}

	// Check if the visited expression is an ast.Expr
	expr, ok := exprAst.(ast.Expr)
	if !ok {
		v.addError("Expression in defer statement did not resolve to a valid Go expression", exprCtx.GetStart())
		return &ast.BadStmt{}
	}

	// For defer, we need a function call expression
	callExpr, isCall := expr.(*ast.CallExpr)
	if !isCall {
		// If it's not already a CallExpr, we need to convert it
		// For example, if it's just an identifier like 'cleanup',
		// we need to convert it to 'cleanup()'
		if ident, isIdent := expr.(*ast.Ident); isIdent {
			callExpr = &ast.CallExpr{
				Fun:  ident,
				Args: []ast.Expr{},
			}
		} else {
			v.addError("Defer statement requires a function call", exprCtx.GetStart())
			return &ast.BadStmt{}
		}
	}

	// Create and return the defer statement
	return &ast.DeferStmt{
		Defer: v.pos(ctx.DEFER().GetSymbol()),
		Call:  callExpr,
	}
}
