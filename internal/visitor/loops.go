package visitor

import (
	"fmt"
	"go/ast"
	gotoken "go/token"
	"manuscript-co/manuscript/internal/parser"
)

// VisitLoopBody handles the body of a loop which can contain statements.
// loopBody: LBRACE (stmt)* RBRACE;
func (v *ManuscriptAstVisitor) VisitLoopBody(ctx *parser.LoopBodyContext) interface{} {
	if ctx == nil {
		return &ast.BlockStmt{} // Should not happen if called correctly
	}

	var stmts []ast.Stmt

	// Process all stmt nodes in the loop body
	for _, stmtCtx := range ctx.AllStmt() {
		visitedStmt := v.Visit(stmtCtx)
		if stmt, ok := visitedStmt.(ast.Stmt); ok {
			if stmt != nil { // Ensure we don't append nil statements
				stmts = append(stmts, stmt)
			}
		} else if visitedStmt != nil {
			v.addError(fmt.Sprintf("Loop body statement did not resolve to ast.Stmt, got %T", visitedStmt), stmtCtx.GetStart())
		}
	}

	return &ast.BlockStmt{
		Lbrace: v.pos(ctx.LBRACE().GetSymbol()),
		List:   stmts,
		Rbrace: v.pos(ctx.RBRACE().GetSymbol()),
	}
}

