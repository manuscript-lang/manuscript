package transpiler

import (
	"fmt"
	"go/ast"
	"go/token"
	mast "manuscript-lang/manuscript/internal/ast"
)

// generateParameterExtraction creates parameter extraction statements for functions with default parameters
func (t *GoTranspiler) generateParameterExtraction(
	param *mast.Parameter,
	paramIndex int,
	paramName string,
	paramType ast.Expr,
) []ast.Stmt {
	if param.DefaultValue != nil {
		return t.createDefaultParameterStmts(param, paramIndex, paramName, paramType)
	}
	return t.createRequiredParameterStmts(paramIndex, paramName, paramType)
}

// createDefaultParameterStmts creates statements for parameters with default values
func (t *GoTranspiler) createDefaultParameterStmts(
	param *mast.Parameter,
	paramIndex int,
	paramName string,
	paramType ast.Expr,
) []ast.Stmt {
	defaultExpr := t.Visit(param.DefaultValue)
	defaultValue, ok := defaultExpr.(ast.Expr)
	if !ok {
		return nil
	}

	// Variable declaration with default value
	varDecl := t.createVarDecl(paramName, paramType, defaultValue)

	// Conditional assignment: if len(args) > i { name = args[i].(Type) }
	ifStmt := t.createConditionalAssignment(paramIndex, paramName, paramType)

	return []ast.Stmt{varDecl, ifStmt}
}

// createRequiredParameterStmts creates statements for required parameters
func (t *GoTranspiler) createRequiredParameterStmts(
	paramIndex int,
	paramName string,
	paramType ast.Expr,
) []ast.Stmt {
	// Parameter without default value: name := args[i].(Type)
	assignStmt := &ast.AssignStmt{
		Lhs: []ast.Expr{&ast.Ident{Name: paramName}},
		Tok: token.DEFINE,
		Rhs: []ast.Expr{t.createArgsTypeAssertion(paramIndex, paramType)},
	}
	return []ast.Stmt{assignStmt}
}

// createVarDecl creates a variable declaration statement
func (t *GoTranspiler) createVarDecl(
	paramName string,
	paramType ast.Expr,
	defaultValue ast.Expr,
) *ast.DeclStmt {
	return &ast.DeclStmt{
		Decl: &ast.GenDecl{
			Tok: token.VAR,
			Specs: []ast.Spec{
				&ast.ValueSpec{
					Names:  []*ast.Ident{{Name: paramName}},
					Type:   paramType,
					Values: []ast.Expr{defaultValue},
				},
			},
		},
	}
}

// createConditionalAssignment creates an if statement for conditional parameter assignment
func (t *GoTranspiler) createConditionalAssignment(
	paramIndex int,
	paramName string,
	paramType ast.Expr,
) *ast.IfStmt {
	return &ast.IfStmt{
		Cond: &ast.BinaryExpr{
			X: &ast.CallExpr{
				Fun:  &ast.Ident{Name: "len"},
				Args: []ast.Expr{&ast.Ident{Name: "args"}},
			},
			Op: token.GTR,
			Y:  &ast.BasicLit{Kind: token.INT, Value: fmt.Sprintf("%d", paramIndex)},
		},
		Body: &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.AssignStmt{
					Lhs: []ast.Expr{&ast.Ident{Name: paramName}},
					Tok: token.ASSIGN,
					Rhs: []ast.Expr{t.createArgsTypeAssertion(paramIndex, paramType)},
				},
			},
		},
	}
}

// createArgsTypeAssertion creates a type assertion expression for args[i].(Type)
func (t *GoTranspiler) createArgsTypeAssertion(
	paramIndex int,
	paramType ast.Expr,
) *ast.TypeAssertExpr {
	return &ast.TypeAssertExpr{
		X: &ast.IndexExpr{
			X:     &ast.Ident{Name: "args"},
			Index: &ast.BasicLit{Kind: token.INT, Value: fmt.Sprintf("%d", paramIndex)},
		},
		Type: paramType,
	}
}

