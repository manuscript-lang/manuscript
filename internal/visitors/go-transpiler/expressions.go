package transpiler

import (
	"go/ast"
	"go/token"

	mast "manuscript-co/manuscript/internal/ast"
)

// VisitIdentifier transpiles identifier expressions
func (t *GoTranspiler) VisitIdentifier(node *mast.Identifier) ast.Node {
	if node == nil || node.Name == "" {
		t.addError("invalid identifier", node)
		return &ast.Ident{Name: "_"}
	}

	return &ast.Ident{Name: t.generateVarName(node.Name)}
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

	// Map manuscript operators to Go operators
	var goOp token.Token
	switch node.Op {
	case mast.Add:
		goOp = token.ADD
	case mast.Subtract:
		goOp = token.SUB
	case mast.Multiply:
		goOp = token.MUL
	case mast.Divide:
		goOp = token.QUO
	case mast.Modulo:
		goOp = token.REM
	case mast.Equal:
		goOp = token.EQL
	case mast.NotEqual:
		goOp = token.NEQ
	case mast.Less:
		goOp = token.LSS
	case mast.LessEqual:
		goOp = token.LEQ
	case mast.Greater:
		goOp = token.GTR
	case mast.GreaterEqual:
		goOp = token.GEQ
	case mast.LogicalAnd:
		goOp = token.LAND
	case mast.LogicalOr:
		goOp = token.LOR
	case mast.BitwiseAnd:
		goOp = token.AND
	case mast.BitwiseXor:
		goOp = token.XOR
	default:
		t.addError("unsupported binary operator", node)
		goOp = token.ADD // fallback
	}

	// Handle string concatenation optimization
	if goOp == token.ADD {
		return t.optimizeStringConcat(leftExpr, rightExpr)
	}

	return &ast.BinaryExpr{
		X:  leftExpr,
		Op: goOp,
		Y:  rightExpr,
	}
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

	// Map manuscript unary operators to Go operators
	var goOp token.Token
	switch node.Op {
	case mast.UnaryNot:
		goOp = token.NOT
	case mast.UnaryMinus:
		goOp = token.SUB
	case mast.UnaryPlus:
		goOp = token.ADD
	default:
		t.addError("unsupported unary operator", node)
		goOp = token.NOT // fallback
	}

	return &ast.UnaryExpr{
		Op: goOp,
		X:  operandExpr,
	}
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
	for _, arg := range node.Args {
		if arg == nil {
			continue
		}

		argResult := t.Visit(arg)
		if argExpr, ok := argResult.(ast.Expr); ok {
			args = append(args, argExpr)
		}
	}

	return &ast.CallExpr{
		Fun:  funcExpr,
		Args: args,
	}
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

	return &ast.IndexExpr{
		X:     objectExpr,
		Index: indexExpr,
	}
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

	return &ast.SelectorExpr{
		X:   objectExpr,
		Sel: &ast.Ident{Name: t.generateVarName(node.Field)},
	}
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

	return &ast.FuncLit{
		Type: &ast.FuncType{
			Params:  &ast.FieldList{List: params},
			Results: results,
		},
		Body: body,
	}
}

// VisitTernaryExpr transpiles ternary expressions to if expressions
func (t *GoTranspiler) VisitTernaryExpr(node *mast.TernaryExpr) ast.Node {
	if node == nil {
		t.addError("invalid ternary expression", node)
		return nil
	}

	condition := t.Visit(node.Cond)
	thenExpr := t.Visit(node.Then)
	elseExpr := t.Visit(node.Else)

	condExpr, okCond := condition.(ast.Expr)
	thenGoExpr, okThen := thenExpr.(ast.Expr)
	elseGoExpr, okElse := elseExpr.(ast.Expr)

	if !okCond || !okThen || !okElse {
		t.addError("ternary expression parts are not valid expressions", node)
		return nil
	}

	// In Go, we need to create an IIFE (Immediately Invoked Function Expression)
	return &ast.CallExpr{
		Fun: &ast.FuncLit{
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
								&ast.ReturnStmt{Results: []ast.Expr{thenGoExpr}},
							},
						},
						Else: &ast.BlockStmt{
							List: []ast.Stmt{
								&ast.ReturnStmt{Results: []ast.Expr{elseGoExpr}},
							},
						},
					},
				},
			},
		},
		Args: []ast.Expr{},
	}
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
