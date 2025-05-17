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
		// Ensure bodyRuleCtx is *parser.LoopBodyContext before calling VisitLoopBody
		if concreteLoopBodyCtx, ok := bodyRuleCtx.(*parser.LoopBodyContext); ok {
			visitedBody := v.VisitLoopBody(concreteLoopBodyCtx)
			if bodyAst, bodyOk := visitedBody.(*ast.BlockStmt); bodyOk {
				forStmtNode.Body = bodyAst
			} else {
				v.addError(fmt.Sprintf("While loop body did not resolve to *ast.BlockStmt, got %T", visitedBody), bodyRuleCtx.GetStart())
				forStmtNode.Body = &ast.BlockStmt{Lbrace: v.pos(bodyRuleCtx.GetStart()), Rbrace: v.pos(bodyRuleCtx.GetStop())} // fallback
			}
		} else {
			v.addError(fmt.Sprintf("While loop body was not *parser.LoopBodyContext, got %T", bodyRuleCtx), bodyRuleCtx.GetStart())
			forStmtNode.Body = &ast.BlockStmt{Lbrace: v.pos(bodyRuleCtx.GetStart()), Rbrace: v.pos(bodyRuleCtx.GetStop())}
		}
	} else {
		v.addError("While loop missing body (LoopBody)", ctx.GetStart())
		return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	return forStmtNode
}

