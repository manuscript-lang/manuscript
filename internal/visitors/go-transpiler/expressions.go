package transpiler

import (
	"fmt"
	"go/ast"
	"go/token"

	mast "manuscript-lang/manuscript/internal/ast"
)

// VisitIdentifier transpiles identifier expressions
func (t *GoTranspiler) VisitIdentifier(node *mast.Identifier) ast.Node {
	if node == nil {
		t.addError("invalid identifier", node)
		return nil
	}

	ident := &ast.Ident{
		Name:    node.Name,
		NamePos: t.posWithName(node, node.Name),
	}

	t.registerNodeMapping(ident, node)
	return ident
}

// VisitBinaryExpr transpiles binary expressions
func (t *GoTranspiler) VisitBinaryExpr(node *mast.BinaryExpr) ast.Node {
	if node == nil {
		t.addError("invalid binary expression", node)
		return nil
	}

	left := t.Visit(node.Left)
	right := t.Visit(node.Right)

	leftExpr, okLeft := left.(ast.Expr)
	rightExpr, okRight := right.(ast.Expr)

	if !okLeft || !okRight {
		t.addError("binary expression operands are not valid expressions", node)
		return nil
	}

	goOp := t.mapBinaryOp(node.Op)
	if goOp == token.ILLEGAL {
		t.addError("unsupported binary operator", node)
		goOp = token.ADD // fallback
	}

	binaryExpr := &ast.BinaryExpr{
		X:     leftExpr,
		OpPos: t.pos(node),
		Op:    goOp,
		Y:     rightExpr,
	}

	t.registerNodeMapping(binaryExpr, node)
	return binaryExpr
}

// VisitUnaryExpr transpiles unary expressions
func (t *GoTranspiler) VisitUnaryExpr(node *mast.UnaryExpr) ast.Node {
	if node == nil {
		t.addError("invalid unary expression", node)
		return nil
	}

	operand := t.Visit(node.Expr)
	operandExpr, ok := operand.(ast.Expr)
	if !ok {
		t.addError("unary expression operand is not a valid expression", node)
		return nil
	}

	goOp := t.mapUnaryOp(node.Op)
	if goOp == token.ILLEGAL {
		t.addError("unsupported unary operator", node)
		goOp = token.NOT // fallback
	}

	unaryExpr := &ast.UnaryExpr{
		OpPos: t.pos(node),
		Op:    goOp,
		X:     operandExpr,
	}

	t.registerNodeMapping(unaryExpr, node)
	return unaryExpr
}

// VisitCallExpr transpiles function call expressions
func (t *GoTranspiler) VisitCallExpr(node *mast.CallExpr) ast.Node {
	if node == nil {
		t.addError("invalid call expression", node)
		return nil
	}

	function := t.Visit(node.Func)
	funcExpr, ok := function.(ast.Expr)
	if !ok {
		t.addError("call expression function is not a valid expression", node)
		return nil
	}

	var args []ast.Expr
	for i, arg := range node.Args {
		if arg == nil {
			continue
		}

		argResult := t.Visit(arg)
		if argExpr, ok := argResult.(ast.Expr); ok {
			// For better source mapping, assign each argument a unique position
			if ident, isIdent := argExpr.(*ast.Ident); isIdent {
				// Create a unique position for this specific argument
				ident.NamePos = t.posWithName(arg, ident.Name+fmt.Sprintf("_arg%d", i))
			}
			args = append(args, argExpr)
		}
	}

	callExpr := &ast.CallExpr{
		Fun:    funcExpr,
		Lparen: t.pos(node),
		Args:   args,
	}

	// Register node mapping for post-print source mapping
	t.registerNodeMapping(callExpr, node)

	return callExpr
}

// VisitIndexExpr transpiles index expressions (array/object access)
func (t *GoTranspiler) VisitIndexExpr(node *mast.IndexExpr) ast.Node {
	if node == nil {
		t.addError("invalid index expression", node)
		return nil
	}

	object := t.Visit(node.Expr)
	index := t.Visit(node.Index)

	objectExpr, okObj := object.(ast.Expr)
	indexExpr, okIdx := index.(ast.Expr)

	if !okObj || !okIdx {
		t.addError("index expression operands are not valid expressions", node)
		return nil
	}

	indexExprNode := &ast.IndexExpr{
		X:      objectExpr,
		Lbrack: t.pos(node),
		Index:  indexExpr,
	}

	t.registerNodeMapping(indexExprNode, node)
	return indexExprNode
}

