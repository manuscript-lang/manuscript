package msparse

import (
	"fmt"
	"manuscript-co/manuscript/internal/ast"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// Statement visitors

// Stmt visitor - was missing
func (v *ParseTreeToAST) VisitStmt(ctx *parser.StmtContext) interface{} {
	// The Stmt context is a base type that gets specialized into specific labeled contexts
	// We need to handle it by checking the children and delegating
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
		}
	}
	return nil
}

func (v *ParseTreeToAST) VisitLabelStmtLet(ctx *parser.LabelStmtLetContext) interface{} {
	if ctx.LetDecl() != nil {
		return ctx.LetDecl().Accept(v)
	}
	return nil
}

func (v *ParseTreeToAST) VisitLabelStmtExpr(ctx *parser.LabelStmtExprContext) interface{} {
	exprStmt := &ast.ExprStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			exprStmt.Expr = expr.(ast.Expression)
		}
	}

	return exprStmt
}

func (v *ParseTreeToAST) VisitLabelStmtReturn(ctx *parser.LabelStmtReturnContext) interface{} {
	return ctx.ReturnStmt().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelStmtYield(ctx *parser.LabelStmtYieldContext) interface{} {
	return ctx.YieldStmt().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelStmtIf(ctx *parser.LabelStmtIfContext) interface{} {
	return ctx.IfStmt().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelStmtFor(ctx *parser.LabelStmtForContext) interface{} {
	return ctx.ForStmt().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelStmtWhile(ctx *parser.LabelStmtWhileContext) interface{} {
	return ctx.WhileStmt().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelStmtBlock(ctx *parser.LabelStmtBlockContext) interface{} {
	return ctx.CodeBlock().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelStmtBreak(ctx *parser.LabelStmtBreakContext) interface{} {
	return ctx.BreakStmt().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelStmtContinue(ctx *parser.LabelStmtContinueContext) interface{} {
	return ctx.ContinueStmt().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelStmtCheck(ctx *parser.LabelStmtCheckContext) interface{} {
	return ctx.CheckStmt().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelStmtDefer(ctx *parser.LabelStmtDeferContext) interface{} {
	return ctx.DeferStmt().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelStmtTry(ctx *parser.LabelStmtTryContext) interface{} {
	tryStmt := &ast.TryStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TryExpr() != nil {
		if expr := ctx.TryExpr().Accept(v); expr != nil {
			tryStmt.Expr = expr.(ast.Expression)
		}
	}

	return tryStmt
}

func (v *ParseTreeToAST) VisitLabelStmtPiped(ctx *parser.LabelStmtPipedContext) interface{} {
	return ctx.PipedStmt().Accept(v)
}

func (v *ParseTreeToAST) VisitReturnStmt(ctx *parser.ReturnStmtContext) interface{} {
	returnStmt := &ast.ReturnStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.ExprList() != nil {
		if exprList := ctx.ExprList().Accept(v); exprList != nil {
			returnStmt.Values = exprList.([]ast.Expression)
		}
	}

	return returnStmt
}

func (v *ParseTreeToAST) VisitYieldStmt(ctx *parser.YieldStmtContext) interface{} {
	yieldStmt := &ast.YieldStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.ExprList() != nil {
		if exprList := ctx.ExprList().Accept(v); exprList != nil {
			yieldStmt.Values = exprList.([]ast.Expression)
		}
	}

	return yieldStmt
}

func (v *ParseTreeToAST) VisitDeferStmt(ctx *parser.DeferStmtContext) interface{} {
	deferStmt := &ast.DeferStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			deferStmt.Expr = expr.(ast.Expression)
		}
	}

	return deferStmt
}

func (v *ParseTreeToAST) VisitExprList(ctx *parser.ExprListContext) interface{} {
	var exprs []ast.Expression
	for _, exprCtx := range ctx.AllExpr() {
		if expr := exprCtx.Accept(v); expr != nil {
			exprs = append(exprs, expr.(ast.Expression))
		}
	}
	return exprs
}

func (v *ParseTreeToAST) VisitIfStmt(ctx *parser.IfStmtContext) interface{} {
	ifStmt := &ast.IfStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			ifStmt.Cond = expr.(ast.Expression)
		}
	}

	codeBlocks := ctx.AllCodeBlock()
	if len(codeBlocks) > 0 {
		if thenBlock := codeBlocks[0].Accept(v); thenBlock != nil {
			ifStmt.Then = thenBlock.(*ast.CodeBlock)
		}
	}

	if len(codeBlocks) > 1 {
		if elseBlock := codeBlocks[1].Accept(v); elseBlock != nil {
			ifStmt.Else = elseBlock.(*ast.CodeBlock)
		}
	}

	return ifStmt
}

func (v *ParseTreeToAST) VisitForStmt(ctx *parser.ForStmtContext) interface{} {
	forStmt := &ast.ForStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.ForLoopType() != nil {
		if loop := ctx.ForLoopType().Accept(v); loop != nil {
			forStmt.Loop = loop.(ast.ForLoop)
		}
	}

	return forStmt
}

func (v *ParseTreeToAST) VisitForLoopType(ctx *parser.ForLoopTypeContext) interface{} {
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
		}
	}
	return nil
}

func (v *ParseTreeToAST) VisitLabelForLoop(ctx *parser.LabelForLoopContext) interface{} {
	return ctx.ForTrinity().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelForInLoop(ctx *parser.LabelForInLoopContext) interface{} {
	forInLoop := &ast.ForInLoop{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	ids := ctx.AllID()
	if len(ids) == 1 {
		forInLoop.Value = ids[0].GetText()
	} else if len(ids) == 2 {
		forInLoop.Key = ids[0].GetText()
		forInLoop.Value = ids[1].GetText()
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			forInLoop.Iterable = expr.(ast.Expression)
		}
	}

	if ctx.LoopBody() != nil {
		if body := ctx.LoopBody().Accept(v); body != nil {
			forInLoop.Body = body.(*ast.LoopBody)
		}
	}

	return forInLoop
}

func (v *ParseTreeToAST) VisitForTrinity(ctx *parser.ForTrinityContext) interface{} {
	forLoop := &ast.ForTrinityLoop{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.ForInit() != nil {
		if init := ctx.ForInit().Accept(v); init != nil {
			fmt.Printf("DEBUG: VisitForTrinity - init is not nil: %T\n", init)
			forLoop.Init = init.(ast.ForInit)
		} else {
			fmt.Printf("DEBUG: VisitForTrinity - init is nil\n")
		}
	} else {
		fmt.Printf("DEBUG: VisitForTrinity - ForInit() context is nil\n")
	}

	if ctx.ForCond() != nil {
		if cond := ctx.ForCond().Accept(v); cond != nil {
			forLoop.Cond = cond.(ast.Expression)
		}
	}

	if ctx.ForPost() != nil {
		if post := ctx.ForPost().Accept(v); post != nil {
			forLoop.Post = post.(ast.Expression)
		}
	}

	if ctx.LoopBody() != nil {
		if body := ctx.LoopBody().Accept(v); body != nil {
			forLoop.Body = body.(*ast.LoopBody)
		}
	}

	fmt.Printf("DEBUG: VisitForTrinity - final forLoop.Init: %v\n", forLoop.Init)
	return forLoop
}

func (v *ParseTreeToAST) VisitForInit(ctx *parser.ForInitContext) interface{} {
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
		}
	}
	return nil
}

func (v *ParseTreeToAST) VisitForCond(ctx *parser.ForCondContext) interface{} {
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
		}
	}
	return nil
}

func (v *ParseTreeToAST) VisitForPost(ctx *parser.ForPostContext) interface{} {
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
		}
	}
	return nil
}

