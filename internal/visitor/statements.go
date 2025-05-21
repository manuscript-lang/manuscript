package visitor

import (
	"go/ast" // Aliased to avoid conflict with ANTLR's token
	"go/token"
	"manuscript-co/manuscript/internal/parser"
)

// VisitStmt handles all statement types using a type switch, following the ANTLR visitor pattern and keeping the code DRY.
func (v *ManuscriptAstVisitor) VisitStmt(ctx parser.IStmtContext) interface{} {
	if ctx == nil {
		return nil
	}
	switch c := ctx.(type) {
	case *parser.StmtLetContext:
		return v.VisitStmtLet(c)
	case *parser.StmtExprContext:
		return v.VisitStmtExpr(c)
	case *parser.StmtReturnContext:
		return v.VisitStmtReturn(c)
	case *parser.StmtYieldContext:
		return v.VisitStmtYield(c)
	case *parser.StmtIfContext:
		return v.VisitStmtIf(c)
	case *parser.StmtForContext:
		return v.VisitStmtFor(c)
	case *parser.StmtWhileContext:
		return v.VisitStmtWhile(c)
	case *parser.StmtBlockContext:
		return v.VisitStmtBlock(c)
	case *parser.StmtBreakContext:
		return v.VisitStmtBreak(c)
	case *parser.StmtContinueContext:
		return v.VisitStmtContinue(c)
	case *parser.StmtCheckContext:
		return v.VisitStmtCheck(c)
	case *parser.StmtDeferContext:
		return v.VisitStmtDefer(c)
	default:
		return nil
	}
}

