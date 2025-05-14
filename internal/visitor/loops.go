package visitor

import (
	"fmt"
	"go/ast"
	gotoken "go/token"
	"manuscript-co/manuscript/internal/parser"
)

// VisitBreakStmt handles a break statement.
func (v *ManuscriptAstVisitor) VisitBreakStmt(ctx *parser.BreakStmtContext) interface{} {
	if v.loopDepth == 0 {
		v.addError("'break' statement found outside of a loop", ctx.BREAK().GetSymbol())
		return &ast.BadStmt{From: v.pos(ctx.BREAK().GetSymbol()), To: v.pos(ctx.BREAK().GetSymbol())}
	}
	return &ast.BranchStmt{
		TokPos: v.pos(ctx.BREAK().GetSymbol()),
		Tok:    gotoken.BREAK,
	}
}

// VisitContinueStmt handles a continue statement.
func (v *ManuscriptAstVisitor) VisitContinueStmt(ctx *parser.ContinueStmtContext) interface{} {
	if v.loopDepth == 0 {
		v.addError("'continue' statement found outside of a loop", ctx.CONTINUE().GetSymbol())
		return &ast.BadStmt{From: v.pos(ctx.CONTINUE().GetSymbol()), To: v.pos(ctx.CONTINUE().GetSymbol())}
	}
	return &ast.BranchStmt{
		TokPos: v.pos(ctx.CONTINUE().GetSymbol()),
		Tok:    gotoken.CONTINUE,
	}
}

// VisitWhileStmt handles while loops.
// Manuscript: while condition { body }
// Go: for condition { body }
func (v *ManuscriptAstVisitor) VisitWhileStmt(ctx *parser.WhileStmtContext) interface{} {
	v.loopDepth++
	defer func() { v.loopDepth-- }()

	forStmtNode := &ast.ForStmt{
		For: v.pos(ctx.WHILE().GetSymbol()),
	}

	if condCtx := ctx.GetCondition(); condCtx != nil {
		condVisited := condCtx.Accept(v)
		if condExpr, ok := condVisited.(ast.Expr); ok {
			forStmtNode.Cond = condExpr
		} else if condVisited != nil {
			v.addError(fmt.Sprintf("While loop condition was %T, expected ast.Expr", condVisited), condCtx.GetStart())
		} else { // Should not happen if grammar is correct (condition is mandatory)
			v.addError("While loop missing condition", condCtx.GetStart())
		}
	} else {
		v.addError("While loop missing condition context", ctx.GetStart())
	}

	bodyCtx := ctx.GetBlock()
	if bodyCtx == nil {
		v.addError("While loop missing body block", ctx.GetStart())
		return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
	bodyVisited := bodyCtx.Accept(v)
	if blockStmt, ok := bodyVisited.(*ast.BlockStmt); ok {
		forStmtNode.Body = blockStmt
	} else {
		v.addError(fmt.Sprintf("While loop body was %T, expected *ast.BlockStmt", bodyVisited), bodyCtx.GetStart())
		forStmtNode.Body = &ast.BlockStmt{Lbrace: v.pos(bodyCtx.GetStart()), Rbrace: v.pos(bodyCtx.GetStop())}
	}

	return forStmtNode
}

// VisitForStmt handles both C-style and for-in loops.
func (v *ManuscriptAstVisitor) VisitForStmt(ctx *parser.ForStmtContext) interface{} {
	v.loopDepth++
	defer func() { v.loopDepth-- }()

	// Determine if it's a for-in loop or C-style loop
	if ctx.GetLoopVars() != nil && ctx.GetIterable() != nil {
		// For-in loop
		rangeStmt := &ast.RangeStmt{
			For: v.pos(ctx.FOR().GetSymbol()),
			Tok: gotoken.DEFINE, // Default to :=
		}

		// Iterable
		iterableVisited := ctx.GetIterable().Accept(v)
		if iterableExpr, ok := iterableVisited.(ast.Expr); ok {
			rangeStmt.X = iterableExpr
		} else if iterableVisited != nil {
			v.addError(fmt.Sprintf("For-in loop iterable was %T, expected ast.Expr", iterableVisited), ctx.GetIterable().GetStart())
			rangeStmt.X = &ast.BadExpr{From: v.pos(ctx.GetIterable().GetStart()), To: v.pos(ctx.GetIterable().GetStop())}
		} else {
			v.addError("For-in loop iterable is missing or invalid", ctx.GetStart())
			rangeStmt.X = &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStart())}
		}

		// Loop variables from loopPattern: var1 = ID (COMMA var2 = ID)?;
		loopVarsCtx := ctx.GetLoopVars()
		var1Token := loopVarsCtx.GetVar1() // Returns antlr.Token
		if var1Token == nil {
			v.addError("Missing first variable in for-in loop", loopVarsCtx.GetStart())
			return &ast.BadStmt{From: v.pos(loopVarsCtx.GetStart()), To: v.pos(loopVarsCtx.GetStop())}
		}
		var1Name := var1Token.GetText()

		var2Token := loopVarsCtx.GetVar2() // Returns antlr.Token, can be nil
		if var2Token != nil {
			var2Name := var2Token.GetText()
			// Manuscript: for val, idx in arr -> Go: for idx, val := range arr
			rangeStmt.Key = ast.NewIdent(var2Name)
			rangeStmt.Value = ast.NewIdent(var1Name)
		} else {
			// Manuscript: for val in arr -> Go: for _, val := range arr
			// This is a simplification; map key iteration needs type info or different syntax.
			rangeStmt.Key = ast.NewIdent("_")
			rangeStmt.Value = ast.NewIdent(var1Name)
		}

		// Body
		bodyCtx := ctx.GetBlock() // Common block accessor
		if bodyCtx == nil {
			v.addError("For-in loop missing body block", ctx.GetStart())
			return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStart())}
		}
		bodyVisited := bodyCtx.Accept(v)
		if blockStmt, ok := bodyVisited.(*ast.BlockStmt); ok {
			rangeStmt.Body = blockStmt
		} else {
			v.addError(fmt.Sprintf("For-in loop body was %T, expected *ast.BlockStmt", bodyVisited), bodyCtx.GetStart())
			rangeStmt.Body = &ast.BlockStmt{Lbrace: v.pos(bodyCtx.GetStart()), Rbrace: v.pos(bodyCtx.GetStop())}
		}
		return rangeStmt

	} else {
		// C-style for loop
		forStmt := &ast.ForStmt{
			For: v.pos(ctx.FOR().GetSymbol()),
		}

		// Init (forInitPattn: letDecl | expr)
		if initCtx := ctx.GetCStyleInit(); initCtx != nil {
			initVisited := initCtx.Accept(v) // VisitForInitPattn should return ast.Stmt
			if initStmt, ok := initVisited.(ast.Stmt); ok {
				forStmt.Init = initStmt
			} else if initVisited != nil {
				v.addError(fmt.Sprintf("C-style for loop initializer was %T, expected ast.Stmt", initVisited), initCtx.GetStart())
			}
		}

		// Condition (expr?)
		if condCtx := ctx.GetCStyleCond(); condCtx != nil {
			condVisited := condCtx.Accept(v)
			if condExpr, ok := condVisited.(ast.Expr); ok {
				forStmt.Cond = condExpr
			} else if condVisited != nil {
				v.addError(fmt.Sprintf("C-style for loop condition was %T, expected ast.Expr", condVisited), condCtx.GetStart())
			}
		}

		// Post (expr?)
		if postCtx := ctx.GetCStylePost(); postCtx != nil {
			postVisited := postCtx.Accept(v) // Can be ast.Stmt (for assignments) or ast.Expr (for calls)
			switch node := postVisited.(type) {
			case ast.Stmt: // e.g., ast.AssignStmt, ast.IncDecStmt
				forStmt.Post = node
			case ast.Expr: // e.g., ast.CallExpr
				forStmt.Post = &ast.ExprStmt{X: node}
			default:
				if postVisited != nil {
					v.addError(fmt.Sprintf("C-style for loop post operation was %T, expected ast.Stmt or ast.Expr", postVisited), postCtx.GetStart())
				}
			}
		}

		// Body
		bodyCtx := ctx.GetBlock() // Common block accessor
		if bodyCtx == nil {
			v.addError("C-style for loop missing body block", ctx.GetStart())
			return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStart())}
		}
		bodyVisited := bodyCtx.Accept(v)
		if blockStmt, ok := bodyVisited.(*ast.BlockStmt); ok {
			forStmt.Body = blockStmt
		} else {
			v.addError(fmt.Sprintf("C-style for loop body was %T, expected *ast.BlockStmt", bodyVisited), bodyCtx.GetStart())
			forStmt.Body = &ast.BlockStmt{Lbrace: v.pos(bodyCtx.GetStart()), Rbrace: v.pos(bodyCtx.GetStop())}
		}
		return forStmt
	}
}

