package visitor

import (
	"go/ast"
	"go/token"
	"log"
	msParser "manuscript-co/manuscript/internal/parser"
)

// Marker structs for destructuring operations
// These structs are defined in codegen.go, uncomment if needed here
type ArrayDestructureMarker struct{ Elements []ast.Expr }
type ObjectDestructureMarker struct{ Properties []ast.Expr }

// VisitLetDecl handles let declarations.
// It can return a single ast.Stmt or a []ast.Stmt if the 'let' expands to multiple Go statements.
func (v *ManuscriptAstVisitor) VisitLetDecl(ctx *msParser.LetDeclContext) interface{} {
	var stmts []ast.Stmt

	if singleLetCtx := ctx.LetSingle(); singleLetCtx != nil {
		// Case: let a = 1 or let a
		// The LetSingle rule itself is: typedID EQUALS value=expr
		// However, the grammar for letDecl is: LET (singleLet | blockLet | ...);
		// And singleLet is: typedID (EQUALS value=expr)?;
		// The parser.ILetSingleContext has TypedID(), EQUALS(), and Expr()

		stmt := v.visitLetSingleAssignment(singleLetCtx) // Pass as ILetSingleContext
		if stmt != nil {
			if _, isEmpty := stmt.(*ast.EmptyStmt); !isEmpty {
				return stmt // Return single statement directly
			}
		}
		return &ast.EmptyStmt{}
	} else if blockLetCtx := ctx.LetBlock(); blockLetCtx != nil {
		// Case: let ( a = 1, b )
		letSingleAssignments := blockLetCtx.AllAssignmentExpr() // Returns []IAssignmentExprContext
		if len(letSingleAssignments) == 0 {
			// This might be 'let {}' which should be an error or no-op.
			// The grammar for blockLet is LBRACE (letSingle)* RBRACE
			// An empty block is possible.
			// Let's treat it as no statements for now, could add error if strict.
			log.Printf("VisitLetDecl: Encountered an empty let block: %s", ctx.GetText())
			return &ast.EmptyStmt{}
		}
		for _, singleAssignCtx := range letSingleAssignments { // singleAssignCtx is ILetSingleContext
			stmt := v.Visit(singleAssignCtx)
			if stmt != nil {
				if stmt, ok := stmt.(ast.Stmt); ok {
					stmts = append(stmts, stmt)
				}
			}
		}
	} else if destructuredObjCtx := ctx.LetDestructuredObj(); destructuredObjCtx != nil {
		// Case: let {a, b} = obj  OR  let {a,b}
		// Rule: LBRACE typedIDList RBRACE (EQUALS expr)?
		stmt := v.visitLetDestructuredObjAssignment(destructuredObjCtx) // Pass as ILetDestructuredObjContext
		if stmt != nil {
			if _, isEmpty := stmt.(*ast.EmptyStmt); !isEmpty {
				return stmt
			}
		}
		return &ast.EmptyStmt{}
	} else if destructuredArrayCtx := ctx.LetDestructuredArray(); destructuredArrayCtx != nil {
		// Case: let [a, b] = arr OR let [a,b]
		// Rule: LSQBR typedIDList RSQBR (EQUALS expr)?
		stmt := v.visitLetDestructuredArrayAssignment(destructuredArrayCtx) // Pass as ILetDestructuredArrayContext
		if stmt != nil {
			if _, isEmpty := stmt.(*ast.EmptyStmt); !isEmpty {
				return stmt
			}
		}
		return &ast.EmptyStmt{}
	} else {
		// This case should ideally not be hit if the grammar requires one of the above.
		v.addError("Unrecognized let declaration structure: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	if len(stmts) == 0 {
		// This can happen if a block contained only assignments that resulted in errors/EmptyStmts
		return &ast.EmptyStmt{}
	}
	if len(stmts) == 1 {
		return stmts[0]
	}
	return stmts // Return the slice of statements directly for block lets
}

// visitLetSingleAssignment handles 'let typedID = expr' or 'let typedID'
// ctx is parser.ILetSingleContext
func (v *ManuscriptAstVisitor) visitLetSingleAssignment(ctx msParser.ILetSingleContext) ast.Stmt {
	// Ensure concrete type for full access if needed, though interface should suffice for TypedID, Expr, EQUALS
	concreteCtx, ok := ctx.(*msParser.LetSingleContext)
	if !ok {
		// This would be an internal error if the parser returns something else implementing the interface.
		// For now, assume ctx provides the necessary methods like TypedID(), Expr(), EQUALS() directly.
		v.addError("Internal error: Expected *parser.LetSingleContext, got different type for ILetSingleContext", ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	if concreteCtx.TypedID() == nil {
		v.addError("Missing pattern in single let assignment: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	patternRaw := v.Visit(concreteCtx.TypedID())
	if patternRaw == nil {
		v.addError("Failed to process pattern in single let assignment: "+concreteCtx.TypedID().GetText(), concreteCtx.TypedID().GetStart())
		return &ast.EmptyStmt{}
	}

	ident, ok := patternRaw.(*ast.Ident)
	if !ok {
		v.addError("Pattern in single let assignment did not evaluate to an identifier: "+concreteCtx.TypedID().GetText(), concreteCtx.TypedID().GetStart())
		return &ast.EmptyStmt{}
	}
	lhsExprs := []ast.Expr{ident}

	// Check for assignment (RHS)
	if concreteCtx.EQUALS() != nil && concreteCtx.Expr() != nil {
		valueVisited := v.Visit(concreteCtx.Expr())
		if valueVisited == nil {
			v.addError("Failed to process value in single let assignment: "+concreteCtx.Expr().GetText(), concreteCtx.Expr().GetStart())
			return &ast.EmptyStmt{}
		}

		sourceExpr, okVal := valueVisited.(ast.Expr)
		if !okVal {
			v.addError("Value in single let assignment did not evaluate to an expression: "+concreteCtx.Expr().GetText(), concreteCtx.Expr().GetStart())
			return &ast.EmptyStmt{}
		}
		rhsExprs := []ast.Expr{sourceExpr}

		return &ast.AssignStmt{
			Lhs: lhsExprs,
			Tok: token.DEFINE,
			Rhs: rhsExprs,
		}
	} else if concreteCtx.EQUALS() != nil && concreteCtx.Expr() == nil {
		// 'let x =' is a syntax error, parser should catch this. If not, error here.
		v.addError("Incomplete assignment in single let: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	} else {
		// No EQUALS, so it's a var declaration: 'let x'
		return &ast.DeclStmt{
			Decl: &ast.GenDecl{
				Tok: token.VAR,
				Specs: []ast.Spec{
					&ast.ValueSpec{
						Names: []*ast.Ident{ident},
						// Type: nil, // Type can be added here if VisitTypedID also returns type info
						// Values: nil,
					},
				},
			},
		}
	}
}

// visitLetDestructuredObjAssignment handles 'let {id1, id2} = expr' or 'let {id1, id2}'
// ctx is parser.ILetDestructuredObjContext
func (v *ManuscriptAstVisitor) visitLetDestructuredObjAssignment(ctx msParser.ILetDestructuredObjContext) ast.Stmt {
	concreteCtx, ok := ctx.(*msParser.LetDestructuredObjContext)
	if !ok {
		v.addError("Internal error: Expected *parser.LetDestructuredObjContext", ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	if concreteCtx.TypedIDList() == nil {
		v.addError("Object destructuring pattern is malformed (missing TypedIDList): "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	var lhsExprs []ast.Expr
	typedIDs := concreteCtx.TypedIDList().AllTypedID() // Returns []ITypedIDContext

	if len(typedIDs) == 0 { // Handles 'let {}'
		log.Printf("VisitLetDestructuredObjAssignment: Empty object destructuring pattern for '%s'", ctx.GetText())
		v.addError("Object destructuring pattern is empty: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	for _, typedIDInterface := range typedIDs {
		idVisited := v.Visit(typedIDInterface.(*msParser.TypedIDContext)) // typedIDInterface is parser.ITypedIDContext
		if idVisited == nil {
			v.addError("Failed to process identifier in object destructuring: "+typedIDInterface.GetText(), typedIDInterface.GetStart())
			return &ast.EmptyStmt{}
		}
		ident, isIdent := idVisited.(*ast.Ident)
		if !isIdent {
			v.addError("Identifier in object destructuring is not a valid ast.Ident: "+typedIDInterface.GetText(), typedIDInterface.GetStart())
			return &ast.EmptyStmt{}
		}
		lhsExprs = append(lhsExprs, ident)
	}

	if len(lhsExprs) == 0 {
		v.addError("Object destructuring pattern resulted in no LHS expressions: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	// According to linter errors and context struct, LetDestructuredObjContext does not have EQUALS() or Expr().
	// This means this rule path is only for VAR declarations like 'let {a, b}'.
	// Assignment logic 'let {a,b} = expr' must be handled by a different parser rule if supported.

	// Create "var a, b" declaration
	var names []*ast.Ident
	for _, expr := range lhsExprs {
		if ident, isIdent := expr.(*ast.Ident); isIdent {
			names = append(names, ident)
		} else {
			v.addError("Expected identifier for var declaration in object destructuring (internal error)", ctx.GetStart())
			return &ast.EmptyStmt{}
		}
	}
	// len(names) == 0 should have been caught by len(typedIDs) == 0 check earlier
	return &ast.DeclStmt{
		Decl: &ast.GenDecl{
			Tok:   token.VAR,
			Specs: []ast.Spec{&ast.ValueSpec{Names: names}},
		},
	}
}

// visitLetDestructuredArrayAssignment handles 'let [id1, id2] = expr' or 'let [id1, id2]'
// ctx is parser.ILetDestructuredArrayContext
func (v *ManuscriptAstVisitor) visitLetDestructuredArrayAssignment(ctx msParser.ILetDestructuredArrayContext) ast.Stmt {
	concreteCtx, ok := ctx.(*msParser.LetDestructuredArrayContext)
	if !ok {
		v.addError("Internal error: Expected *parser.LetDestructuredArrayContext", ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	if concreteCtx.TypedIDList() == nil {
		v.addError("Array destructuring pattern is malformed (missing TypedIDList): "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	var lhsExprs []ast.Expr
	typedIDs := concreteCtx.TypedIDList().AllTypedID()

	if len(typedIDs) == 0 { // Handles 'let []'
		log.Printf("VisitLetDestructuredArrayAssignment: Empty array destructuring pattern for '%s'", ctx.GetText())
		v.addError("Array destructuring pattern is empty: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	for _, typedIDInterface := range typedIDs {
		idVisited := v.Visit(typedIDInterface.(*msParser.TypedIDContext))
		if idVisited == nil {
			v.addError("Failed to process identifier in array destructuring: "+typedIDInterface.GetText(), typedIDInterface.GetStart())
			return &ast.EmptyStmt{}
		}
		ident, isIdent := idVisited.(*ast.Ident)
		if !isIdent {
			v.addError("Identifier in array destructuring is not a valid ast.Ident: "+typedIDInterface.GetText(), typedIDInterface.GetStart())
			return &ast.EmptyStmt{}
		}
		lhsExprs = append(lhsExprs, ident)
	}

	if len(lhsExprs) == 0 {
		v.addError("Array destructuring pattern resulted in no LHS expressions: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	// According to linter errors and context struct, LetDestructuredArrayContext does not have EQUALS() or Expr().
	// This means this rule path is only for VAR declarations like 'let [a, b]'.
	// Assignment logic 'let [a,b] = expr' must be handled by a different parser rule if supported.

	// Create "var a, b" declaration
	var names []*ast.Ident
	for _, expr := range lhsExprs {
		if ident, isIdent := expr.(*ast.Ident); isIdent {
			names = append(names, ident)
		} else {
			v.addError("Expected identifier for var declaration in array destructuring (internal error)", ctx.GetStart())
			return &ast.EmptyStmt{}
		}
	}
	// len(names) == 0 should be caught by len(typedIDs) == 0 check
	return &ast.DeclStmt{
		Decl: &ast.GenDecl{
			Tok:   token.VAR,
			Specs: []ast.Spec{&ast.ValueSpec{Names: names}},
		},
	}
}

// VisitTypedID handles a typed identifier, returning an *ast.Ident.
// Type information is currently ignored for let LHS.
func (v *ManuscriptAstVisitor) VisitTypedID(ctx *msParser.TypedIDContext) interface{} {
	// The interface parser.ITypedIDContext has NamedID() and TypeAnnotation()
	// The concrete type is *parser.TypedIDContext

	// It's good practice to check if NamedID() itself is nil before calling methods on it.
	if ctx.NamedID() == nil {
		v.addError("TypedID has no NamedID component: "+ctx.GetText(), ctx.GetStart())
		return nil
	}
	if ctx.NamedID().ID() == nil {
		v.addError("NamedID component has no ID token: "+ctx.GetText(), ctx.GetStart())
		return nil
	}

	// Assuming NamedID().ID() returns an antlr.TerminalNode which has GetSymbol()
	idToken := ctx.NamedID().ID().GetSymbol()
	idName := idToken.GetText()

	// Type information can be accessed via ctx.TypeAnnotation() if needed in the future.
	// For 'let' LHS, types are usually not directly part of the Go 'var' or ':=' LHS.
	// If type inference or explicit typing on LHS were supported for 'let', this would be the place.

	return ast.NewIdent(idName)
}

// VisitNamedID handles a named identifier, returning an *ast.Ident.
// This is part of the ANTLR generated visitor interface if NamedID is a parser rule.
// We provide a concrete implementation.
func (v *ManuscriptAstVisitor) VisitNamedID(ctx *msParser.NamedIDContext) interface{} {
	// Interface parser.INamedIDContext has ID() antlr.TerminalNode
	// Concrete type is *parser.NamedIDContext
	if ctx.ID() == nil {
		v.addError("NamedID has no ID token: "+ctx.GetText(), ctx.GetStart())
		return nil
	}
	idToken := ctx.ID().GetSymbol()
	idName := idToken.GetText()
	return ast.NewIdent(idName)
}
