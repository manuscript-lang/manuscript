package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"
)

// Marker structs for destructuring operations
// These structs are defined in codegen.go, uncomment if needed here
type ArrayDestructureMarker struct{ Elements []ast.Expr }
type ObjectDestructureMarker struct{ Properties []ast.Expr }

// VisitLetDecl handles let declarations.
// let pattern = expr
// It can return a single ast.Stmt or a []ast.Stmt if the 'let' expands to multiple Go statements.
func (v *ManuscriptAstVisitor) VisitLetDecl(ctx *parser.LetDeclContext) interface{} {
	log.Printf("VisitLetDecl: Called for '%s'", ctx.GetText())

	assignments := ctx.AllLetAssignment()
	if len(assignments) == 0 {
		log.Printf("VisitLetDecl: No assignments found in let declaration '%s'", ctx.GetText())
		return &ast.EmptyStmt{} // or nil
	}

	// Handle single assignment
	if len(assignments) == 1 {
		// VisitLetAssignment should return an ast.Stmt (AssignStmt or DeclStmt)
		return v.VisitLetAssignment(assignments[0].(*parser.LetAssignmentContext))
	}

	// Handle multiple assignments: collect all statements
	var stmts []ast.Stmt
	for _, assignCtx := range assignments {
		assignItem := v.VisitLetAssignment(assignCtx.(*parser.LetAssignmentContext))
		if stmt, ok := assignItem.(ast.Stmt); ok && stmt != nil {
			// Check if it's an EmptyStmt and skip if so, to avoid empty lines from problematic sub-assignments
			if _, isEmpty := stmt.(*ast.EmptyStmt); !isEmpty {
				stmts = append(stmts, stmt)
			}
		} else if assignItem != nil {
			log.Printf("VisitLetDecl: Expected ast.Stmt from VisitLetAssignment, got %T for '%s'", assignItem, assignCtx.GetText())
			// Optionally, append a BadStmt or skip
		}
	}

	if len(stmts) == 0 {
		log.Printf("VisitLetDecl: No valid statements processed for '%s'", ctx.GetText())
		return &ast.EmptyStmt{} // or nil
	}

	// If, after processing, there's only one effective statement, return it directly.
	if len(stmts) == 1 {
		return stmts[0]
	}

	return stmts // Return the slice of statements directly
}

