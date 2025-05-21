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

	if stmtList := ctx.Stmt_list(); stmtList != nil {
		for _, stmtCtx := range stmtList.AllStmt() {
			if stmtCtx == nil {
				continue
			}
			visitedStmt := v.VisitStmt(stmtCtx)
			if stmt, ok := visitedStmt.(ast.Stmt); ok {
				if stmt != nil {
					stmts = append(stmts, stmt)
				}
			} else if visitedStmt != nil {
				v.addError(fmt.Sprintf("Loop body statement did not resolve to ast.Stmt, got %T", visitedStmt), stmtCtx.GetStart())
			}
		}
	}

	var lbrace, rbrace gotoken.Pos
	if ctx.LBRACE() != nil {
		lbrace = v.pos(ctx.LBRACE().GetSymbol())
	}
	if ctx.RBRACE() != nil {
		rbrace = v.pos(ctx.RBRACE().GetSymbol())
	}
	return &ast.BlockStmt{
		Lbrace: lbrace,
		List:   stmts,
		Rbrace: rbrace,
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
		bodyRaw := v.VisitLoopBody(bodyRuleCtx.(*parser.LoopBodyContext))
		var bodyBlock *ast.BlockStmt
		switch b := bodyRaw.(type) {
		case *ast.BlockStmt:
			bodyBlock = b
		case []ast.Stmt:
			bodyBlock = &ast.BlockStmt{List: b}
		case ast.Stmt:
			bodyBlock = &ast.BlockStmt{List: []ast.Stmt{b}}
		default:
			v.addError("While loop body did not resolve to a valid block or statement", bodyRuleCtx.GetStart())
			bodyBlock = &ast.BlockStmt{}
		}
		forStmtNode.Body = bodyBlock
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

	initVal := v.Visit(ctx.ForInit())
	initStmt := v.asStmtOrExprStmt(initVal)
	if _, isEmpty := initVal.(*ast.EmptyStmt); isEmpty {
		initStmt = nil
	}
	condExpr := v.asExpr(v.Visit(ctx.ForCond()))
	postVal := v.Visit(ctx.ForPost())
	postStmt := v.asStmtOrExprStmt(postVal)
	if _, isEmpty := postVal.(*ast.EmptyStmt); isEmpty {
		postStmt = nil
	}

	body := &ast.BlockStmt{}
	if b := ctx.LoopBody(); b != nil {
		bodyRaw := v.VisitLoopBody(b.(*parser.LoopBodyContext))
		switch bb := bodyRaw.(type) {
		case *ast.BlockStmt:
			body = bb
		case []ast.Stmt:
			body = &ast.BlockStmt{List: bb}
		case ast.Stmt:
			body = &ast.BlockStmt{List: []ast.Stmt{bb}}
		default:
			v.addError("For loop body did not resolve to a valid block or statement", b.GetStart())
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

// VisitForInit handles forInit alternatives.
func (v *ManuscriptAstVisitor) VisitForInit(ctx *parser.ForInitContext) interface{} {
	if ctx.LetSingle() != nil {
		return v.Visit(ctx.LetSingle())
	}
	return &ast.EmptyStmt{}
}

// VisitForCond handles forCond alternatives.
func (v *ManuscriptAstVisitor) VisitForCond(ctx *parser.ForCondContext) interface{} {
	if ctx.Expr() != nil {
		return v.Visit(ctx.Expr())
	}
	return nil
}

// VisitForPost handles forPost alternatives.
func (v *ManuscriptAstVisitor) VisitForPost(ctx *parser.ForPostContext) interface{} {
	if ctx.Expr() != nil {
		return v.Visit(ctx.Expr())
	}
	return nil
}

// VisitForIn handles for-in loops: (ID (COMMA ID)?) IN expr loopBody;
func (v *ManuscriptAstVisitor) VisitForIn(ctx parser.IForLoopTypeContext) interface{} {
	if ctx == nil {
		return &ast.BadStmt{}
	}

	ids := ctx.AllID()
	stmt := &ast.RangeStmt{
		Tok: gotoken.DEFINE, // Use := for new variables
	}
	switch len(ids) {
	case 2:
		stmt.Key = ast.NewIdent(ids[1].GetText())
		stmt.Value = ast.NewIdent(ids[0].GetText())
	case 1:
		stmt.Key = ast.NewIdent("_")
		stmt.Value = ast.NewIdent(ids[0].GetText())
	default:
		v.addError("Invalid number of variables in for-in loop. Expected 1 or 2.", ctx.GetStart())
		stmt.Key = ast.NewIdent("_")
		stmt.Value = ast.NewIdent("_")
		return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	if exprCtx := ctx.Expr(); exprCtx != nil {
		if expr, ok := v.Visit(exprCtx).(ast.Expr); ok {
			stmt.X = expr
		} else {
			stmt.X = &ast.BadExpr{}
		}
	}

	stmt.Body = &ast.BlockStmt{}
	if bodyCtx := ctx.LoopBody(); bodyCtx != nil {
		bodyRaw := v.VisitLoopBody(bodyCtx.(*parser.LoopBodyContext))
		switch bb := bodyRaw.(type) {
		case *ast.BlockStmt:
			stmt.Body = bb
		case []ast.Stmt:
			stmt.Body = &ast.BlockStmt{List: bb}
		case ast.Stmt:
			stmt.Body = &ast.BlockStmt{List: []ast.Stmt{bb}}
		default:
			v.addError("For-in loop body did not resolve to a valid block or statement", bodyCtx.GetStart())
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

	forLoopType := ctx.ForLoopType()
	if forLoopType.ForTrinity() != nil {
		stmt := v.Visit(forLoopType.ForTrinity())
		if fs, ok := stmt.(*ast.ForStmt); ok {
			fs.For = v.pos(ctx.FOR().GetSymbol())
			return fs
		}
		return stmt
	}
	// Otherwise, treat as for-in loop
	stmt := v.VisitForIn(forLoopType)
	if rs, ok := stmt.(*ast.RangeStmt); ok {
		rs.For = v.pos(ctx.FOR().GetSymbol())
		return rs
	}
	return stmt
}
