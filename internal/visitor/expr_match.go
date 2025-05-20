package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitMatchExpr(ctx *parser.MatchExprContext) interface{} {
	matchValueExprVisited := v.Visit(ctx.Expr())
	matchValueAST, ok := matchValueExprVisited.(ast.Expr)
	if !ok {
		v.addError("Match expression value did not resolve to ast.Expr", ctx.Expr().GetStart())
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

		allExprs := caseClauseCtx.AllExpr()
		var patternAST ast.Expr
		if len(allExprs) > 0 {
			visited := v.Visit(allExprs[0])
			if expr, ok := visited.(ast.Expr); ok {
				patternAST = expr
			} else {
				v.addError("Case pattern did not resolve to ast.Expr: "+allExprs[0].GetText(), allExprs[0].GetStart())
				patternAST = &ast.BadExpr{From: v.pos(allExprs[0].GetStart()), To: v.pos(allExprs[0].GetStop())}
			}
		} else {
			patternAST = &ast.BadExpr{}
		}

		var caseBody []ast.Stmt
		if len(allExprs) > 1 {
			// case pattern: expr COLON expr
			caseBody = []ast.Stmt{
				&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{v.exprOrBad(allExprs[1])}},
			}
		} else if caseClauseCtx.CodeBlock() != nil {
			visitedBlock := v.Visit(caseClauseCtx.CodeBlock())
			if blockStmt, ok := visitedBlock.(*ast.BlockStmt); ok {
				stmts := blockStmt.List
				if len(stmts) > 0 {
					if exprStmt, isExprStmt := stmts[len(stmts)-1].(*ast.ExprStmt); isExprStmt {
						body := make([]ast.Stmt, len(stmts))
						copy(body, stmts[:len(stmts)-1])
						body[len(stmts)-1] = &ast.AssignStmt{
							Lhs: []ast.Expr{ast.NewIdent(resultVarName)},
							Tok: token.ASSIGN,
							Rhs: []ast.Expr{exprStmt.X},
						}
						body = append(body, &ast.BranchStmt{Tok: token.BREAK})
						caseBody = body
					} else {
						caseBody = append(stmts, &ast.BranchStmt{Tok: token.BREAK})
					}
				} else {
					caseBody = []ast.Stmt{&ast.BranchStmt{Tok: token.BREAK}}
				}
			} else {
				v.addError("Case result block did not resolve to *ast.BlockStmt: "+caseClauseCtx.CodeBlock().GetText(), caseClauseCtx.CodeBlock().GetStart())
				caseBody = []ast.Stmt{&ast.BranchStmt{Tok: token.BREAK}}
			}
		} else {
			v.addError("Malformed case clause (missing result expression or block): "+caseClauseCtx.GetText(), caseClauseCtx.GetStart())
			caseBody = []ast.Stmt{&ast.BranchStmt{Tok: token.BREAK}}
		}

		astClauses = append(astClauses, &ast.CaseClause{
			List: []ast.Expr{patternAST},
			Body: caseBody,
		})
	}

	// Handle default clause if present
	if ctx.DefaultClause() != nil {
		defaultCtx := ctx.DefaultClause()
		var defaultBody []ast.Stmt
		if defaultCtx.Expr() != nil {
			defaultBody = []ast.Stmt{
				&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{v.exprOrBad(defaultCtx.Expr())}},
				&ast.BranchStmt{Tok: token.BREAK},
			}
		} else if defaultCtx.CodeBlock() != nil {
			visitedBlock := v.Visit(defaultCtx.CodeBlock())
			if blockStmt, ok := visitedBlock.(*ast.BlockStmt); ok {
				stmts := blockStmt.List
				if len(stmts) > 0 {
					if exprStmt, isExprStmt := stmts[len(stmts)-1].(*ast.ExprStmt); isExprStmt {
						body := make([]ast.Stmt, len(stmts))
						copy(body, stmts[:len(stmts)-1])
						body[len(stmts)-1] = &ast.AssignStmt{
							Lhs: []ast.Expr{ast.NewIdent(resultVarName)},
							Tok: token.ASSIGN,
							Rhs: []ast.Expr{exprStmt.X},
						}
						body = append(body, &ast.BranchStmt{Tok: token.BREAK})
						defaultBody = body
					} else {
						defaultBody = append(stmts, &ast.BranchStmt{Tok: token.BREAK})
					}
				} else {
					defaultBody = []ast.Stmt{&ast.BranchStmt{Tok: token.BREAK}}
				}
			} else {
				v.addError("Default result block did not resolve to *ast.BlockStmt: "+defaultCtx.CodeBlock().GetText(), defaultCtx.CodeBlock().GetStart())
				defaultBody = []ast.Stmt{&ast.BranchStmt{Tok: token.BREAK}}
			}
		} else {
			v.addError("Malformed default clause (missing result expression or block): "+defaultCtx.GetText(), defaultCtx.GetStart())
			defaultBody = []ast.Stmt{&ast.BranchStmt{Tok: token.BREAK}}
		}
		astClauses = append(astClauses, &ast.CaseClause{
			List: nil,
			Body: defaultBody,
		})
	}

	declResultVar := &ast.DeclStmt{
		Decl: &ast.GenDecl{
			Tok: token.VAR,
			Specs: []ast.Spec{
				&ast.ValueSpec{
					Names: []*ast.Ident{ast.NewIdent(resultVarName)},
					Type:  ast.NewIdent("interface{}"),
				},
			},
		},
	}

	switchStmt := &ast.SwitchStmt{
		Tag:  matchValueAST,
		Body: &ast.BlockStmt{List: astClauses},
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
			Params: &ast.FieldList{},
			Results: &ast.FieldList{
				List: []*ast.Field{{Type: ast.NewIdent("interface{}")}},
			},
		},
		Body: &ast.BlockStmt{List: iifeBodyStmts},
	}

	callExpr := &ast.CallExpr{
		Fun: iifeFuncLit,
	}
	return callExpr
}

