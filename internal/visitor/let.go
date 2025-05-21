package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

// VisitLetDecl handles variable declarations starting with 'let' keyword.
// let x = 5, let {a, b} = obj, etc.
func (v *ManuscriptAstVisitor) VisitLetDecl(ctx *parser.LetDeclContext) interface{} {
	if ctx == nil {
		v.addError("VisitLetDecl called with nil context", nil)
		return &ast.EmptyStmt{}
	}

	letPattern := ctx.LetPattern()
	if letPattern == nil {
		v.addError("Let declaration missing pattern: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}

	return v.Visit(letPattern)
}

// VisitLetPatternSingle handles the simple variable declaration:
// let x = 5, let y: int
func (v *ManuscriptAstVisitor) VisitLetPatternSingle(ctx *parser.LetPatternSingleContext) interface{} {
	if ctx.LetSingle() == nil {
		v.addError("LetPatternSingle missing LetSingle", ctx.GetStart())
		return []ast.Stmt{&ast.EmptyStmt{}}
	}

	return v.Visit(ctx.LetSingle())
}

// VisitLetPatternBlock handles grouped variable declarations:
// let (x = 1, y = 2)
func (v *ManuscriptAstVisitor) VisitLetPatternBlock(ctx *parser.LetPatternBlockContext) interface{} {
	if ctx.LetBlock() == nil {
		v.addError("LetPatternBlock missing LetBlock", ctx.GetStart())
		return []ast.Stmt{&ast.EmptyStmt{}}
	}

	return v.Visit(ctx.LetBlock())
}

// VisitLetPatternDestructuredObj handles object destructuring:
// let {x, y} = point
func (v *ManuscriptAstVisitor) VisitLetPatternDestructuredObj(ctx *parser.LetPatternDestructuredObjContext) interface{} {
	if ctx.LetDestructuredObj() == nil {
		v.addError("LetPatternDestructuredObj missing LetDestructuredObj", ctx.GetStart())
		return []ast.Stmt{&ast.EmptyStmt{}}
	}

	return v.Visit(ctx.LetDestructuredObj())
}

// VisitLetPatternDestructuredArray handles array destructuring:
// let [first, second] = arr
func (v *ManuscriptAstVisitor) VisitLetPatternDestructuredArray(ctx *parser.LetPatternDestructuredArrayContext) interface{} {
	if ctx.LetDestructuredArray() == nil {
		v.addError("LetPatternDestructuredArray missing LetDestructuredArray", ctx.GetStart())
		return []ast.Stmt{&ast.EmptyStmt{}}
	}

	return v.Visit(ctx.LetDestructuredArray())
}

// VisitTypedID processes a variable identifier with optional type annotation
// Variable types are currently handled separately from the identifier
func (v *ManuscriptAstVisitor) VisitTypedID(ctx *parser.TypedIDContext) interface{} {
	if ctx.ID() == nil {
		v.addError("Variable declaration missing identifier", ctx.GetStart())
		return nil
	}

	// Create an identifier node from the variable name
	return ast.NewIdent(ctx.ID().GetText())
}

// VisitTypedIDList processes a list of typed identifiers
// e.g., x: int, y: string
func (v *ManuscriptAstVisitor) VisitTypedIDList(ctx *parser.TypedIDListContext) interface{} {
	var idents []*ast.Ident

	for _, typedIDCtx := range ctx.AllTypedID() {
		result := v.Visit(typedIDCtx)
		if ident, ok := result.(*ast.Ident); ok {
			idents = append(idents, ident)
		} else {
			v.addError("Expected identifier in variable list", typedIDCtx.GetStart())
		}
	}

	return idents
}

// VisitLetBlockItemSingle handles a single variable declaration in a let block
// e.g., x = 5 in let (x = 5, y = 10)
func (v *ManuscriptAstVisitor) VisitLetBlockItemSingle(ctx *parser.LetBlockItemSingleContext) interface{} {
	// Get the left-hand side identifier
	lhsResult := v.Visit(ctx.TypedID())
	lhsIdent, ok := lhsResult.(*ast.Ident)
	if !ok {
		v.addError("Left side of assignment is not a valid identifier", ctx.TypedID().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}

	// Process right-hand side expression if present
	if ctx.Expr() != nil {
		rhsResult := v.Visit(ctx.Expr())
		if rhsExpr, ok := rhsResult.(ast.Expr); ok {
			// Return a short variable declaration (`:=`)
			return []ast.Stmt{
				&ast.AssignStmt{
					Lhs: []ast.Expr{lhsIdent},
					Tok: token.DEFINE,
					Rhs: []ast.Expr{rhsExpr},
				},
			}
		}
	}

	// If no expression or expression didn't evaluate properly,
	// create a variable declaration without initialization
	return []ast.Stmt{
		&ast.DeclStmt{
			Decl: &ast.GenDecl{
				Tok:   token.VAR,
				Specs: []ast.Spec{&ast.ValueSpec{Names: []*ast.Ident{lhsIdent}}},
			},
		},
	}
}

// VisitLetBlockItemDestructuredObj handles object destructuring in a let block
// e.g., {x, y} = point in let ({x, y} = point)
func (v *ManuscriptAstVisitor) VisitLetBlockItemDestructuredObj(ctx *parser.LetBlockItemDestructuredObjContext) interface{} {
	// Get list of variables to assign from destructuring
	typedIDListResult := v.Visit(ctx.TypedIDList())
	lhsIdents, ok := typedIDListResult.([]*ast.Ident)
	if !ok || len(lhsIdents) == 0 {
		v.addError("Object destructuring has no valid identifiers", ctx.TypedIDList().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}

	// Get the expression to destructure
	rhsResult := v.Visit(ctx.Expr())
	rhsExpr, ok := rhsResult.(ast.Expr)
	if !ok {
		v.addError("Invalid expression in object destructuring", ctx.Expr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}

	// Create a temporary variable to hold the object
	tempVarName := "__val" + v.nextTempVarCounter()
	tempVarIdent := ast.NewIdent(tempVarName)

	// Create statements for destructuring
	stmts := []ast.Stmt{
		// First assign the object to a temp variable
		&ast.AssignStmt{
			Lhs: []ast.Expr{tempVarIdent},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{rhsExpr},
		},
	}

	// Create an assignment for each field to extract
	for _, ident := range lhsIdents {
		stmts = append(stmts, &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent(ident.Name)},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{
				&ast.SelectorExpr{
					X:   tempVarIdent,
					Sel: ast.NewIdent(ident.Name),
				},
			},
		})
	}

	return stmts
}

// VisitLetBlockItemDestructuredArray handles array destructuring in a let block
// e.g., [first, second] = arr in let ([first, second] = arr)
func (v *ManuscriptAstVisitor) VisitLetBlockItemDestructuredArray(ctx *parser.LetBlockItemDestructuredArrayContext) interface{} {
	// Get list of variables to assign from destructuring
	typedIDListResult := v.Visit(ctx.TypedIDList())
	lhsIdents, ok := typedIDListResult.([]*ast.Ident)
	if !ok || len(lhsIdents) == 0 {
		v.addError("Array destructuring has no valid identifiers", ctx.TypedIDList().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}

	// Get the expression to destructure
	rhsResult := v.Visit(ctx.Expr())
	rhsExpr, ok := rhsResult.(ast.Expr)
	if !ok {
		v.addError("Invalid expression in array destructuring", ctx.Expr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}

	// Create a temporary variable to hold the array
	tempVarName := "__val" + v.nextTempVarCounter()
	tempVarIdent := ast.NewIdent(tempVarName)

	// Create statements for destructuring
	stmts := []ast.Stmt{
		// First assign the array to a temp variable
		&ast.AssignStmt{
			Lhs: []ast.Expr{tempVarIdent},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{rhsExpr},
		},
	}

	// Create an assignment for each element to extract by index
	for i, ident := range lhsIdents {
		stmts = append(stmts, &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent(ident.Name)},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{
				&ast.IndexExpr{
					X:     tempVarIdent,
					Index: &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(i)},
				},
			},
		})
	}

	return stmts
}

// VisitLetSingle handles a standalone variable declaration
// let x = 5 or let y: int
func (v *ManuscriptAstVisitor) VisitLetSingle(ctx *parser.LetSingleContext) interface{} {
	if ctx.TypedID() == nil {
		v.addError("Variable declaration missing identifier", ctx.GetStart())
		return []ast.Stmt{&ast.EmptyStmt{}}
	}

	// Get the variable identifier
	identResult := v.Visit(ctx.TypedID())
	ident, ok := identResult.(*ast.Ident)
	if !ok {
		v.addError("Invalid identifier in variable declaration", ctx.TypedID().GetStart())
		return []ast.Stmt{&ast.EmptyStmt{}}
	}

	// If there's an initializer expression
	if ctx.EQUALS() != nil && ctx.Expr() != nil {
		valueResult := v.Visit(ctx.Expr())
		if sourceExpr, ok := valueResult.(ast.Expr); ok {
			// Create a short variable declaration (`:=`)
			return []ast.Stmt{
				&ast.AssignStmt{
					Lhs: []ast.Expr{ident},
					Tok: token.DEFINE,
					Rhs: []ast.Expr{sourceExpr},
				},
			}
		} else {
			v.addError("Invalid expression in variable initialization", ctx.Expr().GetStart())
		}
	}

	// If no initializer or it failed, create a variable declaration without initialization
	return []ast.Stmt{
		&ast.DeclStmt{
			Decl: &ast.GenDecl{
				Tok: token.VAR,
				Specs: []ast.Spec{
					&ast.ValueSpec{
						Names: []*ast.Ident{ident},
					},
				},
			},
		},
	}
}

// VisitLetBlock handles a group of variable declarations
// let (x = 1, y = 2, {a, b} = obj)
func (v *ManuscriptAstVisitor) VisitLetBlock(ctx *parser.LetBlockContext) interface{} {
	var stmts []ast.Stmt

	for _, itemCtx := range ctx.AllLetBlockItem() {
		result := v.Visit(itemCtx)
		if itemStmts, ok := result.([]ast.Stmt); ok {
			stmts = append(stmts, itemStmts...)
		} else {
			v.addError("Invalid let block item", itemCtx.GetStart())
		}
	}

	return stmts
}

// VisitLetDestructuredObj handles object destructuring at the top level
// let {x, y} = point
func (v *ManuscriptAstVisitor) VisitLetDestructuredObj(ctx *parser.LetDestructuredObjContext) interface{} {
	// Get list of variables to assign from destructuring
	typedIDListResult := v.Visit(ctx.TypedIDList())
	lhsIdents, ok := typedIDListResult.([]*ast.Ident)
	if !ok || len(lhsIdents) == 0 {
		v.addError("Object destructuring has no valid identifiers", ctx.TypedIDList().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}

	// Get the expression to destructure
	rhsResult := v.Visit(ctx.Expr())
	rhsExpr, ok := rhsResult.(ast.Expr)
	if !ok {
		v.addError("Invalid expression in object destructuring", ctx.Expr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}

	// Create statements for destructuring similar to VisitLetBlockItemDestructuredObj
	tempVarName := "__val" + v.nextTempVarCounter()
	tempVarIdent := ast.NewIdent(tempVarName)

	stmts := []ast.Stmt{
		&ast.AssignStmt{
			Lhs: []ast.Expr{tempVarIdent},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{rhsExpr},
		},
	}

	for _, ident := range lhsIdents {
		stmts = append(stmts, &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent(ident.Name)},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{
				&ast.SelectorExpr{
					X:   tempVarIdent,
					Sel: ast.NewIdent(ident.Name),
				},
			},
		})
	}

	return stmts
}

// VisitLetDestructuredArray handles array destructuring at the top level
// let [first, second] = arr
func (v *ManuscriptAstVisitor) VisitLetDestructuredArray(ctx *parser.LetDestructuredArrayContext) interface{} {
	// Get list of variables to assign from destructuring
	typedIDListResult := v.Visit(ctx.TypedIDList())
	lhsIdents, ok := typedIDListResult.([]*ast.Ident)
	if !ok || len(lhsIdents) == 0 {
		v.addError("Array destructuring has no valid identifiers", ctx.TypedIDList().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}

	// Get the expression to destructure
	rhsResult := v.Visit(ctx.Expr())
	rhsExpr, ok := rhsResult.(ast.Expr)
	if !ok {
		v.addError("Invalid expression in array destructuring", ctx.Expr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}

	// Create statements for destructuring similar to VisitLetBlockItemDestructuredArray
	tempVarName := "__val" + v.nextTempVarCounter()
	tempVarIdent := ast.NewIdent(tempVarName)

	stmts := []ast.Stmt{
		&ast.AssignStmt{
			Lhs: []ast.Expr{tempVarIdent},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{rhsExpr},
		},
	}

	for i, ident := range lhsIdents {
		stmts = append(stmts, &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent(ident.Name)},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{
				&ast.IndexExpr{
					X:     tempVarIdent,
					Index: &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(i)},
				},
			},
		})
	}

	return stmts
}