// VisitStmtLet handles let statements using the ANTLR visitor pattern.
func (v *ManuscriptAstVisitor) VisitStmtLet(ctx *parser.StmtLetContext) interface{} {
	if ctx == nil || ctx.LetDecl() == nil {
		v.addError("let statement missing letDecl", ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	return v.Visit(ctx.LetDecl())
}

// VisitStmtExpr handles expression statements.
func (v *ManuscriptAstVisitor) VisitStmtExpr(ctx *parser.StmtExprContext) interface{} {
	exprCtx := ctx.Expr()
	if exprCtx == nil {
		v.addError("expression statement missing expr", ctx.GetStart())
		return &ast.BadStmt{}
	}
	visited := v.Visit(exprCtx)
	if stmt, ok := visited.(ast.Stmt); ok {
		return stmt
	}
	if expr, ok := visited.(ast.Expr); ok {
		return &ast.ExprStmt{X: expr}
	}
	v.addError("expression in statement context did not resolve to a valid Go expression or statement: "+exprCtx.GetText(), exprCtx.GetStart())
	return &ast.BadStmt{}
}

// VisitStmtReturn handles return statements.
func (v *ManuscriptAstVisitor) VisitStmtReturn(ctx *parser.StmtReturnContext) interface{} {
	if ctx == nil || ctx.ReturnStmt() == nil {
		v.addError("return statement missing returnStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.ReturnStmt())
}

// VisitStmtYield handles yield statements (not implemented).
func (v *ManuscriptAstVisitor) VisitStmtYield(ctx *parser.StmtYieldContext) interface{} {
	v.addError("'yield' statement not implemented", ctx.GetStart())
	return &ast.BadStmt{}
}

// VisitStmtIf handles if statements.
func (v *ManuscriptAstVisitor) VisitStmtIf(ctx *parser.StmtIfContext) interface{} {
	if ctx == nil || ctx.IfStmt() == nil {
		v.addError("if statement missing ifStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.IfStmt())
}

// VisitStmtFor handles for statements.
func (v *ManuscriptAstVisitor) VisitStmtFor(ctx *parser.StmtForContext) interface{} {
	if ctx == nil || ctx.ForStmt() == nil {
		v.addError("for statement missing forStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.ForStmt())
}

// VisitStmtWhile handles while statements.
func (v *ManuscriptAstVisitor) VisitStmtWhile(ctx *parser.StmtWhileContext) interface{} {
	if ctx == nil || ctx.WhileStmt() == nil {
		v.addError("while statement missing whileStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.WhileStmt())
}

// VisitStmtBlock handles code blocks as statements.
// { stmt1; stmt2; ... }
func (v *ManuscriptAstVisitor) VisitStmtBlock(ctx *parser.StmtBlockContext) interface{} {
	if ctx == nil || ctx.CodeBlock() == nil {
		v.addError("block statement missing codeBlock", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.CodeBlock())
}

// VisitStmtBreak handles break statements.
func (v *ManuscriptAstVisitor) VisitStmtBreak(ctx *parser.StmtBreakContext) interface{} {
	if !v.isInLoop() {
		v.addError("'break' statement found outside of a loop", ctx.GetStart())
	}
	return &ast.BranchStmt{
		TokPos: v.pos(ctx.GetStart()),
		Tok:    token.BREAK,
	}
}

// VisitStmtContinue handles continue statements.
func (v *ManuscriptAstVisitor) VisitStmtContinue(ctx *parser.StmtContinueContext) interface{} {
	if !v.isInLoop() {
		v.addError("'continue' statement found outside of a loop", ctx.GetStart())
	}
	return &ast.BranchStmt{
		TokPos: v.pos(ctx.GetStart()),
		Tok:    token.CONTINUE,
	}
}

// VisitStmtCheck handles check statements (not implemented).
func (v *ManuscriptAstVisitor) VisitStmtCheck(ctx *parser.StmtCheckContext) interface{} {
	v.addError("'check' statement not implemented", ctx.GetStart())
	return &ast.BadStmt{}
}

// VisitStmtDefer handles defer statements.
func (v *ManuscriptAstVisitor) VisitStmtDefer(ctx *parser.StmtDeferContext) interface{} {
	if ctx == nil || ctx.DeferStmt() == nil {
		v.addError("defer statement missing deferStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.DeferStmt())
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
	switch t := thenBlockRaw.(type) {
	case *ast.BlockStmt:
		thenBlock = t
	case []ast.Stmt:
		thenBlock = &ast.BlockStmt{List: t}
	case ast.Stmt:
		thenBlock = &ast.BlockStmt{List: []ast.Stmt{t}}
	default:
		v.addError("If body did not resolve to a valid block or statement: "+ctx.CodeBlock(0).GetText(), ctx.CodeBlock(0).GetStart())
		return nil
	}

	// Create the if statement
	ifStmt := &ast.IfStmt{
		Cond: condExpr,
		Body: thenBlock,
	}

	// Handle the else clause if it exists
	if ctx.ELSE() != nil {
		elseBlockRaw := v.Visit(ctx.CodeBlock(1))
		var elseBlock *ast.BlockStmt
		switch e := elseBlockRaw.(type) {
		case *ast.BlockStmt:
			elseBlock = e
		case []ast.Stmt:
			elseBlock = &ast.BlockStmt{List: e}
		case ast.Stmt:
			elseBlock = &ast.BlockStmt{List: []ast.Stmt{e}}
		default:
			v.addError("Else body did not resolve to a valid block or statement", ctx.GetStart())
		}
		ifStmt.Else = elseBlock
	}

	return ifStmt
}

// VisitCodeBlock handles a block of statements.
// { stmt1; stmt2; ... }
func (v *ManuscriptAstVisitor) VisitCodeBlock(ctx *parser.CodeBlockContext) interface{} {
	var stmts []ast.Stmt
	if stmtListItems := ctx.Stmt_list_items(); stmtListItems != nil {
		for _, stmtCtx := range stmtListItems.AllStmt() {
			if stmtCtx == nil {
				continue
			}
			visitedNode := v.Visit(stmtCtx)
			if visitedNode == nil {
				continue
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
			} else if block, ok := visitedNode.(*ast.BlockStmt); ok {
				for _, stmt := range block.List {
					if stmt != nil {
						if _, isEmpty := stmt.(*ast.EmptyStmt); !isEmpty {
							stmts = append(stmts, stmt)
						}
					}
				}
			} else if visitedNode != nil {
				v.addError("Internal error: Statement in code block did not resolve to ast.Stmt, []ast.Stmt, or *ast.BlockStmt", nil)
			}
		}
	}
	return &ast.BlockStmt{
		List: stmts,
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
