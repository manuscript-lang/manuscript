package transpiler

import (
	"go/ast"
	"go/token"
	msast "manuscript-co/manuscript/internal/ast"
	"strconv"
)

// VisitLetBlock transpiles let blocks
func (t *GoTranspiler) VisitLetBlock(node *msast.LetBlock) ast.Node {
	if node == nil {
		return &ast.BlockStmt{List: []ast.Stmt{}}
	}

	var stmts []ast.Stmt
	for _, item := range node.Items {
		itemResult := t.Visit(item)

		// Handle different result types
		switch v := itemResult.(type) {
		case *ast.BlockStmt:
			// Flatten block statements from destructuring
			stmts = append(stmts, v.List...)
		case ast.Stmt:
			stmts = append(stmts, v)
		case nil:
			// Skip nil results
			continue
		}
	}

	// Instead of returning a BlockStmt, return the statements directly
	// If there's only one statement, return it directly
	if len(stmts) == 1 {
		return stmts[0]
	}

	// For multiple statements, we still need to return a BlockStmt
	// but mark it somehow for flattening
	return &ast.BlockStmt{List: stmts}
}

// VisitLetBlockItemSingle transpiles single let block items
func (t *GoTranspiler) VisitLetBlockItemSingle(node *msast.LetBlockItemSingle) ast.Node {
	if node == nil {
		return nil
	}

	// Get the identifier
	var ident *ast.Ident
	if node.ID.Name != "" {
		ident = &ast.Ident{Name: t.generateVarName(node.ID.Name)}
	} else {
		ident = &ast.Ident{Name: "_"}
	}

	// Get the type if specified
	var varType ast.Expr
	if node.ID.Type != nil {
		typeResult := t.Visit(node.ID.Type)
		if typeExpr, ok := typeResult.(ast.Expr); ok {
			varType = typeExpr
		}
	}

	// Handle the value
	if node.Value != nil {
		valueResult := t.Visit(node.Value)
		if valueExpr, ok := valueResult.(ast.Expr); ok {
			// Generate short variable declaration: x := value
			return &ast.AssignStmt{
				Lhs: []ast.Expr{ident},
				Tok: token.DEFINE,
				Rhs: []ast.Expr{valueExpr},
			}
		}
	}

	// No value provided - generate variable declaration: var x [type]
	valueSpec := &ast.ValueSpec{
		Names: []*ast.Ident{ident},
		Type:  varType,
	}

	return &ast.DeclStmt{
		Decl: &ast.GenDecl{
			Tok:   token.VAR,
			Specs: []ast.Spec{valueSpec},
		},
	}
}

// VisitLetBlockItemDestructuredObj transpiles destructured object let block items
func (t *GoTranspiler) VisitLetBlockItemDestructuredObj(node *msast.LetBlockItemDestructuredObj) ast.Node {
	if node == nil {
		return nil
	}

	// For object destructuring, generate a block with separate assignment statements
	tempVar := t.nextTempVar()
	var stmts []ast.Stmt

	// First, assign the value to a temporary variable: __val1 := obj
	if node.Value != nil {
		valueResult := t.Visit(node.Value)
		if valueExpr, ok := valueResult.(ast.Expr); ok {
			tempAssign := &ast.AssignStmt{
				Lhs: []ast.Expr{&ast.Ident{Name: tempVar}},
				Tok: token.DEFINE,
				Rhs: []ast.Expr{valueExpr},
			}
			stmts = append(stmts, tempAssign)
		}
	}

	// Then create assignments for each destructured field: a := __val1.a
	for _, id := range node.IDs {
		fieldAssign := &ast.AssignStmt{
			Lhs: []ast.Expr{&ast.Ident{Name: t.generateVarName(id.Name)}},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{
				&ast.SelectorExpr{
					X:   &ast.Ident{Name: tempVar},
					Sel: &ast.Ident{Name: id.Name}, // Use original name for field access
				},
			},
		}
		stmts = append(stmts, fieldAssign)
	}

	return &ast.BlockStmt{List: stmts}
}

