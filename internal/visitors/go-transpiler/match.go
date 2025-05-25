package transpiler

import (
	"go/ast"
	"go/token"
	mast "manuscript-co/manuscript/internal/ast"
)

// VisitMatchExpr transpiles match expressions
func (t *GoTranspiler) VisitMatchExpr(node *mast.MatchExpr) ast.Node {
	if node == nil {
		return &ast.Ident{Name: "nil"}
	}

	// Get the value to match against
	var matchValue ast.Expr
	if node.Expr != nil {
		valueResult := t.Visit(node.Expr)
		if expr, ok := valueResult.(ast.Expr); ok {
			matchValue = expr
		} else {
			matchValue = &ast.Ident{Name: "nil"}
		}
	} else {
		matchValue = &ast.Ident{Name: "nil"}
	}

	resultVarName := "__match_result"

	// Build case clauses for the switch statement
	var switchCases []ast.Stmt
	for _, caseClause := range node.Cases {
		caseStmt := t.VisitCaseClause(&caseClause)
		if caseClauseStmt, ok := caseStmt.(*ast.CaseClause); ok {
			switchCases = append(switchCases, caseClauseStmt)
		}
	}

	// Handle default clause if present
	if node.Default != nil {
		defaultStmt := t.VisitDefaultClause(node.Default)
		if defaultClauseStmt, ok := defaultStmt.(*ast.CaseClause); ok {
			switchCases = append(switchCases, defaultClauseStmt)
		}
	}

	// Create the result variable declaration
	declResultVar := &ast.DeclStmt{
		Decl: &ast.GenDecl{
			Tok: token.VAR,
			Specs: []ast.Spec{
				&ast.ValueSpec{
					Names: []*ast.Ident{{Name: resultVarName}},
					Type:  &ast.Ident{Name: "interface{}"},
				},
			},
		},
	}

	// Create the switch statement
	switchStmt := &ast.SwitchStmt{
		Tag:  matchValue,
		Body: &ast.BlockStmt{List: switchCases},
	}

	// Return the result variable
	returnStmt := &ast.ReturnStmt{
		Results: []ast.Expr{&ast.Ident{Name: resultVarName}},
	}

	// Create the IIFE (Immediately Invoked Function Expression)
	iifeBodyStmts := []ast.Stmt{
		declResultVar,
		switchStmt,
		returnStmt,
	}

	iifeFuncLit := &ast.FuncLit{
		Type: &ast.FuncType{
			Params: &ast.FieldList{},
			Results: &ast.FieldList{
				List: []*ast.Field{{Type: &ast.Ident{Name: "interface{}"}}},
			},
		},
		Body: &ast.BlockStmt{List: iifeBodyStmts},
	}

	// Return the function call expression
	return &ast.CallExpr{
		Fun: iifeFuncLit,
	}
}

// VisitCaseClause transpiles case clauses
func (t *GoTranspiler) VisitCaseClause(node *mast.CaseClause) ast.Node {
	if node == nil {
		return &ast.CaseClause{List: []ast.Expr{}, Body: []ast.Stmt{}}
	}

	resultVarName := "__match_result"

	// Get the pattern value
	var values []ast.Expr
	if node.Pattern != nil {
		valueResult := t.Visit(node.Pattern)
		if expr, ok := valueResult.(ast.Expr); ok {
			values = append(values, expr)
		}
	}

	// Handle the body based on its type
	var body []ast.Stmt
	if node.Body != nil {
		switch caseBody := node.Body.(type) {
		case *mast.CaseExpr:
			// Simple expression case - assign to result variable, NO break statement
			if caseBody.Expr != nil {
				exprResult := t.Visit(caseBody.Expr)
				if expr, ok := exprResult.(ast.Expr); ok {
					body = []ast.Stmt{
						&ast.AssignStmt{
							Lhs: []ast.Expr{&ast.Ident{Name: resultVarName}},
							Tok: token.ASSIGN,
							Rhs: []ast.Expr{expr},
						},
					}
				}
			}
		case *mast.CaseBlock:
			// Block case - need to handle the last statement as a return value, WITH break
			if caseBody.Block != nil {
				blockResult := t.Visit(caseBody.Block)
				if blockStmt, ok := blockResult.(*ast.BlockStmt); ok {
					stmts := blockStmt.List
					if len(stmts) > 0 {
						// If the last statement is an expression statement, convert it to assignment
						if exprStmt, isExprStmt := stmts[len(stmts)-1].(*ast.ExprStmt); isExprStmt {
							bodyStmts := make([]ast.Stmt, len(stmts))
							copy(bodyStmts, stmts[:len(stmts)-1])
							bodyStmts[len(stmts)-1] = &ast.AssignStmt{
								Lhs: []ast.Expr{&ast.Ident{Name: resultVarName}},
								Tok: token.ASSIGN,
								Rhs: []ast.Expr{exprStmt.X},
							}
							body = append(bodyStmts, &ast.BranchStmt{Tok: token.BREAK})
						} else {
							body = append(stmts, &ast.BranchStmt{Tok: token.BREAK})
						}
					} else {
						body = []ast.Stmt{&ast.BranchStmt{Tok: token.BREAK}}
					}
				}
			}
		}
	}

	return &ast.CaseClause{
		List: values,
		Body: body,
	}
}