func (v *ParseTreeToAST) VisitLabelForInitLet(ctx *parser.LabelForInitLetContext) interface{} {
	forInitLet := &ast.ForInitLet{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.LetSingle() != nil {
		if letSingle := ctx.LetSingle().Accept(v); letSingle != nil {
			forInitLet.Let = letSingle.(*ast.LetSingle)
		}
	}

	return forInitLet
}

func (v *ParseTreeToAST) VisitLabelForInitEmpty(ctx *parser.LabelForInitEmptyContext) interface{} {
	fmt.Printf("DEBUG: VisitLabelForInitEmpty called, returning nil\n")
	return nil
}

func (v *ParseTreeToAST) VisitLabelForCondExpr(ctx *parser.LabelForCondExprContext) interface{} {
	return ctx.Expr().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelForCondEmpty(ctx *parser.LabelForCondEmptyContext) interface{} {
	return nil
}

func (v *ParseTreeToAST) VisitLabelForPostExpr(ctx *parser.LabelForPostExprContext) interface{} {
	return ctx.Expr().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelForPostEmpty(ctx *parser.LabelForPostEmptyContext) interface{} {
	return nil
}

func (v *ParseTreeToAST) VisitWhileStmt(ctx *parser.WhileStmtContext) interface{} {
	whileStmt := &ast.WhileStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			whileStmt.Cond = expr.(ast.Expression)
		}
	}

	if ctx.LoopBody() != nil {
		if body := ctx.LoopBody().Accept(v); body != nil {
			whileStmt.Body = body.(*ast.LoopBody)
		}
	}

	return whileStmt
}

func (v *ParseTreeToAST) VisitLoopBody(ctx *parser.LoopBodyContext) interface{} {
	loopBody := &ast.LoopBody{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	for _, stmtCtx := range ctx.AllStmt() {
		if stmt := stmtCtx.Accept(v); stmt != nil {
			loopBody.Stmts = append(loopBody.Stmts, stmt.(ast.Statement))
		}
	}

	return loopBody
}

func (v *ParseTreeToAST) VisitCodeBlock(ctx *parser.CodeBlockContext) interface{} {
	codeBlock := &ast.CodeBlock{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	for _, stmtCtx := range ctx.AllStmt() {
		if stmt := stmtCtx.Accept(v); stmt != nil {
			codeBlock.Stmts = append(codeBlock.Stmts, stmt.(ast.Statement))
		}
	}

	return codeBlock
}

func (v *ParseTreeToAST) VisitBreakStmt(ctx *parser.BreakStmtContext) interface{} {
	return &ast.BreakStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}
}

func (v *ParseTreeToAST) VisitContinueStmt(ctx *parser.ContinueStmtContext) interface{} {
	return &ast.ContinueStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}
}

func (v *ParseTreeToAST) VisitCheckStmt(ctx *parser.CheckStmtContext) interface{} {
	checkStmt := &ast.CheckStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			checkStmt.Expr = expr.(ast.Expression)
		}
	}

	if ctx.StringLiteral() != nil {
		if strLit := ctx.StringLiteral().Accept(v); strLit != nil {
			if stringLiteral, ok := strLit.(*ast.StringLiteral); ok {
				checkStmt.Message = v.extractStringValue(stringLiteral)
			}
		}
	}

	return checkStmt
}

