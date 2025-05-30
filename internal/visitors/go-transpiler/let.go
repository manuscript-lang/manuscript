package transpiler

import (
	"fmt"
	"go/ast"
	"go/token"
	mast "manuscript-lang/manuscript/internal/ast"
	"strconv"
)

// Helper function to create an identifier with proper position tracking
func (t *GoTranspiler) createIdent(id *mast.TypedID, name string, letNode mast.Node) *ast.Ident {
	if name == "" {
		return &ast.Ident{Name: "_", NamePos: t.pos(letNode)}
	}
	ident := &ast.Ident{
		Name:    t.generateVarName(name),
		NamePos: t.pos(letNode),
	}

	// Register the identifier for sourcemap with the let node
	t.registerNodeMapping(ident, letNode)

	return ident
}

// Helper function to handle type annotation
func (t *GoTranspiler) processTypeAnnotation(typeNode mast.TypeAnnotation, varName string) (ast.Expr, error) {
	if typeNode == nil {
		return nil, nil
	}

	typeResultNode := t.Visit(typeNode)
	if typeResultNode == nil {
		return nil, fmt.Errorf("failed to transpile type annotation for '%s'", varName)
	}

	typeExpr, ok := typeResultNode.(ast.Expr)
	if !ok {
		return nil, fmt.Errorf("expected type annotation for '%s' to transpile to a Go type expression, but got %T", varName, typeResultNode)
	}

	return typeExpr, nil
}

// Helper function to handle value expression
func (t *GoTranspiler) processValueExpression(valueNode mast.Expression, varName string) (ast.Expr, error) {
	if valueNode == nil {
		return nil, nil
	}

	valueAstNode := t.Visit(valueNode)
	if valueAstNode == nil {
		return nil, fmt.Errorf("failed to transpile value expression for '%s'", varName)
	}

	valueExpr, ok := valueAstNode.(ast.Expr)
	if !ok {
		return nil, fmt.Errorf("the right-hand side of the assignment to '%s' must be an expression, but it transpired to %T", varName, valueAstNode)
	}

	return valueExpr, nil
}

// Helper function to create variable declaration without value
func (t *GoTranspiler) createVarDeclStmt(ident *ast.Ident, varType ast.Expr, pos token.Pos) ast.Node {
	valueSpec := &ast.ValueSpec{
		Names: []*ast.Ident{ident},
		Type:  varType,
	}

	return &ast.DeclStmt{
		Decl: &ast.GenDecl{
			TokPos: pos,
			Tok:    token.VAR,
			Specs:  []ast.Spec{valueSpec},
		},
	}
}

// Helper function to create assignment statement
func (t *GoTranspiler) createAssignment(ident *ast.Ident, valueExpr ast.Expr, pos token.Pos, letNode mast.Node) ast.Node {
	assignStmt := &ast.AssignStmt{
		Lhs:    []ast.Expr{ident},
		TokPos: pos,
		Tok:    token.DEFINE,
		Rhs:    []ast.Expr{valueExpr},
	}

	// Register the assignment statement for sourcemap with the full let node
	t.registerNodeMapping(assignStmt, letNode)
	return assignStmt
}

// Helper function to create try assignment with error handling
func (t *GoTranspiler) createTryAssignment(ident *ast.Ident, valueExpr ast.Expr, pos token.Pos, valueNode mast.Node, letNode mast.Node) ast.Node {
	errIdent := &ast.Ident{Name: "err", NamePos: t.pos(valueNode)}

	assignStmt := &ast.AssignStmt{
		Lhs:    []ast.Expr{ident, errIdent},
		TokPos: pos,
		Tok:    token.DEFINE,
		Rhs:    []ast.Expr{valueExpr},
	}

	nilResultForValue := &ast.Ident{Name: "nil", NamePos: t.pos(valueNode)}

	ifStmt := &ast.IfStmt{
		Cond: &ast.BinaryExpr{
			X:  errIdent,
			Op: token.NEQ,
			Y:  &ast.Ident{Name: "nil", NamePos: t.pos(valueNode)},
		},
		Body: &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.ReturnStmt{
					Results: []ast.Expr{nilResultForValue, errIdent},
				},
			},
		},
	}

	blockStmt := &ast.BlockStmt{List: []ast.Stmt{assignStmt, ifStmt}}
	t.registerNodeMapping(blockStmt, letNode)
	return blockStmt
}