// VisitLetAssignment handles the individual assignments in a let declaration
func (v *ManuscriptAstVisitor) VisitLetAssignment(ctx *parser.LetAssignmentContext) interface{} {
	// Visit the pattern (LHS of the assignment)
	patternRaw := v.Visit(ctx.LetPattern())
	if patternRaw == nil {
		log.Printf("VisitLetAssignment: Pattern visit failed for '%s'", ctx.LetPattern().GetText())
		return nil
	}

	var lhsExprs []ast.Expr
	isDestructuring := false

	switch p := patternRaw.(type) {
	case ast.Expr: // Single variable
		lhsExprs = []ast.Expr{p}
	case ArrayDestructureMarker:
		lhsExprs = p.Elements
		isDestructuring = true
		if len(lhsExprs) == 0 {
			log.Printf("VisitLetAssignment: Array destructuring pattern is empty for '%s'", ctx.GetPattern().GetText())
			// Depending on language semantics, this might be an error or no-op
			return nil // Or an empty DeclStmt / AssignStmt
		}
	case ObjectDestructureMarker:
		lhsExprs = p.Properties
		isDestructuring = true
		if len(lhsExprs) == 0 {
			log.Printf("VisitLetAssignment: Object destructuring pattern is empty for '%s'", ctx.GetPattern().GetText())
			// Depending on language semantics, this might be an error or no-op
			return nil // Or an empty DeclStmt / AssignStmt
		}
	default:
		log.Printf("VisitLetAssignment: Unhandled pattern type %T for '%s'", patternRaw, ctx.GetPattern().GetText())
		return nil
	}

	// If there's a value, visit the expression (RHS of the assignment)
	if ctx.GetValue() != nil {
		valueVisited := v.Visit(ctx.GetValue())
		if valueVisited == nil {
			log.Printf("VisitLetAssignment: Value visit failed for '%s'", ctx.GetValue().GetText())
			return nil
		}

		sourceExpr, ok := valueVisited.(ast.Expr)
		if !ok {
			log.Printf("VisitLetAssignment: Expected ast.Expr from value visit, got %T for '%s'", valueVisited, ctx.GetValue().GetText())
			return nil
		}

		var rhsExprs []ast.Expr
		if isDestructuring {
			switch patternRaw.(type) {
			case ArrayDestructureMarker:
				// e.g., a, b := source[0], source[1]
				for i := range lhsExprs {
					rhsExprs = append(rhsExprs, &ast.IndexExpr{
						X:     sourceExpr,
						Index: &ast.BasicLit{Kind: token.INT, Value: fmt.Sprintf("%d", i)},
					})
				}
			case ObjectDestructureMarker:
				// e.g., a, b := source.a, source.b
				for _, lhsItem := range lhsExprs {
					if ident, ok := lhsItem.(*ast.Ident); ok {
						rhsExprs = append(rhsExprs, &ast.SelectorExpr{
							X:   sourceExpr,
							Sel: ast.NewIdent(ident.Name), // Assumes direct mapping of names
						})
					} else {
						log.Printf("VisitLetAssignment: Expected *ast.Ident in LHS for object destructuring, got %T", lhsItem)
						return nil
					}
				}
			}
		} else {
			// Single assignment: a := val
			rhsExprs = []ast.Expr{sourceExpr}
		}

		if len(lhsExprs) == 0 && len(rhsExprs) == 0 && isDestructuring {
			// Handles 'let [] = arr' or 'let {} = obj' as a no-op assignment if patterns were empty.
			// This might need to be an error depending on strictness.
			log.Printf("VisitLetAssignment: Empty destructuring with assignment for '%s', creating no-op", ctx.GetText())
			return &ast.EmptyStmt{} // Or nil, or specific error
		}

		// Ensure LHS and RHS have same number of elements for assignment if destructuring
		// For non-destructuring, len(lhs)=1, len(rhs)=1
		if isDestructuring && len(lhsExprs) != len(rhsExprs) {
			// This is a simplified assumption. Go handles this with specific rules.
			// For now, we expect Manuscript to ensure this or we'll have a mismatch.
			// A more robust solution would involve tuple assignment concepts or error reporting.
			log.Printf("VisitLetAssignment: Mismatch in LHS (%d) and RHS (%d) elements for destructuring assignment for '%s'. This may lead to incorrect Go code.", len(lhsExprs), len(rhsExprs), ctx.GetText())
			// Potentially truncate or pad, but for now, proceed with what we have.
		}

		return &ast.AssignStmt{
			Lhs: lhsExprs,
			Tok: token.DEFINE, // := operator
			Rhs: rhsExprs,
		}
	} else {
		// No value provided, create "var x, y, z" declaration
		var names []*ast.Ident
		for _, expr := range lhsExprs {
			if ident, ok := expr.(*ast.Ident); ok {
				names = append(names, ident)
			} else {
				log.Printf("VisitLetAssignment: Expected *ast.Ident for var declaration, got %T", expr)
				return nil // Should not happen if pattern visitors are correct
			}
		}
		if len(names) == 0 {
			log.Printf("VisitLetAssignment: No identifiers for var declaration for pattern '%s'", ctx.GetPattern().GetText())
			return &ast.EmptyStmt{} // or nil, effectively a no-op
		}
		return &ast.DeclStmt{
			Decl: &ast.GenDecl{
				Tok: token.VAR,
				Specs: []ast.Spec{
					&ast.ValueSpec{
						Names: names, // Handles multiple names
					},
				},
			},
		}
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
		return v.VisitArrayPattn(ctx.ArrayPattn().(*parser.ArrayPattnContext))
	}

	// Handle object patterns - convert to multiple variables
	if ctx.ObjectPattn() != nil {
		return v.VisitObjectPattn(ctx.ObjectPattn().(*parser.ObjectPattnContext))
	}

	return nil
}

// VisitArrayPattn handles array destructuring in let declarations.
// For example: let [a, b] = someArray
func (v *ManuscriptAstVisitor) VisitArrayPattn(ctx *parser.ArrayPattnContext) interface{} {
	log.Printf("VisitArrayPattn: Called for '%s'", ctx.GetText())
	var lhs []ast.Expr
	for _, idNode := range ctx.AllID() {
		idName := idNode.GetText()
		lhs = append(lhs, ast.NewIdent(idName))
	}
	// If lhs is empty, it means it was 'let [] = ...' which might be an error or an empty destructuring.
	// For now, we'll return an empty slice, and let VisitLetAssignment handle it.
	if len(lhs) == 0 {
		log.Printf("VisitArrayPattn: No identifiers found in array pattern '%s'", ctx.GetText())
	}
	return ArrayDestructureMarker{Elements: lhs}
}

// VisitObjectPattn handles object destructuring in let declarations.
// For example: let {x, y} = someObject
func (v *ManuscriptAstVisitor) VisitObjectPattn(ctx *parser.ObjectPattnContext) interface{} {
	log.Printf("VisitObjectPattn: Called for '%s'", ctx.GetText())
	var lhs []ast.Expr
	for _, idNode := range ctx.AllID() {
		idName := idNode.GetText()
		lhs = append(lhs, ast.NewIdent(idName))
	}

	// If lhs is empty, it means 'let {} = ...'
	if len(lhs) == 0 {
		log.Printf("VisitObjectPattn: No identifiers found in object pattern '%s'", ctx.GetText())
	}
	return ObjectDestructureMarker{Properties: lhs}
}
