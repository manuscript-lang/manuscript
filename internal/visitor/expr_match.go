package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitMatchExpr(ctx *parser.MatchExprContext) interface{} {
	matchValueExprVisited := v.Visit(ctx.GetValueToMatch())
	matchValueAST, ok := matchValueExprVisited.(ast.Expr)
	if !ok {
		v.addError("Match expression value did not resolve to ast.Expr", ctx.GetValueToMatch().GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	resultVarName := "__match_result"
	astClauses := []ast.Stmt{}

	for _, caseClauseInterface := range ctx.AllCaseClause() {
		caseClauseCtx, castOk := caseClauseInterface.(*parser.CaseClauseContext)
		if !castOk {

			v.addError(fmt.Sprintf("Internal error: expected CaseClauseContext, got %T", caseClauseInterface), ctx.GetStart())
			continue
		}

		var currentPatternAST ast.Expr
		var currentCaseBody []ast.Stmt

		if caseClauseCtx.GetPattern() == nil {
			v.addError(fmt.Sprintf("Malformed case clause (missing pattern): %s", caseClauseCtx.GetText()), caseClauseCtx.GetStart())
			badPattern := &ast.BadExpr{From: v.pos(caseClauseCtx.GetStart()), To: v.pos(caseClauseCtx.GetStart())}
			astClauses = append(astClauses, &ast.CaseClause{List: []ast.Expr{badPattern}, Body: []ast.Stmt{&ast.EmptyStmt{}}})
			continue
		}

		patternCtx := caseClauseCtx.GetPattern()
		patternExprVisited := v.Visit(patternCtx)
		pAST, pOk := patternExprVisited.(ast.Expr)
		if !pOk {
			v.addError("Case pattern did not resolve to ast.Expr: "+patternCtx.GetText(), patternCtx.GetStart())
			currentPatternAST = &ast.BadExpr{From: v.pos(patternCtx.GetStart()), To: v.pos(patternCtx.GetStop())}
		} else {
			currentPatternAST = pAST
		}

		if resultExprCtx := caseClauseCtx.GetResultExpr(); resultExprCtx != nil {
			resultExprVisited := v.Visit(resultExprCtx)
			rAST, rOk := resultExprVisited.(ast.Expr)
			if !rOk {
				v.addError("Case result expression did not resolve to ast.Expr: "+resultExprCtx.GetText(), resultExprCtx.GetStart())
				rAST = &ast.BadExpr{From: v.pos(resultExprCtx.GetStart()), To: v.pos(resultExprCtx.GetStop())}
			}
			currentCaseBody = []ast.Stmt{
				&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{rAST}},
			}
		} else if resultBlockCtx := caseClauseCtx.GetResultBlock(); resultBlockCtx != nil {
			visitedBlock := v.Visit(resultBlockCtx)
			blockStmt, bOk := visitedBlock.(*ast.BlockStmt)
			if !bOk {
				v.addError("Case result block did not resolve to *ast.BlockStmt: "+resultBlockCtx.GetText(), resultBlockCtx.GetStart())
				badResultVal := &ast.BadExpr{From: v.pos(resultBlockCtx.GetStart()), To: v.pos(resultBlockCtx.GetStop())}
				currentCaseBody = []ast.Stmt{
					&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{badResultVal}},
				}
			} else {
				stmtsInBlock := blockStmt.List
				if len(stmtsInBlock) > 0 {
					lastStmtInBlock := stmtsInBlock[len(stmtsInBlock)-1]
					if exprStmt, isExprStmt := lastStmtInBlock.(*ast.ExprStmt); isExprStmt {
						currentCaseBody = make([]ast.Stmt, len(stmtsInBlock))
						if len(stmtsInBlock) > 1 {
							copy(currentCaseBody, stmtsInBlock[:len(stmtsInBlock)-1])
						}
						currentCaseBody[len(stmtsInBlock)-1] = &ast.AssignStmt{
							Lhs: []ast.Expr{ast.NewIdent(resultVarName)},
							Tok: token.ASSIGN,
							Rhs: []ast.Expr{exprStmt.X},
						}
					} else {
						v.addError("Case result block must end with an expression to produce a value.", resultBlockCtx.GetStop())
						badResultVal := &ast.BadExpr{From: v.pos(resultBlockCtx.GetStart()), To: v.pos(resultBlockCtx.GetStop())}
						currentCaseBody = []ast.Stmt{
							&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{badResultVal}},
						}
					}
				} else {
					v.addError("Case result block is empty and cannot produce a value.", resultBlockCtx.GetStart())
					badResultVal := &ast.BadExpr{From: v.pos(resultBlockCtx.GetStart()), To: v.pos(resultBlockCtx.GetStop())}
					currentCaseBody = []ast.Stmt{
						&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{badResultVal}},
					}
				}
			}
		} else {
			v.addError(fmt.Sprintf("Malformed case clause (missing result expression or block): %s", caseClauseCtx.GetText()), caseClauseCtx.GetStart())
			badResultVal := &ast.BadExpr{From: v.pos(caseClauseCtx.GetStart()), To: v.pos(caseClauseCtx.GetStop())}
			currentCaseBody = []ast.Stmt{
				&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{badResultVal}},
			}
		}

		if currentPatternAST == nil {
			currentPatternAST = &ast.BadExpr{From: v.pos(caseClauseCtx.GetStart()), To: v.pos(caseClauseCtx.GetStart())}
		}
		if currentCaseBody == nil {
			currentCaseBody = []ast.Stmt{&ast.EmptyStmt{}}
		}

		astClauses = append(astClauses, &ast.CaseClause{
			List: []ast.Expr{currentPatternAST},
			Body: currentCaseBody,
		})
	}

	// IIFE structure:
	// var __match_result interface{}
	declResultVar := &ast.DeclStmt{
		Decl: &ast.GenDecl{
			Tok: token.VAR,
			Specs: []ast.Spec{
				&ast.ValueSpec{
					Names: []*ast.Ident{ast.NewIdent(resultVarName)},
					Type:  ast.NewIdent("interface{}"), // Assuming result can be any type
				},
			},
		},
	}

	switchStmt := &ast.SwitchStmt{
		Tag: matchValueAST,
	}
	if ctx.LBRACE() != nil && ctx.LBRACE().GetSymbol() != nil {
		switchStmt.Body = &ast.BlockStmt{List: astClauses, Lbrace: v.pos(ctx.LBRACE().GetSymbol())}
	} else {
		v.addError("Match expression missing LBRACE token in AST context", ctx.GetStart())
		switchStmt.Body = &ast.BlockStmt{List: astClauses}
	}

	if ctx.MATCH() != nil && ctx.MATCH().GetSymbol() != nil {
		switchStmt.Switch = v.pos(ctx.MATCH().GetSymbol())
	} else {
		v.addError("Match expression missing MATCH token in AST context", ctx.GetStart())
		// Potentially use ctx.GetStart() for switchStmt.Switch if a position is absolutely needed
	}

	returnResultVar := &ast.ReturnStmt{
		Results: []ast.Expr{ast.NewIdent(resultVarName)},
	}

	iifeBodyStmts := []ast.Stmt{
		declResultVar,
		switchStmt,
		returnResultVar,
	}

	iifeFuncLit := &ast.FuncLit{
		Type: &ast.FuncType{
			Params: &ast.FieldList{}, // No params for this IIFE
			Results: &ast.FieldList{
				List: []*ast.Field{{Type: ast.NewIdent("interface{}")}}, // IIFE returns single interface{} value
			},
		},
		Body: &ast.BlockStmt{List: iifeBodyStmts, Lbrace: v.pos(ctx.MATCH().GetSymbol())},
	}

	callExpr := &ast.CallExpr{
		Fun: iifeFuncLit,
	}
	if ctx.MATCH() != nil && ctx.MATCH().GetSymbol() != nil { // Position of the call can be start of match
		callExpr.Lparen = v.pos(ctx.MATCH().GetSymbol())
	} else {
		// Fallback Lparen position if MATCH token is missing
		callExpr.Lparen = v.pos(ctx.GetStart())
	}

	if ctx.RBRACE() != nil && ctx.RBRACE().GetSymbol() != nil {
		callExpr.Rparen = v.pos(ctx.RBRACE().GetSymbol())
	} else {
		v.addError("Match expression missing RBRACE token in AST context", ctx.GetStop())
		// Fallback Rparen position if RBRACE token is missing
		callExpr.Rparen = v.pos(ctx.GetStop())
	}
	return callExpr
}

// VisitCaseClause handles individual case clauses in a match expression
func (v *ManuscriptAstVisitor) VisitCaseClause(ctx *parser.CaseClauseContext) interface{} {
	v.addError("Internal warning: VisitCaseClause should not be called directly.", ctx.GetStart())

	var patternVisited interface{}
	if pNode := ctx.GetPattern(); pNode != nil {
		patternVisited = v.Visit(pNode)
	} else {
		patternVisited = &ast.BadExpr{
			From: v.pos(ctx.GetStart()),
			To:   v.pos(ctx.GetStart()),
		}
	}

	var resultVisited interface{}
	if rExpr := ctx.GetResultExpr(); rExpr != nil {
		resultVisited = v.Visit(rExpr)
	} else if rBlock := ctx.GetResultBlock(); rBlock != nil {
		resultVisited = v.Visit(rBlock)
	} else {
		resultVisited = &ast.BadExpr{
			From: v.pos(ctx.GetStart()),
			To:   v.pos(ctx.GetStop()),
		}
	}

	return map[string]interface{}{
		"pattern": patternVisited,
		"result":  resultVisited,
	}
}