// VisitLetBlockItemDestructuredArray transpiles destructured array let block items
func (t *GoTranspiler) VisitLetBlockItemDestructuredArray(node *msast.LetBlockItemDestructuredArray) ast.Node {
	if node == nil {
		return nil
	}

	// For array destructuring, generate a block with separate assignment statements
	tempVar := t.nextTempVar()
	var stmts []ast.Stmt

	// First, assign the value to a temporary variable: __val2 := [1, 2]
	if node.Value != nil {
		valueResult := t.Visit(node.Value)
		if valueExpr, ok := valueResult.(ast.Expr); ok {
			tempAssign := &ast.AssignStmt{
				Lhs: []ast.Expr{&ast.Ident{Name: tempVar}},
				Tok: token.DEFINE,
				Rhs: []ast.Expr{valueExpr},
			}
			stmts = append(stmts, tempAssign)
		}
	}

	// Then create assignments for each destructured element: c := __val2[0]
	for i, id := range node.IDs {
		elementAssign := &ast.AssignStmt{
			Lhs: []ast.Expr{&ast.Ident{Name: t.generateVarName(id.Name)}},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{
				&ast.IndexExpr{
					X:     &ast.Ident{Name: tempVar},
					Index: &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(i)},
				},
			},
		}
		stmts = append(stmts, elementAssign)
	}

	return &ast.BlockStmt{List: stmts}
}

// VisitLetDestructuredObj transpiles destructured object let declarations
func (t *GoTranspiler) VisitLetDestructuredObj(node *msast.LetDestructuredObj) ast.Node {
	if node == nil {
		return nil
	}

	// Similar to VisitLetBlockItemDestructuredObj but as a statement
	result := t.VisitLetBlockItemDestructuredObj(&msast.LetBlockItemDestructuredObj{
		IDs:   node.IDs,
		Value: node.Value,
	})

	// Wrap in DestructuringBlockStmt to preserve block structure
	if blockStmt, ok := result.(*ast.BlockStmt); ok {
		return &DestructuringBlockStmt{BlockStmt: blockStmt}
	}

	return result
}

// VisitLetDestructuredArray transpiles destructured array let declarations
func (t *GoTranspiler) VisitLetDestructuredArray(node *msast.LetDestructuredArray) ast.Node {
	if node == nil {
		return nil
	}

	// Similar to VisitLetBlockItemDestructuredArray but as a statement
	result := t.VisitLetBlockItemDestructuredArray(&msast.LetBlockItemDestructuredArray{
		IDs:   node.IDs,
		Value: node.Value,
	})

	// Wrap in DestructuringBlockStmt to preserve block structure
	if blockStmt, ok := result.(*ast.BlockStmt); ok {
		return &DestructuringBlockStmt{BlockStmt: blockStmt}
	}

	return result
}

// VisitLetSingle transpiles single let declarations
func (t *GoTranspiler) VisitLetSingle(node *msast.LetSingle) ast.Node {
	if node == nil {
		t.addError("invalid let single declaration", node)
		return nil
	}

	// Get the identifier
	var ident *ast.Ident
	if node.ID.Name != "" {
		ident = &ast.Ident{Name: t.generateVarName(node.ID.Name)}
	} else {
		ident = &ast.Ident{Name: "_"}
	}

	// Get the type if specified
	var varType ast.Expr
	if node.ID.Type != nil {
		typeResult := t.Visit(node.ID.Type)
		if typeExpr, ok := typeResult.(ast.Expr); ok {
			varType = typeExpr
		}
	}

	// Handle the value if present
	if node.Value != nil {
		valueResult := t.Visit(node.Value)
		if valueExpr, ok := valueResult.(ast.Expr); ok {
			// Check if this is a try expression
			if node.IsTry {
				// Generate try logic: var, err := expr(); if err != nil { return nil, err }
				errIdent := &ast.Ident{Name: "err"}

				// Assignment: var, err := expr()
				assignStmt := &ast.AssignStmt{
					Lhs: []ast.Expr{ident, errIdent},
					Tok: token.DEFINE,
					Rhs: []ast.Expr{valueExpr},
				}

				// Error check: if err != nil { return nil, err }
				ifStmt := &ast.IfStmt{
					Cond: &ast.BinaryExpr{
						X:  errIdent,
						Op: token.NEQ,
						Y:  &ast.Ident{Name: "nil"},
					},
					Body: &ast.BlockStmt{
						List: []ast.Stmt{
							&ast.ReturnStmt{
								Results: []ast.Expr{
									&ast.Ident{Name: "nil"},
									errIdent,
								},
							},
						},
					},
				}

				// Return a block that VisitCodeBlock will handle
				return &ast.BlockStmt{List: []ast.Stmt{assignStmt, ifStmt}}
			} else {
				// Regular assignment: x := value
				return &ast.AssignStmt{
					Lhs: []ast.Expr{ident},
					Tok: token.DEFINE,
					Rhs: []ast.Expr{valueExpr},
				}
			}
		}
	}

	// No value provided - generate variable declaration: var x [type]
	valueSpec := &ast.ValueSpec{
		Names: []*ast.Ident{ident},
		Type:  varType,
	}

	return &ast.DeclStmt{
		Decl: &ast.GenDecl{
			Tok:   token.VAR,
			Specs: []ast.Spec{valueSpec},
		},
	}
}