// VisitWhileStmt handles while loops.
// Manuscript: while condition { body } -> while condition loopBody
// Go: for condition { body }
func (v *ManuscriptAstVisitor) VisitWhileStmt(ctx *parser.WhileStmtContext) interface{} {
	v.enterLoop()
	defer v.exitLoop()

	forStmtNode := &ast.ForStmt{
		For: v.pos(ctx.WHILE().GetSymbol()),
	}

	// Condition is ctx.Expr() based on `whileStmt: WHILE condition = expr loopBody;`
	if condCtx := ctx.Expr(); condCtx != nil {
		condVisited := v.Visit(condCtx) // Use generic v.Visit
		if condExpr, ok := condVisited.(ast.Expr); ok {
			forStmtNode.Cond = condExpr
		} else if condVisited != nil {
			v.addError(fmt.Sprintf("While loop condition was %T, expected ast.Expr", condVisited), condCtx.GetStart())
		} else { // Should not happen if grammar is correct (condition is mandatory if Expr() not nil)
			v.addError("While loop missing condition expression", condCtx.GetStart())
		}
	} else {
		v.addError("While loop missing condition context (Expr)", ctx.GetStart())
	}

	// Body is ctx.LoopBody() based on `whileStmt: WHILE condition = expr loopBody;`
	if bodyRuleCtx := ctx.LoopBody(); bodyRuleCtx != nil {
		// Create default empty block in case of errors
		forStmtNode.Body = &ast.BlockStmt{
			Lbrace: v.pos(bodyRuleCtx.GetStart()),
			Rbrace: v.pos(bodyRuleCtx.GetStop()),
		}

		// Try to get concrete loop body context
		if concreteLoopBodyCtx, ok := bodyRuleCtx.(*parser.LoopBodyContext); ok {
			if bodyAst, ok := v.VisitLoopBody(concreteLoopBodyCtx).(*ast.BlockStmt); ok {
				forStmtNode.Body = bodyAst
			} else {
				v.addError(fmt.Sprintf("While loop body did not resolve to *ast.BlockStmt, got %T", bodyRuleCtx), bodyRuleCtx.GetStart())
			}
		} else {
			v.addError(fmt.Sprintf("While loop body was not *parser.LoopBodyContext, got %T", bodyRuleCtx), bodyRuleCtx.GetStart())
		}
	} else {
		v.addError("While loop missing body (LoopBody)", ctx.GetStart())
		return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	return forStmtNode
}

// VisitForTrinity handles C-style for loops (init; cond; post; body)
func (v *ManuscriptAstVisitor) VisitForTrinity(ctx *parser.ForTrinityContext) interface{} {
	if ctx == nil {
		return &ast.BadStmt{}
	}

	// Init
	var initStmt ast.Stmt
	if decl := ctx.GetInitializerDecl(); decl != nil {
		// Always use := for for-loop init
		if cinit := decl.(*parser.LetSingleContext); cinit != nil {
			if stmt, ok := v.VisitLetSingle(cinit).(ast.Stmt); ok {
				initStmt = stmt
			}
		}
	} else if exprs := ctx.GetInitializerExprs(); exprs != nil {
		if stmt, ok := v.Visit(exprs).(ast.Stmt); ok {
			initStmt = stmt
		}
	}

	// Cond
	var condExpr ast.Expr
	if cond := ctx.GetCondition(); cond != nil {
		if expr, ok := v.Visit(cond).(ast.Expr); ok {
			condExpr = expr
		}
	}

	// Post
	var postStmt ast.Stmt
	if post := ctx.GetPostUpdate(); post != nil {
		if stmt, ok := v.Visit(post).(ast.Stmt); ok {
			postStmt = stmt
		} else if expr, ok := v.Visit(post).(ast.Expr); ok {
			postStmt = &ast.ExprStmt{X: expr}
		}
	}

	// Body
	var body *ast.BlockStmt
	if b := ctx.GetBody(); b != nil {
		if block, ok := v.VisitLoopBody(b.(*parser.LoopBodyContext)).(*ast.BlockStmt); ok {
			body = block
		} else {
			body = &ast.BlockStmt{}
		}
	} else {
		body = &ast.BlockStmt{}
	}

	return &ast.ForStmt{
		For:  0, // Position can be set by parent
		Init: initStmt,
		Cond: condExpr,
		Post: postStmt,
		Body: body,
	}
}

// VisitForInLoop handles for-in loops
func (v *ManuscriptAstVisitor) VisitForInLoop(ctx *parser.ForInLoopContext) interface{} {
	if ctx == nil {
		return &ast.BadStmt{}
	}
	stmt := &ast.RangeStmt{Tok: gotoken.DEFINE}
	// Iterable
	if it := ctx.GetIterable(); it != nil {
		if expr, ok := v.Visit(it).(ast.Expr); ok {
			stmt.X = expr
		} else {
			stmt.X = &ast.BadExpr{}
		}
	}
	// Vars
	key, val := ctx.GetKey(), ctx.GetVal()
	if key == nil {
		stmt.Key = ast.NewIdent("_")
	} else if val != nil {
		stmt.Key = ast.NewIdent(val.GetText())
		stmt.Value = ast.NewIdent(key.GetText())
	} else {
		stmt.Key = ast.NewIdent("_")
		stmt.Value = ast.NewIdent(key.GetText())
	}
	// Body
	if b := ctx.LoopBody(); b != nil {
		if block, ok := v.VisitLoopBody(b.(*parser.LoopBodyContext)).(*ast.BlockStmt); ok {
			stmt.Body = block
		} else {
			stmt.Body = &ast.BlockStmt{}
		}
	} else {
		stmt.Body = &ast.BlockStmt{}
	}
	return stmt
}

// VisitForStmt dispatches to the correct for-loop type
func (v *ManuscriptAstVisitor) VisitForStmt(ctx *parser.ForStmtContext) interface{} {
	v.enterLoop()
	defer v.exitLoop()

	if ctx == nil || ctx.ForLoopType() == nil {
		return &ast.BadStmt{}
	}

	switch t := ctx.ForLoopType().(type) {
	case *parser.ForLoopContext:
		forTrinity := t.ForTrinity()
		if forTrinity == nil {
			return &ast.BadStmt{}
		}
		stmt := v.VisitForTrinity(forTrinity.(*parser.ForTrinityContext))
		if fs, ok := stmt.(*ast.ForStmt); ok {
			fs.For = v.pos(ctx.FOR().GetSymbol())
			return fs
		}
		return stmt
	case *parser.ForInLoopContext:
		stmt := v.VisitForInLoop(t)
		if rs, ok := stmt.(*ast.RangeStmt); ok {
			rs.For = v.pos(ctx.FOR().GetSymbol())
			return rs
		}
		return stmt
	default:
		return &ast.BadStmt{}
	}
}