func (v *ManuscriptAstVisitor) VisitForInitPattn(ctx *parser.ForInitPattnContext) interface{} {
	if ctx.LetDecl() != nil {
		val := ctx.LetDecl().Accept(v) // Assuming VisitLetDecl returns ast.Stmt
		if stmt, ok := val.(ast.Stmt); ok {
			return stmt
		}
		v.addError(fmt.Sprintf("letDecl in for-init was %T, expected ast.Stmt", val), ctx.LetDecl().GetStart())
		return &ast.BadStmt{From: v.pos(ctx.LetDecl().GetStart()), To: v.pos(ctx.LetDecl().GetStop())}
	}
	if ctx.Expr() != nil {
		val := ctx.Expr().Accept(v)
		switch node := val.(type) {
		case ast.Stmt: // For assignments like i = 0 (if VisitAssignmentExpr returns Stmt)
			return node
		case ast.Expr: // For expressions like function calls foo()
			return &ast.ExprStmt{X: node}
		default:
			if val != nil {
				v.addError(fmt.Sprintf("Expression in for-init was %T, expected ast.Stmt or ast.Expr", val), ctx.Expr().GetStart())
			}
			return &ast.BadStmt{From: v.pos(ctx.Expr().GetStart()), To: v.pos(ctx.Expr().GetStop())}
		}
	}
	v.addError("Empty for-init pattern", ctx.GetStart())
	return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
}

// VisitLoopPattern handles the pattern part of a for-in loop.
// loopPattern: var1=ID (COMMA var2=ID)?;
// This method isn't strictly needed if its parts are accessed directly (GetVar1, GetVar2)
// as done in visitForInLoop. If complex logic were needed for the pattern itself,
// this visitor method would be fleshed out.
func (v *ManuscriptAstVisitor) VisitLoopPattern(ctx *parser.LoopPatternContext) interface{} {
	// Typically, this would construct some representation of the loop variables.
	// However, visitForInLoop accesses ctx.GetVar1() and ctx.GetVar2() directly.
	// If we wanted to return a struct or specific node type for the pattern:
	// vars := []*ast.Ident{ast.NewIdent(ctx.GetVar1().GetText())}
	// if ctx.GetVar2() != nil {
	// 	vars = append(vars, ast.NewIdent(ctx.GetVar2().GetText()))
	// }
	// return vars // Or some custom struct
	return v.VisitChildren(ctx) // Default behavior, probably not what's desired if this is used.
}
