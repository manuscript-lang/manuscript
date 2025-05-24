package visitor

import (
	"go/ast" // Aliased to avoid conflict with ANTLR's token
	"go/token"
	"manuscript-co/manuscript/internal/parser"
)

// VisitStmtLet handles let statements using the ANTLR visitor pattern.
func (v *ManuscriptAstVisitor) VisitLabelStmtLet(ctx *parser.LabelStmtLetContext) interface{} {
	if ctx == nil || ctx.LetDecl() == nil {
		v.addError("let statement missing letDecl", ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	return v.Visit(ctx.LetDecl())
}

// VisitStmtExpr handles expression statements.
func (v *ManuscriptAstVisitor) VisitLabelStmtExpr(ctx *parser.LabelStmtExprContext) interface{} {
	exprCtx := ctx.Expr()
	if exprCtx == nil {
		v.addError("expression statement missing expr", ctx.GetStart())
		return &ast.BadStmt{}
	}
	visited := v.Visit(exprCtx)

	if tryMarker, ok := visited.(*TryMarkerExpr); ok {
		actualSourceExpr := tryMarker.OriginalExpr
		underscoreIdent := ast.NewIdent("_") // For standalone try, assign value to _
		return v.buildTryLogic(underscoreIdent, actualSourceExpr)
	}

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
func (v *ManuscriptAstVisitor) VisitLabelStmtReturn(ctx *parser.LabelStmtReturnContext) interface{} {
	if ctx == nil || ctx.ReturnStmt() == nil {
		v.addError("return statement missing returnStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.ReturnStmt())
}

// VisitStmtYield handles yield statements (not implemented).
func (v *ManuscriptAstVisitor) VisitLabelStmtYield(ctx *parser.LabelStmtYieldContext) interface{} {
	v.addError("'yield' statement not implemented", ctx.GetStart())
	return &ast.BadStmt{}
}

// VisitStmtIf handles if statements.
func (v *ManuscriptAstVisitor) VisitLabelStmtIf(ctx *parser.LabelStmtIfContext) interface{} {
	if ctx == nil || ctx.IfStmt() == nil {
		v.addError("if statement missing ifStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.IfStmt())
}

// VisitStmtFor handles for statements.
func (v *ManuscriptAstVisitor) VisitLabelStmtFor(ctx *parser.LabelStmtForContext) interface{} {
	if ctx == nil || ctx.ForStmt() == nil {
		v.addError("for statement missing forStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.ForStmt())
}

// VisitStmtWhile handles while statements.
func (v *ManuscriptAstVisitor) VisitLabelStmtWhile(ctx *parser.LabelStmtWhileContext) interface{} {
	if ctx == nil || ctx.WhileStmt() == nil {
		v.addError("while statement missing whileStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.WhileStmt())
}

// VisitStmtBlock handles code blocks as statements.
func (v *ManuscriptAstVisitor) VisitLabelStmtBlock(ctx *parser.LabelStmtBlockContext) interface{} {
	if ctx == nil || ctx.CodeBlock() == nil {
		v.addError("block statement missing codeBlock", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.CodeBlock())
}

// VisitStmtBreak handles break statements.
func (v *ManuscriptAstVisitor) VisitLabelStmtBreak(ctx *parser.LabelStmtBreakContext) interface{} {
	if !v.isInLoop() {
		v.addError("'break' statement found outside of a loop", ctx.GetStart())
	}
	return &ast.BranchStmt{
		TokPos: v.pos(ctx.GetStart()),
		Tok:    token.BREAK,
	}
}

// VisitStmtContinue handles continue statements.
func (v *ManuscriptAstVisitor) VisitLabelStmtContinue(ctx *parser.LabelStmtContinueContext) interface{} {
	if !v.isInLoop() {
		v.addError("'continue' statement found outside of a loop", ctx.GetStart())
	}
	return &ast.BranchStmt{
		TokPos: v.pos(ctx.GetStart()),
		Tok:    token.CONTINUE,
	}
}

// VisitStmtCheck handles check statements (not implemented).
func (v *ManuscriptAstVisitor) VisitLabelStmtCheck(ctx *parser.LabelStmtCheckContext) interface{} {
	v.addError("'check' statement not implemented", ctx.GetStart())
	return &ast.BadStmt{}
}

// VisitStmtDefer handles defer statements.
func (v *ManuscriptAstVisitor) VisitLabelStmtDefer(ctx *parser.LabelStmtDeferContext) interface{} {
	if ctx == nil || ctx.DeferStmt() == nil {
		v.addError("defer statement missing deferStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.DeferStmt())
}

// VisitStmtTry handles try statements.
func (v *ManuscriptAstVisitor) VisitLabelStmtTry(ctx *parser.LabelStmtTryContext) interface{} {
	if ctx == nil || ctx.TryExpr() == nil {
		v.addError("try statement missing tryExpr", ctx.GetStart())
		return &ast.BadStmt{}
	}

	visited := v.Visit(ctx.TryExpr())

	// Handle regular try expressions
	if tryMarker, ok := visited.(*TryMarkerExpr); ok {
		return v.buildTryLogic(ast.NewIdent("_"), tryMarker.OriginalExpr)
	}

	v.addError("try statement did not resolve to a valid try marker", ctx.TryExpr().GetStart())
	return &ast.BadStmt{}
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
		} else {
			v.addError("Internal error: Statement processing in code block returned unexpected type for: "+stmtCtx.GetText(), stmtCtx.GetStart())
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
		visited := v.Visit(ctx.ExprList())
		if exprs, ok := visited.([]ast.Expr); ok {
			retStmt.Results = exprs
		} else {
			v.addError("Return statement's exprList did not resolve to valid Go expressions", ctx.ExprList().GetStart())
		}
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

// VisitStmtPiped handles piped statements.
func (v *ManuscriptAstVisitor) VisitLabelStmtPiped(ctx *parser.LabelStmtPipedContext) interface{} {
	if ctx == nil || ctx.PipedStmt() == nil {
		v.addError("piped statement missing pipedStmt", ctx.GetStart())
		return &ast.BadStmt{}
	}
	return v.Visit(ctx.PipedStmt())
}

// VisitPipedStmt handles the main piped statement structure
func (v *ManuscriptAstVisitor) VisitPipedStmt(ctx *parser.PipedStmtContext) interface{} {
	if ctx == nil {
		v.addError("piped statement context is nil", nil)
		return &ast.BadStmt{}
	}

	// Get all postfixExpr contexts (source + targets)
	allPostfixExprs := ctx.AllPostfixExpr()
	if len(allPostfixExprs) < 2 {
		v.addError("piped statement needs at least source and one target", ctx.GetStart())
		return &ast.BadStmt{}
	}

	// First postfixExpr is the source
	sourceExpr := v.Visit(allPostfixExprs[0])
	if sourceExpr == nil {
		v.addError("source expression in piped statement is nil", allPostfixExprs[0].GetStart())
		return &ast.BadStmt{}
	}

	sourceExprAst, ok := sourceExpr.(ast.Expr)
	if !ok {
		v.addError("source expression did not resolve to valid Go expression", allPostfixExprs[0].GetStart())
		return &ast.BadStmt{}
	}

	// Rest are pipeline targets
	var pipedCalls []PipedCall
	for i := 1; i < len(allPostfixExprs); i++ {
		targetExpr := v.Visit(allPostfixExprs[i])
		if targetExpr == nil {
			v.addError("pipeline target expression is nil", allPostfixExprs[i].GetStart())
			continue
		}

		targetExprAst, ok := targetExpr.(ast.Expr)
		if !ok {
			v.addError("pipeline target did not resolve to valid Go expression", allPostfixExprs[i].GetStart())
			continue
		}

		pipedCall := PipedCall{
			TargetExpr: targetExprAst,
			Args:       []PipedArg{},
		}

		// Check if this target has arguments (i-1 because we're offset by 1 from allPostfixExprs)
		argIndex := i - 1
		if argIndex < len(ctx.AllPipedArgs()) && ctx.AllPipedArgs()[argIndex] != nil {
			visited := v.Visit(ctx.AllPipedArgs()[argIndex])
			if pipedArgs, ok := visited.([]PipedArg); ok {
				pipedCall.Args = pipedArgs
			} else {
				v.addError("piped args did not resolve to valid structure", ctx.AllPipedArgs()[argIndex].GetStart())
			}
		}

		pipedCalls = append(pipedCalls, pipedCall)
	}

	return v.buildPipedStatement(sourceExprAst, pipedCalls)
}

// VisitPipedArgs handles the arguments for a piped call
func (v *ManuscriptAstVisitor) VisitPipedArgs(ctx *parser.PipedArgsContext) interface{} {
	if ctx == nil {
		return []PipedArg{}
	}

	var args []PipedArg
	for _, pipedArgCtx := range ctx.AllPipedArg() {
		if pipedArgCtx == nil {
			continue
		}
		visited := v.Visit(pipedArgCtx)
		if pipedArg, ok := visited.(PipedArg); ok {
			args = append(args, pipedArg)
		} else {
			v.addError("piped arg did not resolve to valid structure", pipedArgCtx.GetStart())
		}
	}
	return args
}

// VisitPipedArg handles individual arguments in a piped call
func (v *ManuscriptAstVisitor) VisitPipedArg(ctx *parser.PipedArgContext) interface{} {
	if ctx == nil || ctx.ID() == nil || ctx.Expr() == nil {
		v.addError("piped arg missing name or value", ctx.GetStart())
		return PipedArg{}
	}

	argName := ctx.ID().GetText()
	argValue := v.Visit(ctx.Expr())

	if argValueExpr, ok := argValue.(ast.Expr); ok {
		return PipedArg{
			Name:  argName,
			Value: argValueExpr,
		}
	}

	v.addError("piped arg value did not resolve to valid Go expression", ctx.Expr().GetStart())
	return PipedArg{}
}