// VisitCaseClause implements the antlr visitor pattern for case clauses
func (v *ManuscriptAstVisitor) VisitCaseClause(ctx *parser.CaseClauseContext) interface{} {
	if ctx == nil {
		return []ast.Stmt{&ast.EmptyStmt{}}
	}
	resultVarName := "__match_result"
	allExprs := ctx.AllExpr()
	if len(allExprs) > 1 {
		// case pattern: expr COLON expr
		return []ast.Stmt{
			&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{v.exprOrBad(allExprs[1])}},
		}
	}
	if ctx.CodeBlock() != nil {
		visitedBlock := v.Visit(ctx.CodeBlock())
		if blockStmt, ok := visitedBlock.(*ast.BlockStmt); ok {
			stmts := blockStmt.List
			if len(stmts) > 0 {
				if exprStmt, isExprStmt := stmts[len(stmts)-1].(*ast.ExprStmt); isExprStmt {
					body := make([]ast.Stmt, len(stmts))
					copy(body, stmts[:len(stmts)-1])
					body[len(stmts)-1] = &ast.AssignStmt{
						Lhs: []ast.Expr{ast.NewIdent(resultVarName)},
						Tok: token.ASSIGN,
						Rhs: []ast.Expr{exprStmt.X},
					}
					return body
				}
				return stmts
			}
			v.addError("Case result block must end with an expression to produce a value.", ctx.CodeBlock().GetStop())
		} else {
			v.addError("Case result block did not resolve to *ast.BlockStmt: "+ctx.CodeBlock().GetText(), ctx.CodeBlock().GetStart())
		}
		return []ast.Stmt{
			&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{&ast.BadExpr{From: v.pos(ctx.CodeBlock().GetStart()), To: v.pos(ctx.CodeBlock().GetStop())}}},
		}
	}
	v.addError("Malformed case clause (missing result expression or block): "+ctx.GetText(), ctx.GetStart())
	return []ast.Stmt{
		&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{&ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}}},
	}
}

// exprOrBad returns ast.Expr for a context, or BadExpr if not valid
func (v *ManuscriptAstVisitor) exprOrBad(exprCtx parser.IExprContext) ast.Expr {
	visited := v.Visit(exprCtx)
	if e, ok := visited.(ast.Expr); ok {
		return e
	}
	v.addError("Case result expression did not resolve to ast.Expr: "+exprCtx.GetText(), exprCtx.GetStart())
	return &ast.BadExpr{From: v.pos(exprCtx.GetStart()), To: v.pos(exprCtx.GetStop())}
}