// manuscriptBodyContainsYield checks if a CodeBlock contains yield statements
func (t *GoTranspiler) manuscriptBodyContainsYield(
	body mast.Node,
) bool {
	if body == nil {
		return false
	}

	codeBlock, ok := body.(*mast.CodeBlock)
	if !ok {
		return false
	}

	for _, stmt := range codeBlock.Stmts {
		if t.stmtContainsYield(stmt) {
			return true
		}
	}
	return false
}

// stmtContainsYield recursively checks if a statement contains yield statements
func (t *GoTranspiler) stmtContainsYield(stmt mast.Statement) bool {
	if stmt == nil {
		return false
	}

	switch node := stmt.(type) {
	case *mast.YieldStmt:
		return true
	case *mast.IfStmt:
		return (node.Then != nil && t.manuscriptBodyContainsYield(node.Then)) ||
			(node.Else != nil && t.manuscriptBodyContainsYield(node.Else))
	case *mast.WhileStmt:
		return node.Body != nil && t.loopBodyContainsYield(node.Body)
	case *mast.ForStmt:
		return node.Loop != nil && t.forLoopContainsYield(node.Loop)
	default:
		return false
	}
}

// loopBodyContainsYield checks if a LoopBody contains yield statements
func (t *GoTranspiler) loopBodyContainsYield(body *mast.LoopBody) bool {
	if body == nil {
		return false
	}

	for _, stmt := range body.Stmts {
		if t.stmtContainsYield(stmt) {
			return true
		}
	}
	return false
}

// forLoopContainsYield checks if a ForLoop contains yield statements
func (t *GoTranspiler) forLoopContainsYield(loop mast.ForLoop) bool {
	if loop == nil {
		return false
	}

	switch loopNode := loop.(type) {
	case *mast.ForTrinityLoop:
		return t.loopBodyContainsYield(loopNode.Body)
	case *mast.ForInLoop:
		return t.loopBodyContainsYield(loopNode.Body)
	default:
		return false
	}
}

// buildGeneratorFunction creates a generator function that returns a channel
func (t *GoTranspiler) buildGeneratorFunction(
	name string,
	params []*ast.Field,
	body *ast.BlockStmt,
) ast.Node {
	// Determine the yield type - for now use interface{} but could be improved
	yieldType := ast.NewIdent("any")

	// Create channel type: chan interface{}
	channelType := &ast.ChanType{
		Dir:   ast.SEND | ast.RECV,
		Value: yieldType,
	}

	// Generator function returns a channel
	generatorResults := &ast.FieldList{
		List: []*ast.Field{{Type: channelType}},
	}

	// Create the generator function body
	generatorBody := t.buildGeneratorBody(body, yieldType)

	return &ast.FuncDecl{
		Name: &ast.Ident{Name: t.generateVarName(name)},
		Type: &ast.FuncType{
			Params:  &ast.FieldList{List: params},
			Results: generatorResults,
		},
		Body: generatorBody,
	}
}