// VisitForStmt handles both C-style and for-in loops.
func (v *ManuscriptAstVisitor) VisitForStmt(ctx *parser.ForStmtContext) interface{} {
	v.enterLoop()
	defer v.exitLoop()

	forLoopTypeInterface := ctx.ForLoopType()
	if forLoopTypeInterface == nil {
		v.addError("For loop is missing its type (forLoopType)", ctx.GetStart())
		return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	switch typeCtx := forLoopTypeInterface.(type) {
	case *parser.ForLoopContext: // This corresponds to the #ForLoop label (forTrinity rule)
		forTrinityCtx := typeCtx.ForTrinity()
		if forTrinityCtx == nil {
			v.addError("For loop is missing its trinity construct", typeCtx.GetStart())
			return &ast.BadStmt{From: v.pos(typeCtx.GetStart()), To: v.pos(typeCtx.GetStop())}
		}

		// Handle initialization
		var initStmt ast.Stmt
		initDeclCtx := forTrinityCtx.GetInitializerDecl()
		initExprsCtx := forTrinityCtx.GetInitializerExprs()

		if initDeclCtx != nil {
			initVisited := v.Visit(initDeclCtx)
			if stmt, ok := initVisited.(ast.Stmt); ok {
				initStmt = stmt
			} else {
				processedManually := false
				// Replace YourLetSingleDeclContextType with the actual concrete context type from your parser
				// that implements parser.IDeclContext for a single `let name = expr` style declaration.
				// This context should have methods like IDENTIFIER() and Expr().
				if singleDeclCtx, isCorrectType := initDeclCtx.(parser.ILetSingleContext); isCorrectType {
					// Accessing components of ILetSingleContext based on grammar:
					// letSingle: typedID (EQUALS value = expr)?
					// typedID: namedID (COLON type = typeAnnotation)?;
					// namedID: name = ID;
					// Therefore, to get the ID token: singleDeclCtx.TypedID().NamedID().ID()
					// And for the expression: singleDeclCtx.GetValue()
					identAntlrToken := singleDeclCtx.TypedID().NamedID().ID() // antlr.TerminalNode for the identifier
					exprAntlrCtx := singleDeclCtx.GetValue()                  // parser.IExprContext for the expression part

					if identAntlrToken != nil && exprAntlrCtx != nil {
						identName := identAntlrToken.GetText()
						rhsVisited := v.Visit(exprAntlrCtx)
						if rhsExpr, isExpr := rhsVisited.(ast.Expr); isExpr {
							initStmt = &ast.AssignStmt{
								Lhs:    []ast.Expr{ast.NewIdent(identName)},
								TokPos: v.pos(identAntlrToken.GetSymbol()),
								Tok:    gotoken.DEFINE,
								Rhs:    []ast.Expr{rhsExpr},
							}
							processedManually = true
						} else if rhsVisited != nil {
							v.addError(fmt.Sprintf("RHS of for-loop 'let' initializer was %T, expected ast.Expr", rhsVisited), exprAntlrCtx.GetStart())
						} else {
							v.addError("RHS of for-loop 'let' initializer is missing or failed to visit", exprAntlrCtx.GetStart())
						}
					} else {
						v.addError("Malformed 'let' structure in for-loop initializer (missing IDENTIFIER or Expr component)", singleDeclCtx.GetStart())
					}
				}

				if !processedManually && initVisited != nil {
					v.addError(fmt.Sprintf("C-style for loop initialization (decl) was %T (and not a recognized direct 'let' structure), expected ast.Stmt", initVisited), initDeclCtx.GetStart())
				}
			}

			// Consolidate post-processing for initStmt from initDeclCtx:
			// 1. If it's an AssignStmt, ensure Tok is DEFINE.
			// 2. If it's a DeclStmt (var X = Y), convert to AssignStmt (X := Y).
			if assignStmt, isAssign := initStmt.(*ast.AssignStmt); isAssign {
				assignStmt.Tok = gotoken.DEFINE
			} else if declStmt, isDecl := initStmt.(*ast.DeclStmt); isDecl {
				if genDecl, isGen := declStmt.Decl.(*ast.GenDecl); isGen && genDecl.Tok == gotoken.VAR {
					if len(genDecl.Specs) == 1 {
						if valSpec, isValSpec := genDecl.Specs[0].(*ast.ValueSpec); isValSpec {
							if len(valSpec.Names) == 1 && valSpec.Values != nil && len(valSpec.Values) == 1 {
								initStmt = &ast.AssignStmt{
									Lhs:    []ast.Expr{valSpec.Names[0]},
									TokPos: genDecl.TokPos,
									Tok:    gotoken.DEFINE,
									Rhs:    []ast.Expr{valSpec.Values[0]},
								}
							}
						}
					}
				}
			}
		} else if initExprsCtx != nil {
			initVisited := v.Visit(initExprsCtx)

			if visitedStmt, ok := initVisited.(ast.Stmt); ok {
				initStmt = visitedStmt
			} else if visitedExprs, ok := initVisited.([]ast.Expr); ok {
				if len(visitedExprs) == 1 {
					singleExpr := visitedExprs[0]
					if binExpr, isBin := singleExpr.(*ast.BinaryExpr); isBin && (binExpr.Op == gotoken.ASSIGN || binExpr.Op.String() == "=") {
						initStmt = &ast.AssignStmt{
							Lhs: []ast.Expr{binExpr.X}, TokPos: binExpr.OpPos, Tok: gotoken.ASSIGN, Rhs: []ast.Expr{binExpr.Y},
						}
					} else {
						initStmt = &ast.ExprStmt{X: singleExpr}
					}
				} else if len(visitedExprs) > 1 {
					v.addError("C-style for loop initialization (exprs list) has multiple expressions. Using first.", initExprsCtx.GetStart())
					initStmt = &ast.ExprStmt{X: visitedExprs[0]}
				}
			} else if visitedExpr, ok := initVisited.(ast.Expr); ok {
				if binExpr, isBin := visitedExpr.(*ast.BinaryExpr); isBin && (binExpr.Op == gotoken.ASSIGN || binExpr.Op.String() == "=") {
					initStmt = &ast.AssignStmt{
						Lhs: []ast.Expr{binExpr.X}, TokPos: binExpr.OpPos, Tok: gotoken.ASSIGN, Rhs: []ast.Expr{binExpr.Y},
					}
				} else {
					initStmt = &ast.ExprStmt{X: visitedExpr}
				}
			} else if initVisited != nil {
				v.addError(fmt.Sprintf("C-style for loop initialization (exprs) was %T, expected ast.Stmt, ast.Expr, or []ast.Expr", initVisited), initExprsCtx.GetStart())
			}

			// Ensure an AssignStmt from exprs list also becomes DEFINE for `:=`
			if assignStmt, isAssign := initStmt.(*ast.AssignStmt); isAssign {
				assignStmt.Tok = gotoken.DEFINE
			}
		}

		// Handle condition
		var condExpr ast.Expr
		if condRuleCtx := forTrinityCtx.GetCondition(); condRuleCtx != nil {
			condVisited := v.Visit(condRuleCtx)
			if expr, ok := condVisited.(ast.Expr); ok {
				condExpr = expr
			} else if condVisited != nil {
				v.addError(fmt.Sprintf("C-style for loop condition was %T, expected ast.Expr", condVisited), condRuleCtx.GetStart())
			}
		}

		// Handle post-update
		var postStmt ast.Stmt
		if postExprsCtx := forTrinityCtx.GetPostUpdate(); postExprsCtx != nil {
			postVisited := v.Visit(postExprsCtx)
			if stmt, ok := postVisited.(ast.Stmt); ok {
				postStmt = stmt
			} else if expr, ok := postVisited.(ast.Expr); ok {
				postStmt = &ast.ExprStmt{X: expr}
			} else if postVisited != nil {
				v.addError(fmt.Sprintf("C-style for loop post-update was %T, expected ast.Stmt or ast.Expr", postVisited), postExprsCtx.GetStart())
			}
		}

		// Handle body
		var bodyStmt *ast.BlockStmt
		bodyRuleCtx := forTrinityCtx.GetBody()
		if bodyRuleCtx != nil {
			if concreteLoopBodyCtx, ok := bodyRuleCtx.(*parser.LoopBodyContext); ok {
				visitedBody := v.VisitLoopBody(concreteLoopBodyCtx)
				if bodyAst, bodyOk := visitedBody.(*ast.BlockStmt); bodyOk {
					bodyStmt = bodyAst
				} else {
					v.addError(fmt.Sprintf("C-style For loop body did not resolve to *ast.BlockStmt, got %T", visitedBody), concreteLoopBodyCtx.GetStart())
					bodyStmt = &ast.BlockStmt{Lbrace: v.pos(concreteLoopBodyCtx.GetStart()), Rbrace: v.pos(concreteLoopBodyCtx.GetStop())} // fallback
				}
			} else {
				v.addError(fmt.Sprintf("C-style For loop body was not *parser.LoopBodyContext, got %T", bodyRuleCtx), bodyRuleCtx.GetStart())
				bodyStmt = &ast.BlockStmt{Lbrace: v.pos(bodyRuleCtx.GetStart()), Rbrace: v.pos(bodyRuleCtx.GetStop())} // fallback
			}
		} else {
			v.addError("C-style For loop missing body (ILoopBodyContext is nil)", forTrinityCtx.GetStart())
			bodyStmt = &ast.BlockStmt{Lbrace: v.pos(forTrinityCtx.GetStart()), Rbrace: v.pos(forTrinityCtx.GetStop())}
		}

		// Always emit a Go C-style for loop (for init; cond; post { ... })
		return &ast.ForStmt{
			For:  v.pos(ctx.FOR().GetSymbol()),
			Init: initStmt,
			Cond: condExpr,
			Post: postStmt,
			Body: bodyStmt,
		}

	case *parser.ForInLoopContext: // This corresponds to the #ForInLoop label
		rangeStmt := &ast.RangeStmt{
			For: v.pos(ctx.FOR().GetSymbol()),
			Tok: gotoken.DEFINE,
		}

		// Iterable
		if iterableCtx := typeCtx.GetIterable(); iterableCtx != nil {
			iterableVisited := v.Visit(iterableCtx)
			if iterableExpr, ok := iterableVisited.(ast.Expr); ok {
				rangeStmt.X = iterableExpr
			} else if iterableVisited != nil {
				v.addError(fmt.Sprintf("For-in loop iterable was %T, expected ast.Expr", iterableVisited), iterableCtx.GetStart())
				rangeStmt.X = &ast.BadExpr{From: v.pos(iterableCtx.GetStart()), To: v.pos(iterableCtx.GetStop())}
			} else {
				v.addError("For-in loop iterable is missing or invalid", iterableCtx.GetStart())
				rangeStmt.X = &ast.BadExpr{From: v.pos(iterableCtx.GetStart()), To: v.pos(iterableCtx.GetStart())}
			}
		} else {
			v.addError("For-in loop missing iterable context", typeCtx.GetStart())
			rangeStmt.X = &ast.BadExpr{From: v.pos(typeCtx.GetStart()), To: v.pos(typeCtx.GetStop())}
		}

		// Loop variables
		keyToken := typeCtx.GetKey()
		valToken := typeCtx.GetVal()

		if keyToken == nil {
			v.addError("Missing key variable in for-in loop", typeCtx.GetStart())
			rangeStmt.Key = ast.NewIdent("_")
		} else {
			keyName := keyToken.GetText()
			if valToken != nil {
				valName := valToken.GetText()
				// Manuscript: for firstVar, secondVar in collection
				// Go (arrays): for index, value := range collection
				// Go (maps):   for key, value := range collection
				// Test failures imply for arrays, MS firstVar is value, secondVar is index.
				// So, Go Key (index) = MS secondVar (valName)
				// And Go Value       = MS firstVar (keyName)
				rangeStmt.Key = ast.NewIdent(valName)
				rangeStmt.Value = ast.NewIdent(keyName)
			} else {
				// Single variable case: for val in X.  Go: for _, val := range X
				rangeStmt.Key = ast.NewIdent("_")
				rangeStmt.Value = ast.NewIdent(keyName)
			}
		}

		// Body (loopBody)
		if bodyRuleCtx := typeCtx.LoopBody(); bodyRuleCtx != nil {
			if concreteLoopBodyCtx, ok := bodyRuleCtx.(*parser.LoopBodyContext); ok {
				visitedBody := v.VisitLoopBody(concreteLoopBodyCtx)
				if bodyAst, bodyOk := visitedBody.(*ast.BlockStmt); bodyOk {
					rangeStmt.Body = bodyAst
				} else {
					v.addError(fmt.Sprintf("For-in loop body did not resolve to *ast.BlockStmt, got %T", visitedBody), bodyRuleCtx.GetStart())
					rangeStmt.Body = &ast.BlockStmt{Lbrace: v.pos(bodyRuleCtx.GetStart()), Rbrace: v.pos(bodyRuleCtx.GetStop())} // fallback
				}
			} else {
				v.addError("For-in loop body was not *parser.LoopBodyContext", bodyRuleCtx.GetStart())
				rangeStmt.Body = &ast.BlockStmt{Lbrace: v.pos(bodyRuleCtx.GetStart()), Rbrace: v.pos(bodyRuleCtx.GetStop())} // fallback
			}
		} else {
			v.addError("For-in loop missing body", typeCtx.GetStart())
			rangeStmt.Body = &ast.BlockStmt{Lbrace: v.pos(typeCtx.GetStart()), Rbrace: v.pos(typeCtx.GetStop())}
		}
		return rangeStmt

	default:
		v.addError(fmt.Sprintf("Unhandled forLoopType: %T", forLoopTypeInterface), ctx.GetStart())
		return &ast.BadStmt{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
}
