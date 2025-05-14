package visitor

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"
)

// VisitMatchExpr translates match expressions into Go switch statements
func (v *ManuscriptAstVisitor) VisitMatchExpr(ctx *parser.MatchExprContext) interface{} {
	// First, get the value we're matching against
	valueExpr := v.Visit(ctx.GetValueToMatch())
	matchValue, ok := valueExpr.(ast.Expr)
	if !ok {
		log.Printf("Error: Match value is not an ast.Expr. Got: %T", valueExpr)
		return &ast.BadExpr{}
	}

	// Now handle all the case clauses
	cases := ctx.AllCaseClause()
	if len(cases) == 0 {
		// Empty match expression, rare but handle it
		log.Printf("Warning: Empty match expression with no cases")
		return &ast.BadExpr{}
	}

	// Create a switch statement
	switchStmt := &ast.SwitchStmt{
		Body: &ast.BlockStmt{
			List: []ast.Stmt{},
		},
	}

	// Special optimization: if we're matching against a type, create a type switch
	// This is a heuristic that could be improved with more semantic analysis
	isTypeSwitch := false
	typeAssertion := &ast.TypeAssertExpr{
		X:    matchValue,
		Type: nil, // Will be filled in later for type switches
	}

	// Process each case clause
	for _, caseCtx := range cases {
		caseClause := caseCtx.(*parser.CaseClauseContext)

		// Get the pattern (case condition) and result (case body)
		patternExpr := v.Visit(caseClause.GetPattern())
		pattern, ok := patternExpr.(ast.Expr)
		if !ok {
			log.Printf("Warning: Case pattern is not an ast.Expr. Got: %T", patternExpr)
			continue
		}

		resultExpr := v.Visit(caseClause.GetResult())
		result, ok := resultExpr.(ast.Expr)
		if !ok {
			log.Printf("Warning: Case result is not an ast.Expr. Got: %T", resultExpr)
			continue
		}

		// Create comparison expression for the case
		// In Go, we'll use x == pattern for most cases
		var caseBody *ast.BlockStmt

		// For simple patterns, just create a return statement with the result
		caseBody = &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.ReturnStmt{
					Results: []ast.Expr{result},
				},
			},
		}

		// Create the case clause and add it to the switch statement
		switchCase := &ast.CaseClause{
			List: []ast.Expr{pattern},
			Body: caseBody.List,
		}

		switchStmt.Body.List = append(switchStmt.Body.List, switchCase)
	}

	// If we're doing a type switch, we need an expression to switch on
	if isTypeSwitch {
		// Create a type switch statement instead
		typeSwitchStmt := &ast.TypeSwitchStmt{
			Assign: &ast.AssignStmt{
				Lhs: []ast.Expr{ast.NewIdent("_")},
				Tok: token.DEFINE,
				Rhs: []ast.Expr{typeAssertion},
			},
			Body: switchStmt.Body,
		}

		// Wrap the type switch in a function literal
		fnLit := &ast.FuncLit{
			Type: &ast.FuncType{
				Results: &ast.FieldList{
					List: []*ast.Field{
						{
							Type: ast.NewIdent("interface{}"),
						},
					},
				},
			},
			Body: &ast.BlockStmt{
				List: []ast.Stmt{typeSwitchStmt},
			},
		}

		// Return the function literal call
		return &ast.CallExpr{
			Fun: fnLit,
		}
	} else {
		// For a regular switch, use the match value as the tag
		switchStmt.Tag = matchValue

		// Wrap the switch in a function literal
		fnLit := &ast.FuncLit{
			Type: &ast.FuncType{
				Results: &ast.FieldList{
					List: []*ast.Field{
						{
							Type: ast.NewIdent("interface{}"),
						},
					},
				},
			},
			Body: &ast.BlockStmt{
				List: []ast.Stmt{switchStmt},
			},
		}

		// Return the function literal call
		return &ast.CallExpr{
			Fun: fnLit,
		}
	}
}

// VisitCaseClause handles individual case clauses in a match expression
func (v *ManuscriptAstVisitor) VisitCaseClause(ctx *parser.CaseClauseContext) interface{} {
	// This is actually handled directly in VisitMatchExpr to allow building
	// the full switch statement. This method is just a placeholder.
	log.Printf("Warning: VisitCaseClause called directly, should be handled by VisitMatchExpr")

	// For completeness, return the pattern and result if called directly
	patternExpr := v.Visit(ctx.GetPattern())
	resultExpr := v.Visit(ctx.GetResult())

	// Return both parts so the caller could use them if needed
	return map[string]interface{}{
		"pattern": patternExpr,
		"result":  resultExpr,
	}
}