// buildGeneratorBody creates the generator function body with channel operations
func (t *GoTranspiler) buildGeneratorBody(
	originalBody *ast.BlockStmt,
	yieldType ast.Expr,
) *ast.BlockStmt {
	// Create channel: ch := make(chan interface{}, 1)
	channelDecl := &ast.AssignStmt{
		Lhs: []ast.Expr{&ast.Ident{Name: "ch"}},
		Tok: token.DEFINE,
		Rhs: []ast.Expr{
			&ast.CallExpr{
				Fun: &ast.Ident{Name: "make"},
				Args: []ast.Expr{
					&ast.ChanType{
						Dir:   ast.SEND | ast.RECV,
						Value: yieldType,
					},
				},
			},
		},
	}

	// Create goroutine that runs the original function body
	goroutineBody := t.transformYieldCalls(originalBody)

	// Add defer close(ch) at the beginning of the goroutine
	deferCloseStmt := &ast.DeferStmt{
		Call: &ast.CallExpr{
			Fun:  &ast.Ident{Name: "close"},
			Args: []ast.Expr{&ast.Ident{Name: "ch"}},
		},
	}

	// Prepend defer statement to the goroutine body
	goroutineBody.List = append([]ast.Stmt{deferCloseStmt}, goroutineBody.List...)

	// Create go statement: go func() { ... }()
	goStmt := &ast.GoStmt{
		Call: &ast.CallExpr{
			Fun: &ast.FuncLit{
				Type: &ast.FuncType{
					Params: &ast.FieldList{},
				},
				Body: goroutineBody,
			},
		},
	}

	// Return channel: return ch
	returnStmt := &ast.ReturnStmt{
		Results: []ast.Expr{&ast.Ident{Name: "ch"}},
	}

	return &ast.BlockStmt{
		List: []ast.Stmt{
			channelDecl,
			goStmt,
			returnStmt,
		},
	}
}

// transformYieldCalls replaces __yield calls with channel sends
func (t *GoTranspiler) transformYieldCalls(
	body *ast.BlockStmt,
) *ast.BlockStmt {
	newStmts := make([]ast.Stmt, 0, len(body.List))

	for _, stmt := range body.List {
		newStmt := t.transformYieldInStmt(stmt)

		// Handle case where transformYieldInStmt returns a BlockStmt (e.g., for return statements)
		if blockStmt, ok := newStmt.(*ast.BlockStmt); ok {
			newStmts = append(newStmts, blockStmt.List...)
		} else {
			newStmts = append(newStmts, newStmt)
		}
	}

	return &ast.BlockStmt{List: newStmts}
}

// transformYieldInStmt recursively transforms yield calls in statements
func (t *GoTranspiler) transformYieldInStmt(
	stmt ast.Stmt,
) ast.Stmt {
	switch s := stmt.(type) {
	case *ast.ExprStmt:
		if callExpr, ok := s.X.(*ast.CallExpr); ok {
			if ident, ok := callExpr.Fun.(*ast.Ident); ok && ident.Name == "__yield" {
				// Transform __yield(value) to ch <- value
				var value ast.Expr = &ast.Ident{Name: "nil"}
				if len(callExpr.Args) > 0 {
					value = callExpr.Args[0]
				}

				return &ast.ExprStmt{
					X: &ast.BinaryExpr{
						X:  &ast.Ident{Name: "ch"},
						Op: token.ARROW,
						Y:  value,
					},
				}
			}
		}
		return s
	case *ast.ReturnStmt:
		// Transform return statements in generator functions to close channel and return
		closeStmt := &ast.ExprStmt{
			X: &ast.CallExpr{
				Fun:  &ast.Ident{Name: "close"},
				Args: []ast.Expr{&ast.Ident{Name: "ch"}},
			},
		}
		returnStmt := &ast.ReturnStmt{}

		// Return a block with both statements
		return &ast.BlockStmt{
			List: []ast.Stmt{closeStmt, returnStmt},
		}
	case *ast.BlockStmt:
		return t.transformYieldCalls(s)
	case *ast.IfStmt:
		s.Body = t.transformYieldCalls(s.Body)
		if s.Else != nil {
			if elseBlock, ok := s.Else.(*ast.BlockStmt); ok {
				s.Else = t.transformYieldCalls(elseBlock)
			} else if elseStmt, ok := s.Else.(ast.Stmt); ok {
				s.Else = t.transformYieldInStmt(elseStmt)
			}
		}
		return s
	case *ast.ForStmt:
		s.Body = t.transformYieldCalls(s.Body)
		return s
	case *ast.RangeStmt:
		s.Body = t.transformYieldCalls(s.Body)
		return s
	default:
		return s
	}
}
