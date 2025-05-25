package transpiler

import (
	"go/ast"
	"go/token"
	mast "manuscript-lang/manuscript/internal/ast"
)

// VisitForTrinityLoop transpiles trinity for loops (init; cond; post)
func (t *GoTranspiler) VisitForTrinityLoop(node *mast.ForTrinityLoop) ast.Node {
	if node == nil {
		return &ast.ForStmt{Body: &ast.BlockStmt{List: []ast.Stmt{}}}
	}

	t.enterLoop()
	defer t.exitLoop()

	var init ast.Stmt
	if node.Init != nil {

		initResult := t.Visit(node.Init)

		if initStmt, ok := initResult.(ast.Stmt); ok {
			init = initStmt
		}
	} else {
		init = &ast.EmptyStmt{}
	}

	var cond ast.Expr
	if node.Cond != nil {
		condResult := t.Visit(node.Cond)
		if condExpr, ok := condResult.(ast.Expr); ok {
			cond = condExpr
		}
	} else {
		init = &ast.EmptyStmt{}
	}

	var post ast.Stmt
	if node.Post != nil {
		postResult := t.Visit(node.Post)
		if postStmt, ok := postResult.(ast.Stmt); ok {
			post = postStmt
		} else if postExpr, ok := postResult.(ast.Expr); ok {
			post = &ast.ExprStmt{X: postExpr}
		}
	} else {
		// TODO: This is a hack to get the AST to compile.
		// post = &ast.EmptyStmt{}
	}

	var body *ast.BlockStmt
	if node.Body != nil {
		bodyResult := t.Visit(node.Body)
		if blockStmt, ok := bodyResult.(*ast.BlockStmt); ok {
			body = blockStmt
		} else {
			body = &ast.BlockStmt{List: []ast.Stmt{}}
		}
	}

	// Always use verbose for-loop format with semicolons

	return &ast.ForStmt{
		For:  0, // Position set by parent VisitForStmt
		Init: init,
		Cond: cond,
		Post: post,
		Body: body,
	}
}

// VisitForInLoop transpiles for-in loops to Go range statements
func (t *GoTranspiler) VisitForInLoop(node *mast.ForInLoop) ast.Node {
	if node == nil {
		return &ast.ForStmt{Body: &ast.BlockStmt{List: []ast.Stmt{}}}
	}

	t.enterLoop()
	defer t.exitLoop()

	// Get the iterable expression
	var iterable ast.Expr
	if node.Iterable != nil {
		iterResult := t.Visit(node.Iterable)
		if iterExpr, ok := iterResult.(ast.Expr); ok {
			iterable = iterExpr
		} else {
			iterable = &ast.Ident{Name: "nil"}
		}
	} else {
		iterable = &ast.Ident{Name: "nil"}
	}

	// Create identifiers for key and value
	// In manuscript: for index, value in items
	// In Go: for index, value := range items
	var key, value ast.Expr

	// Handle different cases for manuscript for-in syntax
	if node.Key != "" && node.Value != "" {
		// Both key and value specified: for key, value in items
		// In manuscript: for value, index in items (value first, index second)
		// In Go: for index, value := range items (index first, value second)
		// So we need to swap: manuscript Key → Go Value, manuscript Value → Go Key
		key = &ast.Ident{Name: t.generateVarName(node.Value)} // manuscript Value → Go Key (index)
		value = &ast.Ident{Name: t.generateVarName(node.Key)} // manuscript Key → Go Value (value)
	} else if node.Value != "" {
		// Only value specified: for value in items
		// In Go this becomes: for _, value := range items
		key = &ast.Ident{Name: "_"}
		value = &ast.Ident{Name: t.generateVarName(node.Value)}
	} else if node.Key != "" {
		// Only key specified - unusual but possible: for key in items
		// In Go this becomes: for key := range items
		key = &ast.Ident{Name: t.generateVarName(node.Key)}
		value = nil
	} else {
		// Neither specified - use bare range
		key = nil
		value = nil
	}

	// Build the loop body
	var body *ast.BlockStmt
	if node.Body != nil {
		bodyResult := t.Visit(node.Body)
		if blockStmt, ok := bodyResult.(*ast.BlockStmt); ok {
			body = blockStmt
		} else {
			body = &ast.BlockStmt{List: []ast.Stmt{}}
		}
	} else {
		body = &ast.BlockStmt{List: []ast.Stmt{}}
	}

	return &ast.RangeStmt{
		Key:   key,
		Value: value,
		Tok:   token.DEFINE,
		X:     iterable,
		Body:  body,
	}
}

// VisitForInitLet transpiles for loop let initializers
func (t *GoTranspiler) VisitForInitLet(node *mast.ForInitLet) ast.Node {
	if node == nil || node.Let == nil {
		return nil
	}

	// Visit the let declaration and convert to assignment statement
	letResult := t.Visit(node.Let)

	// Check if it's already an AssignStmt (which is what we want for for-loop init)
	if assignStmt, ok := letResult.(*ast.AssignStmt); ok {
		return assignStmt
	}

	if valueSpec, ok := letResult.(*ast.ValueSpec); ok {
		// Convert ValueSpec to AssignStmt for for-loop init
		if len(valueSpec.Names) > 0 && len(valueSpec.Values) > 0 {
			return &ast.AssignStmt{
				Lhs: []ast.Expr{valueSpec.Names[0]},
				Tok: token.DEFINE,
				Rhs: valueSpec.Values,
			}
		}
	}

	return nil
}
