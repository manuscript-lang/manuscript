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

		// Inline patternExpr logic
		patternCtx := caseClauseCtx.GetPattern()
		var patternAST ast.Expr
		if patternCtx == nil {
			patternAST = &ast.BadExpr{}
		} else {
			visited := v.Visit(patternCtx)
			if expr, ok := visited.(ast.Expr); ok {
				patternAST = expr
			} else {
				v.addError("Case pattern did not resolve to ast.Expr: "+patternCtx.GetText(), patternCtx.GetStart())
				patternAST = &ast.BadExpr{From: v.pos(patternCtx.GetStart()), To: v.pos(patternCtx.GetStop())}
			}
		}

		// Inline caseBody logic
		var caseBody []ast.Stmt
		visited := v.VisitCaseClause(caseClauseCtx)
		if stmts, ok := visited.([]ast.Stmt); ok {
			caseBody = stmts
		} else {
			caseBody = []ast.Stmt{&ast.EmptyStmt{}}
		}

		astClauses = append(astClauses, &ast.CaseClause{
			List: []ast.Expr{patternAST},
			Body: caseBody,
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
		Body: &ast.BlockStmt{List: iifeBodyStmts, Lbrace: v.pos(ctx.MATCH().GetSymbol())},
	}

	callExpr := &ast.CallExpr{
		Fun: iifeFuncLit,
	}
	if ctx.MATCH() != nil && ctx.MATCH().GetSymbol() != nil {
		callExpr.Lparen = v.pos(ctx.MATCH().GetSymbol())
	} else {
		callExpr.Lparen = v.pos(ctx.GetStart())
	}

	if ctx.RBRACE() != nil && ctx.RBRACE().GetSymbol() != nil {
		callExpr.Rparen = v.pos(ctx.RBRACE().GetSymbol())
	} else {
		v.addError("Match expression missing RBRACE token in AST context", ctx.GetStop())
		callExpr.Rparen = v.pos(ctx.GetStop())
	}
	return callExpr
}

// VisitCaseClause implements the antlr visitor pattern for case clauses
func (v *ManuscriptAstVisitor) VisitCaseClause(ctx *parser.CaseClauseContext) interface{} {
	if ctx == nil {
		return []ast.Stmt{&ast.EmptyStmt{}}
	}
	resultVarName := "__match_result"
	if ctx.GetResultExpr() != nil {
		return []ast.Stmt{
			&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{v.exprOrBad(ctx.GetResultExpr())}},
		}
	}
	if ctx.GetResultBlock() != nil {
		visitedBlock := v.Visit(ctx.GetResultBlock())
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
			v.addError("Case result block must end with an expression to produce a value.", ctx.GetResultBlock().GetStop())
		} else {
			v.addError("Case result block did not resolve to *ast.BlockStmt: "+ctx.GetResultBlock().GetText(), ctx.GetResultBlock().GetStart())
		}
		return []ast.Stmt{
			&ast.AssignStmt{Lhs: []ast.Expr{ast.NewIdent(resultVarName)}, Tok: token.ASSIGN, Rhs: []ast.Expr{&ast.BadExpr{From: v.pos(ctx.GetResultBlock().GetStart()), To: v.pos(ctx.GetResultBlock().GetStop())}}},
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
