package visitor

import (
	"fmt"
	"go/ast"
	gotoken "go/token"
	"manuscript-co/manuscript/internal/parser"
)

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
		condVisited := v.Visit(condCtx)
		if condExpr, ok := condVisited.(ast.Expr); ok {
			forStmtNode.Cond = condExpr
		} else if condVisited != nil {
			v.addError(fmt.Sprintf("While loop condition was %T, expected ast.Expr", condVisited), condCtx.GetStart())
		} else {
			v.addError("While loop missing condition expression", condCtx.GetStart())
		}
	} else {
		v.addError("While loop missing condition context (Expr)", ctx.GetStart())
	}

	// Body is ctx.LoopBody() based on `whileStmt: WHILE condition = expr loopBody;`
	if bodyRuleCtx := ctx.LoopBody(); bodyRuleCtx != nil {
		forStmtNode.Body = &ast.BlockStmt{
			Lbrace: v.pos(bodyRuleCtx.GetStart()),
			Rbrace: v.pos(bodyRuleCtx.GetStop()),
		}

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

// VisitForTrinity handles forTrinity: forInit SEMICOLON forCond SEMICOLON forPost loopBody;
func (v *ManuscriptAstVisitor) VisitForTrinity(ctx *parser.ForTrinityContext) interface{} {
	if ctx == nil {
		return &ast.BadStmt{}
	}

	initStmt := v.asStmt(v.Visit(ctx.ForInit()))
	condExpr := v.asExpr(v.Visit(ctx.ForCond()))
	postStmt := v.asStmtOrExprStmt(v.Visit(ctx.ForPost()))

	body := &ast.BlockStmt{}
	if b := ctx.LoopBody(); b != nil {
		if block, ok := v.VisitLoopBody(b.(*parser.LoopBodyContext)).(*ast.BlockStmt); ok && block != nil {
			body = block
		}
	}

	return &ast.ForStmt{
		For:  0, // Position set by parent VisitForStmt
		Init: initStmt,
		Cond: condExpr,
		Post: postStmt,
		Body: body,
	}
}

// --- ANTLR visitor pattern for forInit, forCond, forPost ---

func (v *ManuscriptAstVisitor) VisitForInitLet(ctx *parser.ForInitLetContext) interface{} {
	if ctx == nil || ctx.LetSingle() == nil {
		return &ast.EmptyStmt{}
	}
	return v.Visit(ctx.LetSingle())
}

func (v *ManuscriptAstVisitor) VisitForInitEmpty(ctx *parser.ForInitEmptyContext) interface{} {
	return &ast.EmptyStmt{}
}

func (v *ManuscriptAstVisitor) VisitForCondExpr(ctx *parser.ForCondExprContext) interface{} {
	if ctx == nil || ctx.Expr() == nil {
		return nil
	}
	return v.Visit(ctx.Expr())
}

func (v *ManuscriptAstVisitor) VisitForCondEmpty(ctx *parser.ForCondEmptyContext) interface{} {
	return nil
}

func (v *ManuscriptAstVisitor) VisitForPostExpr(ctx *parser.ForPostExprContext) interface{} {
	if ctx == nil || ctx.Expr() == nil {
		return nil
	}
	return v.Visit(ctx.Expr())
}

func (v *ManuscriptAstVisitor) VisitForPostEmpty(ctx *parser.ForPostEmptyContext) interface{} {
	return nil
}

// VisitForInLoop handles for-in loops: (ID (COMMA ID)?) IN expr loopBody;
func (v *ManuscriptAstVisitor) VisitForInLoop(ctx *parser.ForInLoopContext) interface{} {
	if ctx == nil {
		return &ast.BadStmt{}
	}

	stmt := &ast.RangeStmt{
		Tok: gotoken.DEFINE, // Use := for new variables
	}

	ids := ctx.AllID()
	switch len(ids) {
	case 2:
		// Manuscript: value, key in items
		// Go: for key, value := range items
		stmt.Key = ast.NewIdent(ids[1].GetText())   // key
		stmt.Value = ast.NewIdent(ids[0].GetText()) // value
	case 1:
		// Manuscript: value in items
		// Go: for _, value := range items
		stmt.Key = ast.NewIdent("_")
		stmt.Value = ast.NewIdent(ids[0].GetText())
	default:
		v.addError("Invalid number of variables in for-in loop. Expected 1 or 2.", ctx.GetStart())
		stmt.Key = ast.NewIdent("_")
		stmt.Value = ast.NewIdent("_")
		return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	// Set the range expression (the iterable)
	if exprCtx := ctx.Expr(); exprCtx != nil {
		if expr, ok := v.Visit(exprCtx).(ast.Expr); ok {
			stmt.X = expr
		} else {
			stmt.X = &ast.BadExpr{}
		}
	}

	// Set the loop body
	stmt.Body = &ast.BlockStmt{}
	if bodyCtx := ctx.LoopBody(); bodyCtx != nil {
		if loopBody, ok := v.VisitLoopBody(bodyCtx.(*parser.LoopBodyContext)).(*ast.BlockStmt); ok {
			stmt.Body = loopBody
		}
	}

	return stmt
}

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