// VisitDotExpr transpiles member access expressions
func (t *GoTranspiler) VisitDotExpr(node *mast.DotExpr) ast.Node {
	if node == nil {
		t.addError("invalid dot expression", node)
		return nil
	}

	object := t.Visit(node.Expr)
	objectExpr, ok := object.(ast.Expr)
	if !ok {
		t.addError("dot expression object is not a valid expression", node)
		return nil
	}

	selectorExpr := &ast.SelectorExpr{
		X: objectExpr,
		Sel: &ast.Ident{
			Name:    t.generateVarName(node.Field),
			NamePos: t.pos(node),
		},
	}

	t.registerNodeMapping(selectorExpr, node)
	return selectorExpr
}

// VisitFnExpr transpiles function expressions
func (t *GoTranspiler) VisitFnExpr(node *mast.FnExpr) ast.Node {
	if node == nil {
		t.addError("invalid function expression", node)
		return nil
	}

	// Build parameter list
	var params []*ast.Field
	for i := range node.Parameters {
		param := &node.Parameters[i]
		field := t.Visit(param)
		if astField, ok := field.(*ast.Field); ok {
			params = append(params, astField)
		}
	}

	// Build return type
	var results *ast.FieldList
	if node.ReturnType != nil {
		returnType := t.Visit(node.ReturnType)
		if returnExpr, ok := returnType.(ast.Expr); ok {
			results = &ast.FieldList{
				List: []*ast.Field{{Type: returnExpr}},
			}
		}
	}

	// Build function body
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

	funcLit := &ast.FuncLit{
		Type: &ast.FuncType{
			Params:  &ast.FieldList{List: params},
			Results: results,
		},
		Body: body,
	}

	t.registerNodeMapping(funcLit, node)
	return funcLit
}

// VisitTernaryExpr transpiles ternary expressions to if expressions
func (t *GoTranspiler) VisitTernaryExpr(node *mast.TernaryExpr) ast.Node {
	if node == nil || node.Cond == nil {
		t.addError("invalid ternary expression", node)
		return nil
	}

	// Visit condition
	condition := t.Visit(node.Cond)
	condExpr, ok := condition.(ast.Expr)
	if !ok {
		t.addError("ternary condition is not a valid expression", node)
		return nil
	}

	// Visit then branch
	var thenExpr ast.Expr
	if node.Then != nil {
		thenResult := t.Visit(node.Then)
		if expr, ok := thenResult.(ast.Expr); ok {
			thenExpr = expr
		} else {
			t.addError("ternary then branch is not a valid expression", node)
			return nil
		}
	} else {
		thenExpr = &ast.Ident{Name: "nil"}
	}

	// Visit else branch
	var elseExpr ast.Expr
	if node.Else != nil {
		elseResult := t.Visit(node.Else)
		if expr, ok := elseResult.(ast.Expr); ok {
			elseExpr = expr
		} else {
			t.addError("ternary else branch is not a valid expression", node)
			return nil
		}
	} else {
		elseExpr = &ast.Ident{Name: "nil"}
	}

	// Create immediately invoked function expression (IIFE) for ternary
	funcLit := &ast.FuncLit{
		Type: &ast.FuncType{
			Params: &ast.FieldList{},
			Results: &ast.FieldList{
				List: []*ast.Field{{Type: &ast.Ident{Name: "interface{}"}}},
			},
		},
		Body: &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.IfStmt{
					Cond: condExpr,
					Body: &ast.BlockStmt{
						List: []ast.Stmt{
							&ast.ReturnStmt{Results: []ast.Expr{thenExpr}},
						},
					},
					Else: &ast.BlockStmt{
						List: []ast.Stmt{
							&ast.ReturnStmt{Results: []ast.Expr{elseExpr}},
						},
					},
				},
			},
		},
	}

	// Return the function call expression
	callExpr := &ast.CallExpr{Fun: funcLit}
	t.registerNodeMapping(callExpr, node)
	return callExpr
}

