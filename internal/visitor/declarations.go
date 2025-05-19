package visitor

import (
	"go/ast"
	"go/token"
	msParser "manuscript-co/manuscript/internal/parser"
	"strconv"
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
		stmt := v.visitLetSingleAssignment(singleLetCtx)
		if stmt != nil {
			if _, isEmpty := stmt.(*ast.EmptyStmt); !isEmpty {
				return stmt
			}
		}
		return &ast.EmptyStmt{}
	} else if blockLetCtx := ctx.LetBlock(); blockLetCtx != nil {
		blockItems := blockLetCtx.AllLetBlockItem()
		if len(blockItems) == 0 {

			return &ast.EmptyStmt{}
		}
		for _, itemCtx := range blockItems {
			visitedItem := v.Visit(itemCtx)
			if visitedItem != nil {
				if individualStmts, ok := visitedItem.([]ast.Stmt); ok {
					stmts = append(stmts, individualStmts...)
				} else {
					v.addError("Let block item did not resolve to a slice of statements: "+itemCtx.GetText(), itemCtx.GetStart())
				}
			}
		}
	} else if destructuredObjCtx := ctx.LetDestructuredObj(); destructuredObjCtx != nil {
		stmt := v.visitLetDestructuredObjAssignment(destructuredObjCtx)
		if stmt != nil {
			if _, isEmpty := stmt.(*ast.EmptyStmt); !isEmpty {
				return stmt
			}
		}
		return &ast.EmptyStmt{}
	} else if destructuredArrayCtx := ctx.LetDestructuredArray(); destructuredArrayCtx != nil {
		stmt := v.visitLetDestructuredArrayAssignment(destructuredArrayCtx)
		if stmt != nil {
			if _, isEmpty := stmt.(*ast.EmptyStmt); !isEmpty {
				return stmt
			}
		}
		return &ast.EmptyStmt{}
	} else {
		v.addError("Unrecognized let declaration structure: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	if len(stmts) == 0 {
		// This path is mainly for blockLet. If it's empty or all items failed, return EmptyStmt.
		return &ast.EmptyStmt{}
	}

	// If stmts has items (from blockLet), return them.
	// If only one statement, return it directly. Otherwise, return the slice.
	// Callers like VisitStmt (for a statement list) or VisitProgramItem (for top-level) need to handle []ast.Stmt.
	if len(stmts) == 1 {
		return stmts[0]
	}
	return stmts
}