// VisitDefaultClause transpiles default clauses
func (t *GoTranspiler) VisitDefaultClause(node *mast.DefaultClause) ast.Node {
	if node == nil {
		return &ast.CaseClause{List: nil, Body: []ast.Stmt{}}
	}

	resultVarName := "__match_result"

	// Handle the body based on its type
	var body []ast.Stmt
	if node.Body != nil {
		switch caseBody := node.Body.(type) {
		case *mast.CaseExpr:
			// Simple expression case - assign to result variable, NO break statement
			if caseBody.Expr != nil {
				exprResult := t.Visit(caseBody.Expr)
				if expr, ok := exprResult.(ast.Expr); ok {
					body = []ast.Stmt{
						&ast.AssignStmt{
							Lhs: []ast.Expr{&ast.Ident{Name: resultVarName}},
							Tok: token.ASSIGN,
							Rhs: []ast.Expr{expr},
						},
					}
				}
			}
		case *mast.CaseBlock:
			// Block case - need to handle the last statement as a return value, WITH break
			if caseBody.Block != nil {
				blockResult := t.Visit(caseBody.Block)
				if blockStmt, ok := blockResult.(*ast.BlockStmt); ok {
					stmts := blockStmt.List
					if len(stmts) > 0 {
						// If the last statement is an expression statement, convert it to assignment
						if exprStmt, isExprStmt := stmts[len(stmts)-1].(*ast.ExprStmt); isExprStmt {
							bodyStmts := make([]ast.Stmt, len(stmts))
							copy(bodyStmts, stmts[:len(stmts)-1])
							bodyStmts[len(stmts)-1] = &ast.AssignStmt{
								Lhs: []ast.Expr{&ast.Ident{Name: resultVarName}},
								Tok: token.ASSIGN,
								Rhs: []ast.Expr{exprStmt.X},
							}
							body = append(bodyStmts, &ast.BranchStmt{Tok: token.BREAK})
						} else {
							body = append(stmts, &ast.BranchStmt{Tok: token.BREAK})
						}
					} else {
						body = []ast.Stmt{&ast.BranchStmt{Tok: token.BREAK}}
					}
				}
			}
		}
	}

	return &ast.CaseClause{
		List: nil, // nil means default case
		Body: body,
	}
}

// VisitCaseExpr transpiles case expressions
func (t *GoTranspiler) VisitCaseExpr(node *mast.CaseExpr) ast.Node {
	if node == nil || node.Expr == nil {
		return &ast.Ident{Name: "nil"}
	}

	return t.Visit(node.Expr)
}

// VisitCaseBlock transpiles case blocks
func (t *GoTranspiler) VisitCaseBlock(node *mast.CaseBlock) ast.Node {
	if node == nil {
		return &ast.BlockStmt{List: []ast.Stmt{}}
	}

	if node.Block != nil {
		return t.Visit(node.Block)
	}

	return &ast.BlockStmt{List: []ast.Stmt{}}
}
