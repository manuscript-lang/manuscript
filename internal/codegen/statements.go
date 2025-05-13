package codegen

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"
)

// TODO: Implement other Visit methods based on the action plan (Phase 2 onwards)
// e.g., VisitProgramItem, VisitStmt, VisitExprStmt, VisitLetDecl, VisitAssignmentExpr, etc.

// VisitStmt handles different kinds of statements.
func (v *ManuscriptAstVisitor) VisitStmt(ctx *parser.StmtContext) interface{} {
	log.Printf("VisitStmt: Called for '%s'", ctx.GetText()) // Log entry

	if ctx.LetDecl() != nil {
		log.Printf("VisitStmt: Found LetDecl: %s", ctx.LetDecl().GetText())
		return v.VisitLetDecl(ctx.LetDecl().(*parser.LetDeclContext))
	}

	if exprStmtCtx := ctx.ExprStmt(); exprStmtCtx != nil {
		log.Printf("VisitStmt: Found ExprStmt: %s", exprStmtCtx.GetText())
		if concreteExprStmtCtx, ok := exprStmtCtx.(*parser.ExprStmtContext); ok {
			log.Printf("VisitStmt: Asserted ExprStmtContext, calling VisitExprStmt for '%s'", concreteExprStmtCtx.GetText())
			return v.VisitExprStmt(concreteExprStmtCtx)
		} else {
			log.Printf("VisitStmt: Failed to assert ExprStmtContext type for '%s'", exprStmtCtx.GetText())
			return nil
		}
	}

	if ctx.SEMICOLON() != nil {
		log.Printf("VisitStmt: Found SEMICOLON (empty statement): %s", ctx.GetText())
		return nil
	}

	log.Printf("VisitStmt: Unhandled statement type for '%s'", ctx.GetText())
	return nil // Return nil if unhandled
}

// VisitExprStmt processes an expression statement.
func (v *ManuscriptAstVisitor) VisitExprStmt(ctx *parser.ExprStmtContext) interface{} {
	// Explicitly visit only the expression part, ignore the semicolon child
	visitedExprRaw := v.Visit(ctx.Expr()) // Visit the core expression
	// Add detailed logging here:
	log.Printf("VisitExprStmt: Visited ctx.Expr() for '%s', got type %T, value: %+v", ctx.Expr().GetText(), visitedExprRaw, visitedExprRaw)

	if expr, ok := visitedExprRaw.(ast.Expr); ok {
		// Wrap the resulting expression in an ast.ExprStmt
		log.Printf("VisitExprStmt: Successfully asserted ast.Expr for '%s'", ctx.Expr().GetText()) // Log success
		return &ast.ExprStmt{X: expr}
	}

	// Log if the assertion failed
	log.Printf("VisitExprStmt: Failed to assert ast.Expr for '%s'. Got type %T instead.", ctx.Expr().GetText(), visitedExprRaw)
	return nil // Return nil if the expression visit failed
}

// VisitLetAssignment handles the individual assignments in a let declaration
func (v *ManuscriptAstVisitor) VisitLetAssignment(ctx *parser.LetAssignmentContext) interface{} {
	// Visit the pattern (LHS of the assignment)
	patternRaw := v.Visit(ctx.LetPattern())
	if patternRaw == nil {
		return nil
	}

	// For now, we'll only handle simple patterns (identifiers)
	var lhs []ast.Expr

	switch pattern := patternRaw.(type) {
	case ast.Expr:
		lhs = []ast.Expr{pattern}
	case []ast.Expr:
		lhs = pattern
	default:
		return nil
	}

	// If there's a value, visit the expression (RHS of the assignment)
	var rhs []ast.Expr
	if ctx.GetValue() != nil {
		valueRaw := v.Visit(ctx.GetValue())

		if valueRaw == nil {
			return nil
		}

		switch value := valueRaw.(type) {
		case ast.Expr:
			rhs = []ast.Expr{value}
		case []ast.Expr:
			rhs = value
		default:
			return nil
		}
	} else {
		// If no value provided, create "var x" declaration
		return &ast.DeclStmt{
			Decl: &ast.GenDecl{
				Tok: token.VAR,
				Specs: []ast.Spec{
					&ast.ValueSpec{
						Names: []*ast.Ident{lhs[0].(*ast.Ident)},
					},
				},
			},
		}
	}

	// Create the Go-style ":=" statement (short variable declaration)
	return &ast.AssignStmt{
		Lhs: lhs,
		Tok: token.DEFINE, // ":=" operator
		Rhs: rhs,
	}
}

// VisitLetPattern handles the left side of a let declaration
func (v *ManuscriptAstVisitor) VisitLetPattern(ctx *parser.LetPatternContext) interface{} {
	// Handle simple identifiers
	if ctx.ID() != nil {
		idToken := ctx.ID().GetSymbol()
		idName := idToken.GetText()
		return ast.NewIdent(idName)
	}

	// Handle array patterns - convert to multiple variables
	if ctx.ArrayPattn() != nil {
		// TODO: Implement array destructuring
		return nil
	}

	// Handle object patterns - convert to multiple variables
	if ctx.ObjectPattn() != nil {
		// TODO: Implement object destructuring
		return nil
	}

	return nil
}
