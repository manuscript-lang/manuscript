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
	assignments := ctx.AllLetAssignment()
	if len(assignments) == 0 {
		v.addError("No assignments found in let declaration: "+ctx.GetText(), ctx.GetStart())
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
			v.addError("Internal error: Expected statement from let assignment processing for: "+assignCtx.GetText(), assignCtx.GetStart())
			// Optionally, append a BadStmt or skip
		}
	}

	if len(stmts) == 0 {
		// This could be a valid scenario if all assignments were empty destructures.
		// However, individual empty destructures are reported as errors below.
		// If all assignments lead to errors and thus no statements, this path might be taken.
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
		v.addError("Failed to process pattern in let assignment: "+ctx.LetPattern().GetText(), ctx.LetPattern().GetStart())
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
			v.addError("Array destructuring pattern is empty: "+ctx.GetPattern().GetText(), ctx.GetPattern().GetStart())
			return nil // Or an empty DeclStmt / AssignStmt
		}
	case ObjectDestructureMarker:
		lhsExprs = p.Properties
		isDestructuring = true
		if len(lhsExprs) == 0 {
			v.addError("Object destructuring pattern is empty: "+ctx.GetPattern().GetText(), ctx.GetPattern().GetStart())
			return nil // Or an empty DeclStmt / AssignStmt
		}
	default:
		v.addError("Unhandled pattern type in let assignment: "+ctx.GetPattern().GetText(), ctx.GetPattern().GetStart())
		return nil
	}

	// If there's a value, visit the expression (RHS of the assignment)
	if ctx.GetValue() != nil {
		valueVisited := v.Visit(ctx.GetValue())
		if valueVisited == nil {
			v.addError("Failed to process value in let assignment: "+ctx.GetValue().GetText(), ctx.GetValue().GetStart())
			return nil
		}

		sourceExpr, ok := valueVisited.(ast.Expr)
		if !ok {
			v.addError("Value in let assignment did not evaluate to an expression: "+ctx.GetValue().GetText(), ctx.GetValue().GetStart())
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
						v.addError("Expected identifier in left-hand side for object destructuring property name", ctx.GetPattern().GetStart()) // Token might not be perfect, points to whole pattern
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
			v.addError(fmt.Sprintf("Mismatch in number of elements for destructuring assignment (LHS: %d, RHS: %d) for: %s", len(lhsExprs), len(rhsExprs), ctx.GetText()), ctx.GetStart())
			// Potentially truncate or pad, but for now, proceed with what we have, which might be an error later.
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
				v.addError("Expected identifier for var declaration without assignment", ctx.GetPattern().GetStart()) // Token points to whole pattern
				return nil                                                                                            // Should not happen if pattern visitors are correct
			}
		}
		if len(names) == 0 && len(lhsExprs) > 0 { // Only error if original pattern had items but none were valid idents
			v.addError("No valid identifiers found for var declaration from pattern: "+ctx.GetPattern().GetText(), ctx.GetPattern().GetStart())
			return &ast.EmptyStmt{} // or nil, effectively a no-op
		}
		if len(names) == 0 && len(lhsExprs) == 0 { // Case: let [] or let {} without assignment
			// This is an empty pattern, already errored if isDestructuring was true and lhsExprs was empty.
			// If it reaches here, it implies a non-destructuring empty pattern, which is odd.
			// For safety, let's add an error if `names` is empty and it wasn't an explicit empty destructuring error from before.
			if !isDestructuring { // if it was destructuring, it would have been caught by len(lhsExprs)==0 checks earlier.
				v.addError("No identifiers provided for var declaration: "+ctx.GetPattern().GetText(), ctx.GetPattern().GetStart())
			}
			return &ast.EmptyStmt{}
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
	var lhs []ast.Expr
	for _, idNode := range ctx.AllID() {
		idName := idNode.GetText()
		lhs = append(lhs, ast.NewIdent(idName))
	}
	// If lhs is empty, it means it was 'let [] = ...' which might be an error or an empty destructuring.
	// For now, we'll return an empty slice, and let VisitLetAssignment handle it.
	if len(lhs) == 0 {
		log.Printf("VisitArrayPattn: No identifiers found in array pattern '%s'", ctx.GetText()) // Kept as log for now, as LetAssignment handles empty lhs
	}
	return ArrayDestructureMarker{Elements: lhs}
}

// VisitObjectPattn handles object destructuring in let declarations.
// For example: let {x, y} = someObject
func (v *ManuscriptAstVisitor) VisitObjectPattn(ctx *parser.ObjectPattnContext) interface{} {
	var lhs []ast.Expr
	for _, idNode := range ctx.AllID() {
		idName := idNode.GetText()
		lhs = append(lhs, ast.NewIdent(idName))
	}

	// If lhs is empty, it means 'let {} = ...'
	if len(lhs) == 0 {
		log.Printf("VisitObjectPattn: No identifiers found in object pattern '%s'", ctx.GetText()) // Kept as log for now
	}
	return ObjectDestructureMarker{Properties: lhs}
}