// Piped statements

func (v *ParseTreeToAST) VisitPipedStmt(ctx *parser.PipedStmtContext) interface{} {
	pipedStmt := &ast.PipedStmt{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	// First expression is the source (no arguments)
	postfixExprs := ctx.AllPostfixExpr()
	pipedArgsCtxs := ctx.AllPipedArgs()

	for i, exprCtx := range postfixExprs {
		pipedCall := &ast.PipedCall{
			BaseNode: ast.BaseNode{Position: v.getPosition(exprCtx)},
		}

		if expr := exprCtx.Accept(v); expr != nil {
			pipedCall.Expr = expr.(ast.Expression)
		}

		// Associate piped args with the correct function
		// pipedArgs come after postfixExprs in order, but the first postfixExpr (source) has no args
		if i > 0 { // Skip source (first expr)
			argIndex := i - 1 // Adjust index since pipedArgs start after the source
			if argIndex < len(pipedArgsCtxs) && pipedArgsCtxs[argIndex] != nil {
				if args := pipedArgsCtxs[argIndex].Accept(v); args != nil {
					pipedCall.Args = args.([]ast.PipedArg)
				}
			}
		}

		pipedStmt.Calls = append(pipedStmt.Calls, *pipedCall)
	}

	return pipedStmt
}

func (v *ParseTreeToAST) VisitPipedArgs(ctx *parser.PipedArgsContext) interface{} {
	var args []ast.PipedArg
	for _, argCtx := range ctx.AllPipedArg() {
		if arg := argCtx.Accept(v); arg != nil {
			args = append(args, arg.(ast.PipedArg))
		}
	}
	return args
}

func (v *ParseTreeToAST) VisitPipedArg(ctx *parser.PipedArgContext) interface{} {
	pipedArg := ast.PipedArg{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			pipedArg.Value = expr.(ast.Expression)
		}
	}

	return pipedArg
}