// VisitAssignmentExpr transpiles assignment expressions
func (t *GoTranspiler) VisitAssignmentExpr(node *mast.AssignmentExpr) ast.Node {
	if node == nil {
		t.addError("invalid assignment expression", node)
		return nil
	}

	left := t.Visit(node.Left)
	right := t.Visit(node.Right)

	leftExpr, okLeft := left.(ast.Expr)
	rightExpr, okRight := right.(ast.Expr)

	if !okLeft || !okRight {
		t.addError("assignment expression operands are not valid expressions", node)
		return nil
	}

	// For compound assignments, expand them to binary expressions
	var rhsExpr ast.Expr
	switch node.Op {
	case mast.AssignEq:
		// Simple assignment: x = y
		rhsExpr = rightExpr
	case mast.AssignPlusEq:
		// x += y becomes x = x + y
		rhsExpr = &ast.BinaryExpr{X: leftExpr, Op: token.ADD, Y: rightExpr}
	case mast.AssignMinusEq:
		// x -= y becomes x = x - y
		rhsExpr = &ast.BinaryExpr{X: leftExpr, Op: token.SUB, Y: rightExpr}
	case mast.AssignStarEq:
		// x *= y becomes x = x * y
		rhsExpr = &ast.BinaryExpr{X: leftExpr, Op: token.MUL, Y: rightExpr}
	case mast.AssignSlashEq:
		// x /= y becomes x = x / y
		rhsExpr = &ast.BinaryExpr{X: leftExpr, Op: token.QUO, Y: rightExpr}
	case mast.AssignModEq:
		// x %= y becomes x = x % y
		rhsExpr = &ast.BinaryExpr{X: leftExpr, Op: token.REM, Y: rightExpr}
	case mast.AssignCaretEq:
		// x ^= y becomes x = x ^ y
		rhsExpr = &ast.BinaryExpr{X: leftExpr, Op: token.XOR, Y: rightExpr}
	default:
		t.addError("unsupported assignment operator", node)
		rhsExpr = rightExpr // fallback
	}

	return &ast.AssignStmt{
		Lhs: []ast.Expr{leftExpr},
		Tok: token.ASSIGN,
		Rhs: []ast.Expr{rhsExpr},
	}
}

// VisitParenExpr transpiles parenthesized expressions
func (t *GoTranspiler) VisitParenExpr(node *mast.ParenExpr) ast.Node {
	if node == nil {
		return &ast.Ident{Name: "nil"}
	}

	if node.Expr != nil {
		return t.Visit(node.Expr)
	}

	return &ast.Ident{Name: "nil"}
}

// VisitVoidExpr transpiles void expressions
func (t *GoTranspiler) VisitVoidExpr(node *mast.VoidExpr) ast.Node {
	return &ast.Ident{Name: "nil"}
}

// VisitNullExpr transpiles null expressions
func (t *GoTranspiler) VisitNullExpr(node *mast.NullExpr) ast.Node {
	return &ast.Ident{Name: "nil"}
}

// VisitTryExpr transpiles try expressions
func (t *GoTranspiler) VisitTryExpr(node *mast.TryExpr) ast.Node {
	if node == nil {
		return &ast.Ident{Name: "nil"}
	}

	// For try expressions, we need to handle the error return
	if node.Expr != nil {
		return t.Visit(node.Expr)
	}

	return &ast.Ident{Name: "nil"}
}

// mapBinaryOp maps manuscript binary operators to Go operators
func (t *GoTranspiler) mapBinaryOp(op mast.BinaryOp) token.Token {
	switch op {
	case mast.Add:
		return token.ADD
	case mast.Subtract:
		return token.SUB
	case mast.Multiply:
		return token.MUL
	case mast.Divide:
		return token.QUO
	case mast.Modulo:
		return token.REM
	case mast.Equal:
		return token.EQL
	case mast.NotEqual:
		return token.NEQ
	case mast.Less:
		return token.LSS
	case mast.LessEqual:
		return token.LEQ
	case mast.Greater:
		return token.GTR
	case mast.GreaterEqual:
		return token.GEQ
	case mast.LogicalAnd:
		return token.LAND
	case mast.LogicalOr:
		return token.LOR
	case mast.BitwiseAnd:
		return token.AND
	case mast.BitwiseXor:
		return token.XOR
	default:
		return token.ILLEGAL
	}
}

// mapUnaryOp maps manuscript unary operators to Go operators
func (t *GoTranspiler) mapUnaryOp(op mast.UnaryOp) token.Token {
	switch op {
	case mast.UnaryNot:
		return token.NOT
	case mast.UnaryMinus:
		return token.SUB
	case mast.UnaryPlus:
		return token.ADD
	default:
		return token.ILLEGAL
	}
}