// visitLetSingleAssignment handles 'let typedID = expr' or 'let typedID'
// ctx is parser.ILetSingleContext
func (v *ManuscriptAstVisitor) visitLetSingleAssignment(ctx msParser.ILetSingleContext) ast.Stmt {
	concreteCtx, ok := ctx.(*msParser.LetSingleContext)
	if !ok {
		v.addError("Internal error: Expected *parser.LetSingleContext", ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	if concreteCtx.TypedID() == nil {
		v.addError("Missing pattern in single let assignment: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	patternRaw := v.Visit(concreteCtx.TypedID())
	if patternRaw == nil {
		v.addError("Failed to process pattern: "+concreteCtx.TypedID().GetText(), concreteCtx.TypedID().GetStart())
		return &ast.EmptyStmt{}
	}

	ident, ok := patternRaw.(*ast.Ident)
	if !ok {
		v.addError("Pattern did not evaluate to an identifier: "+concreteCtx.TypedID().GetText(), concreteCtx.TypedID().GetStart())
		return &ast.EmptyStmt{}
	}
	lhsExprs := []ast.Expr{ident}

	// Get type information if available
	var typeName string
	typedIDCtx, typedIDOk := concreteCtx.TypedID().(*msParser.TypedIDContext)
	if typedIDOk && typedIDCtx.TypeAnnotation() != nil {
		// Extract the type name
		typeText := typedIDCtx.TypeAnnotation().GetText()
		typeName = typeText
	}

	// Check for assignment (RHS)
	if concreteCtx.EQUALS() != nil && concreteCtx.Expr() != nil {
		valueVisited := v.Visit(concreteCtx.Expr())
		if valueVisited == nil {
			v.addError("Failed to process value: "+concreteCtx.Expr().GetText(), concreteCtx.Expr().GetStart())
			return &ast.EmptyStmt{}
		}

		sourceExpr, okVal := valueVisited.(ast.Expr)
		if !okVal {
			v.addError("Value did not evaluate to an expression: "+concreteCtx.Expr().GetText(), concreteCtx.Expr().GetStart())
			return &ast.EmptyStmt{}
		}

		// If we have a type and the expression is an object literal, convert it to a struct initialization
		if typeName != "" && concreteCtx.Expr().GetText()[0] == '{' {
			// Check if the source is a map literal (from object literal)
			if compositeLit, isCompositeLit := sourceExpr.(*ast.CompositeLit); isCompositeLit {
				if mapType, isMapType := compositeLit.Type.(*ast.MapType); isMapType {
					if mapType.Key != nil && mapType.Key.(*ast.Ident).Name == "string" &&
						mapType.Value != nil && mapType.Value.(*ast.Ident).Name == "interface{}" {
						// This is a map[string]interface{} from object literal
						// Convert it to a struct initialization
						structType := ast.NewIdent(typeName)

						// Create a new set of elements with identifiers as keys instead of string literals
						newElts := make([]ast.Expr, 0, len(compositeLit.Elts))
						for _, elt := range compositeLit.Elts {
							if keyVal, isKeyVal := elt.(*ast.KeyValueExpr); isKeyVal {
								if strLit, isStrLit := keyVal.Key.(*ast.BasicLit); isStrLit && strLit.Kind == token.STRING {
									// Convert the string key (e.g., "id") to an identifier key (e.g., id)
									// First, unquote the string
									fieldName, err := strconv.Unquote(strLit.Value)
									if err != nil {
										v.addError("Failed to unquote struct field name: "+strLit.Value, ctx.GetStart())
										continue
									}

									// Create a new KeyValueExpr with the identifier as the key
									newKeyVal := &ast.KeyValueExpr{
										Key:   ast.NewIdent(fieldName),
										Value: keyVal.Value,
									}
									newElts = append(newElts, newKeyVal)
								} else {
									// Not a string literal key, just keep as is
									newElts = append(newElts, keyVal)
								}
							} else {
								// Not a key-value pair, just keep as is
								newElts = append(newElts, elt)
							}
						}

						// Create a struct composite literal with the converted elements
						sourceExpr = &ast.CompositeLit{
							Type: structType,
							Elts: newElts,
						}
					}
				}
			}
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
		v.addError("Object destructuring pattern is malformed: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	var lhsIdents []*ast.Ident
	typedIDListCtx := concreteCtx.TypedIDList().(*msParser.TypedIDListContext)
	for _, typedIDInterface := range typedIDListCtx.AllTypedID() {
		idVisited := v.Visit(typedIDInterface)
		if ident, isIdent := idVisited.(*ast.Ident); isIdent {
			lhsIdents = append(lhsIdents, ident)
		} else {
			v.addError("Identifier in object destructuring is not valid: "+typedIDInterface.GetText(), typedIDInterface.GetStart())
			return &ast.EmptyStmt{}
		}
	}

	if len(lhsIdents) == 0 {
		v.addError("Object destructuring pattern resulted in no LHS: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	// This is 'let {a,b} = expr'
	if concreteCtx.EQUALS() != nil && concreteCtx.Expr() != nil {
		rhsVisited := v.Visit(concreteCtx.Expr())
		rhsExpr, okExpr := rhsVisited.(ast.Expr)
		if !okExpr {
			v.addError("RHS of object destructuring is not an expression: "+concreteCtx.Expr().GetText(), concreteCtx.Expr().GetStart())
			return &ast.EmptyStmt{}
		}

		// Generate:
		// __val := rhsExpr
		// ident1 := __val.ident1
		// ident2 := __val.ident2
		// ...
		var generatedStmts []ast.Stmt
		tempVarIdent := ast.NewIdent("__val" + v.nextTempVarCounter())

		// __val := rhsExpr
		generatedStmts = append(generatedStmts, &ast.AssignStmt{
			Lhs: []ast.Expr{tempVarIdent},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{rhsExpr},
		})

		for _, ident := range lhsIdents {
			generatedStmts = append(generatedStmts, &ast.AssignStmt{
				Lhs: []ast.Expr{ast.NewIdent(ident.Name)}, // Create new ident for LHS to avoid sharing
				Tok: token.DEFINE,
				Rhs: []ast.Expr{&ast.SelectorExpr{X: tempVarIdent, Sel: ast.NewIdent(ident.Name)}},
			})
		}
		return &ast.BlockStmt{List: generatedStmts}

	} else if concreteCtx.EQUALS() != nil && concreteCtx.Expr() == nil {
		v.addError("Incomplete assignment in object destructuring: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	} else {
		// No EQUALS, so it's a var declaration: 'let {x, y}'
		// Create "var x, y"
		return &ast.DeclStmt{
			Decl: &ast.GenDecl{
				Tok:   token.VAR,
				Specs: []ast.Spec{&ast.ValueSpec{Names: lhsIdents}},
			},
		}
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
		v.addError("Array destructuring pattern is malformed: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	var lhsIdents []*ast.Ident
	typedIDListCtx := concreteCtx.TypedIDList().(*msParser.TypedIDListContext)
	for _, typedIDInterface := range typedIDListCtx.AllTypedID() {
		idVisited := v.Visit(typedIDInterface)
		if ident, isIdent := idVisited.(*ast.Ident); isIdent {
			lhsIdents = append(lhsIdents, ident)
		} else {
			v.addError("Identifier in array destructuring is not valid: "+typedIDInterface.GetText(), typedIDInterface.GetStart())
			return &ast.EmptyStmt{}
		}
	}

	if len(lhsIdents) == 0 {
		v.addError("Array destructuring pattern resulted in no LHS: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	if concreteCtx.EQUALS() != nil && concreteCtx.Expr() != nil {
		rhsVisited := v.Visit(concreteCtx.Expr())
		rhsExpr, okExpr := rhsVisited.(ast.Expr)
		if !okExpr {
			v.addError("RHS of array destructuring is not an expression: "+concreteCtx.Expr().GetText(), concreteCtx.Expr().GetStart())
			return &ast.EmptyStmt{}
		}

		var generatedStmts []ast.Stmt
		tempVarIdent := ast.NewIdent("__val" + v.nextTempVarCounter())

		generatedStmts = append(generatedStmts, &ast.AssignStmt{
			Lhs: []ast.Expr{tempVarIdent},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{rhsExpr},
		})

		for i, ident := range lhsIdents {
			generatedStmts = append(generatedStmts, &ast.AssignStmt{
				Lhs: []ast.Expr{ast.NewIdent(ident.Name)},
				Tok: token.DEFINE,
				Rhs: []ast.Expr{&ast.IndexExpr{X: tempVarIdent, Index: &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(i)}}},
			})
		}
		return &ast.BlockStmt{List: generatedStmts}

	} else if concreteCtx.EQUALS() != nil && concreteCtx.Expr() == nil {
		v.addError("Incomplete assignment in array destructuring: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	} else {
		return &ast.DeclStmt{
			Decl: &ast.GenDecl{
				Tok:   token.VAR,
				Specs: []ast.Spec{&ast.ValueSpec{Names: lhsIdents}},
			},
		}
	}
}

// VisitTypedID handles a typed identifier, returning an *ast.Ident.
// Type information is currently ignored for let LHS.
func (v *ManuscriptAstVisitor) VisitTypedID(ctx *msParser.TypedIDContext) interface{} {
	if ctx.NamedID() != nil {
		return v.Visit(ctx.NamedID())
	}
	v.addError("TypedID does not have a NamedID: "+ctx.GetText(), ctx.GetStart())
	return nil
}

// VisitNamedID handles a named identifier, returning an *ast.Ident.
// This is part of the ANTLR generated visitor interface if NamedID is a parser rule.
// We provide a concrete implementation.
func (v *ManuscriptAstVisitor) VisitNamedID(ctx *msParser.NamedIDContext) interface{} {
	if ctx.ID() != nil {
		return ast.NewIdent(ctx.ID().GetText())
	}
	v.addError("NamedID does not have an ID: "+ctx.GetText(), ctx.GetStart())
	return nil
}

// VisitTypedIDList if it's missing and helps.
// For now, assuming AllTypedID() returns ITypedIDContext and Visit(ITypedIDContext) returns *ast.Ident.
func (v *ManuscriptAstVisitor) VisitTypedIDList(ctx *msParser.TypedIDListContext) interface{} {
	var idents []*ast.Ident
	for _, typedIDCtx := range ctx.AllTypedID() {
		visitedIdent := v.Visit(typedIDCtx)
		if ident, ok := visitedIdent.(*ast.Ident); ok {
			idents = append(idents, ident)
		} else {
			v.addError("Item in TypedIDList did not resolve to an identifier: "+typedIDCtx.GetText(), typedIDCtx.GetStart())
			// Potentially return partial list or nil
		}
	}
	return idents
}

// Ensure ManuscriptAstVisitor has tempVarCount and nextTempVarCounter method
// This usually means modifying the struct definition in visitor.go
// and adding the method in a relevant file (e.g., visitor.go or helpers.go).
// For now, this file won't contain the struct def.

// VisitLetBlockItemSingle handles: lhsTypedId = typedID EQUALS rhsExpr = expr
func (v *ManuscriptAstVisitor) VisitLetBlockItemSingle(ctx *msParser.LetBlockItemSingleContext) interface{} {
	var stmts []ast.Stmt
	lhsVisited := v.Visit(ctx.GetLhsTypedId())
	lhsIdent, okLHS := lhsVisited.(*ast.Ident)
	if !okLHS {
		// Use GetLhsTypedId() for error reporting context as well
		v.addError("LHS of let block item is not an identifier: "+ctx.GetLhsTypedId().GetText(), ctx.GetLhsTypedId().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	rhsVisited := v.Visit(ctx.GetRhsExpr())
	rhsExpr, okRHS := rhsVisited.(ast.Expr)
	if !okRHS {
		v.addError("RHS of let block item is not an expression: "+ctx.GetRhsExpr().GetText(), ctx.GetRhsExpr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	stmts = append(stmts, &ast.AssignStmt{
		Lhs: []ast.Expr{lhsIdent}, Tok: token.DEFINE, Rhs: []ast.Expr{rhsExpr},
	})
	return stmts
}

// VisitLetBlockItemDestructuredObj handles: LBRACE TypedIDList RBRACE EQUALS expr
func (v *ManuscriptAstVisitor) VisitLetBlockItemDestructuredObj(ctx *msParser.LetBlockItemDestructuredObjContext) interface{} {
	var stmts []ast.Stmt
	var lhsIdents []*ast.Ident

	typedIDListCtx := ctx.GetLhsDestructuredIdsObj().(*msParser.TypedIDListContext)
	for _, typedIDInterface := range typedIDListCtx.AllTypedID() {
		idVisited := v.Visit(typedIDInterface)
		if ident, isIdent := idVisited.(*ast.Ident); isIdent {
			lhsIdents = append(lhsIdents, ident)
		} else {
			v.addError("Identifier in let block object destructuring not valid: "+typedIDInterface.GetText(), typedIDInterface.GetStart())
			return []ast.Stmt{&ast.BadStmt{}}
		}
	}
	if len(lhsIdents) == 0 {
		v.addError("Let block object destructuring no LHS: "+ctx.GetLhsDestructuredIdsObj().GetText(), ctx.GetLhsDestructuredIdsObj().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	rhsVisited := v.Visit(ctx.GetRhsExprObj())
	rhsExpr, okRHS := rhsVisited.(ast.Expr)
	if !okRHS {
		v.addError("RHS of let block object destructuring not expr: "+ctx.GetRhsExprObj().GetText(), ctx.GetRhsExprObj().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	tempVarIdent := ast.NewIdent("__val" + v.nextTempVarCounter())
	stmts = append(stmts, &ast.AssignStmt{
		Lhs: []ast.Expr{tempVarIdent}, Tok: token.DEFINE, Rhs: []ast.Expr{rhsExpr},
	})
	for _, ident := range lhsIdents {
		stmts = append(stmts, &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent(ident.Name)}, Tok: token.DEFINE,
			Rhs: []ast.Expr{&ast.SelectorExpr{X: tempVarIdent, Sel: ast.NewIdent(ident.Name)}},
		})
	}
	return stmts
}

// VisitLetBlockItemDestructuredArray handles: LSQBR TypedIDList RSQBR EQUALS expr
func (v *ManuscriptAstVisitor) VisitLetBlockItemDestructuredArray(ctx *msParser.LetBlockItemDestructuredArrayContext) interface{} {
	var stmts []ast.Stmt
	var lhsIdents []*ast.Ident

	typedIDListCtx := ctx.GetLhsDestructuredIdsArr().(*msParser.TypedIDListContext)
	for _, typedIDInterface := range typedIDListCtx.AllTypedID() {
		idVisited := v.Visit(typedIDInterface)
		if ident, isIdent := idVisited.(*ast.Ident); isIdent {
			lhsIdents = append(lhsIdents, ident)
		} else {
			v.addError("Identifier in let block array destructuring not valid: "+typedIDInterface.GetText(), typedIDInterface.GetStart())
			return []ast.Stmt{&ast.BadStmt{}}
		}
	}
	if len(lhsIdents) == 0 {
		v.addError("Let block array destructuring no LHS: "+ctx.GetLhsDestructuredIdsArr().GetText(), ctx.GetLhsDestructuredIdsArr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	rhsVisited := v.Visit(ctx.GetRhsExprArr())
	rhsExpr, okRHS := rhsVisited.(ast.Expr)
	if !okRHS {
		v.addError("RHS of let block array destructuring not expr: "+ctx.GetRhsExprArr().GetText(), ctx.GetRhsExprArr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	tempVarIdent := ast.NewIdent("__val" + v.nextTempVarCounter())
	stmts = append(stmts, &ast.AssignStmt{
		Lhs: []ast.Expr{tempVarIdent}, Tok: token.DEFINE, Rhs: []ast.Expr{rhsExpr},
	})
	for i, ident := range lhsIdents {
		stmts = append(stmts, &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent(ident.Name)}, Tok: token.DEFINE,
			Rhs: []ast.Expr{&ast.IndexExpr{X: tempVarIdent, Index: &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(i)}}},
		})
	}
	return stmts
}
