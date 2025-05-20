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
		visitedStmt := v.VisitStmt(stmtCtx)
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

// VisitForTrinity handles forTrinity: (letSingle | exprList)? SEMICOLON expr? SEMICOLON exprList? loopBody;
func (v *ManuscriptAstVisitor) VisitForTrinity(ctx *parser.ForTrinityContext) interface{} {
	if ctx == nil {
		return &ast.BadStmt{}
	}

	var initStmt ast.Stmt
	var postStmt ast.Stmt
	var condExpr ast.Expr

	// --- Init ---
	if forInit := ctx.ForInit(); forInit != nil {
		if letSingle := forInit.LetSingle(); letSingle != nil {
			if visited := v.Visit(letSingle); visited != nil {
				if stmt, ok := visited.(ast.Stmt); ok {
					initStmt = stmt
				}
			}
		}
	}

	// --- Condition ---
	if forCond := ctx.ForCond(); forCond != nil {
		if expr := forCond.Expr(); expr != nil {
			if visited := v.Visit(expr); visited != nil {
				if e, ok := visited.(ast.Expr); ok {
					condExpr = e
				}
			}
		}
	}

	// --- Post ---
	if forPost := ctx.ForPost(); forPost != nil {
		if expr := forPost.Expr(); expr != nil {
			if visited := v.Visit(expr); visited != nil {
				if stmt, ok := visited.(ast.Stmt); ok {
					postStmt = stmt
				} else if e, ok := visited.(ast.Expr); ok {
					postStmt = &ast.ExprStmt{X: e}
				}
			}
		}
	}

	// --- Body ---
	var body *ast.BlockStmt
	if b := ctx.LoopBody(); b != nil {
		if visitedBody := v.VisitLoopBody(b.(*parser.LoopBodyContext)); visitedBody != nil {
			if block, ok := visitedBody.(*ast.BlockStmt); ok {
				body = block
			} else {
				body = &ast.BlockStmt{}
			}
		} else {
			body = &ast.BlockStmt{}
		}
	} else {
		body = &ast.BlockStmt{}
	}

	return &ast.ForStmt{
		For:  0, // Position set by parent VisitForStmt
		Init: initStmt,
		Cond: condExpr,
		Post: postStmt,
		Body: body,
	}
}

// VisitForInLoop handles for-in loops: (ID (COMMA ID)?) IN expr loopBody;
func (v *ManuscriptAstVisitor) VisitForInLoop(ctx *parser.ForInLoopContext) interface{} {
	if ctx == nil {
		return &ast.BadStmt{}
	}
	stmt := &ast.RangeStmt{Tok: gotoken.DEFINE} // Use DEFINE for new vars
	ids := ctx.AllID()

	if len(ids) == 2 { // Manuscript: id_value, id_key (e.g., "value, index in items")
		// Go expects: for key, value := range items
		stmt.Key = ast.NewIdent(ids[1].GetText())   // Second ID in Manuscript is key for Go
		stmt.Value = ast.NewIdent(ids[0].GetText()) // First ID in Manuscript is value for Go
	} else if len(ids) == 1 { // Manuscript: id_value (e.g., "value in items")
		// Go expects: for _, value := range items
		stmt.Key = ast.NewIdent("_")
		stmt.Value = ast.NewIdent(ids[0].GetText()) // The single ID in Manuscript is value for Go
	} else {
		// This case should ideally not be reached based on grammar: (ID (COMMA ID)?)
		// which means 1 or 2 IDs.
		v.addError("Invalid number of variables in for-in loop. Expected 1 or 2.", ctx.GetStart())
		// Default to a safe state or return a BadStmt
		stmt.Key = ast.NewIdent("_")   // Placeholder
		stmt.Value = ast.NewIdent("_") // Placeholder to avoid nil, though it's unusual
		return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	if it := ctx.Expr(); it != nil {
		if expr, ok := v.Visit(it).(ast.Expr); ok {
			stmt.X = expr
		} else {
			stmt.X = &ast.BadExpr{}
		}
	}

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