// Core function to handle single let declarations
func (t *GoTranspiler) processSingleLet(letNode *mast.LetSingle) ast.Node {
	if letNode == nil || letNode.ID.Name == "" {
		t.addError("Attempted to transpile a nil identifier. This is an internal compiler error.", letNode)
		return nil
	}

	id := &letNode.ID
	varName := id.Name
	if varName == "" {
		varName = "_"
	}

	ident := t.createIdent(id, id.Name, letNode)
	pos := t.pos(letNode) // Use the position of the entire let statement

	// Process type annotation if present
	varType, err := t.processTypeAnnotation(id.Type, varName)
	if err != nil {
		t.addError(err.Error(), id.Type)
		return nil
	}

	// Process value expression if present
	valueExpr, err := t.processValueExpression(letNode.Value, varName)
	if err != nil {
		t.addError(err.Error(), letNode.Value)
		return nil
	}

	// Handle different cases
	if valueExpr != nil {
		if letNode.IsTry {
			return t.createTryAssignment(ident, valueExpr, pos, letNode.Value, letNode)
		}
		return t.createAssignment(ident, valueExpr, pos, letNode)
	}

	// No value provided - use type annotation or nil for untyped var declaration
	varDeclStmt := t.createVarDeclStmt(ident, varType, pos)
	t.registerNodeMapping(varDeclStmt, letNode)
	return varDeclStmt
}

// VisitLetBlock transpiles let blocks
func (t *GoTranspiler) VisitLetBlock(node *mast.LetBlock) ast.Node {
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

	// Return a block statement that can be flattened by parent visitors
	return &ast.BlockStmt{List: stmts}
}

// VisitLetBlockItemSingle transpiles single let block items
func (t *GoTranspiler) VisitLetBlockItemSingle(node *mast.LetBlockItemSingle) ast.Node {
	if node == nil {
		t.addError("Attempted to transpile a nil LetBlockItemSingle node. This is an internal compiler error.", nil)
		return nil
	}

	return t.processSingleLet(&mast.LetSingle{
		ID:    node.ID,
		Value: node.Value,
	})
}

// VisitLetBlockItemDestructuredObj transpiles destructured object let block items
func (t *GoTranspiler) VisitLetBlockItemDestructuredObj(node *mast.LetBlockItemDestructuredObj) ast.Node {
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
			Lhs: []ast.Expr{t.createIdent(&id, id.Name, node)},
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
func (t *GoTranspiler) VisitLetBlockItemDestructuredArray(node *mast.LetBlockItemDestructuredArray) ast.Node {
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
			Lhs: []ast.Expr{t.createIdent(&id, id.Name, node)},
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
func (t *GoTranspiler) VisitLetDestructuredObj(node *mast.LetDestructuredObj) ast.Node {
	if node == nil {
		return nil
	}

	// Similar to VisitLetBlockItemDestructuredObj but as a statement
	result := t.VisitLetBlockItemDestructuredObj(&mast.LetBlockItemDestructuredObj{
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
func (t *GoTranspiler) VisitLetDestructuredArray(node *mast.LetDestructuredArray) ast.Node {
	if node == nil {
		return nil
	}

	// Similar to VisitLetBlockItemDestructuredArray but as a statement
	result := t.VisitLetBlockItemDestructuredArray(&mast.LetBlockItemDestructuredArray{
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
func (t *GoTranspiler) VisitLetSingle(node *mast.LetSingle) ast.Node {
	if node == nil {
		t.addError("Attempted to transpile a nil LetSingle node. This is an internal compiler error.", nil)
		return nil
	}

	return t.processSingleLet(node)
}
