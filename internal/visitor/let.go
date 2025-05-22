package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"

	"github.com/antlr4-go/antlr/v4"
)

// DRY helper for destructured let (object/array)
func (v *ManuscriptAstVisitor) destructuredLet(
	typedIDListCtx parser.ITypedIDListContext,
	rhsExprCtx parser.IExprContext,
	isArray bool,
	getRhs func(tempVar *ast.Ident, idx int, name string) ast.Expr,
	ctx antlr.ParserRuleContext,
) interface{} {
	if typedIDListCtx == nil {
		v.addError("Destructuring pattern is malformed: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	var lhsIdents []*ast.Ident
	typedIDList := v.Visit(typedIDListCtx)
	if idSlice, ok := typedIDList.([]*ast.Ident); ok {
		lhsIdents = idSlice
	} else {
		v.addError("Destructuring pattern did not resolve to identifiers: "+typedIDListCtx.GetText(), typedIDListCtx.GetStart())
		return &ast.EmptyStmt{}
	}
	if len(lhsIdents) == 0 {
		v.addError("Destructuring pattern resulted in no LHS: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	if rhsExprCtx != nil {
		rhsVisited := v.Visit(rhsExprCtx)
		rhsExpr, okExpr := rhsVisited.(ast.Expr)
		if !okExpr {
			v.addError("RHS of destructuring is not an expression: "+rhsExprCtx.GetText(), rhsExprCtx.GetStart())
			return &ast.EmptyStmt{}
		}
		tempVarIdent := ast.NewIdent("__val" + v.nextTempVarCounter())
		var stmts []ast.Stmt
		stmts = append(stmts, &ast.AssignStmt{
			Lhs: []ast.Expr{tempVarIdent},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{rhsExpr},
		})
		for i, ident := range lhsIdents {
			var rhs ast.Expr
			if isArray {
				rhs = getRhs(tempVarIdent, i, ident.Name)
			} else {
				rhs = getRhs(tempVarIdent, i, ident.Name)
			}
			stmts = append(stmts, &ast.AssignStmt{
				Lhs: []ast.Expr{ast.NewIdent(ident.Name)},
				Tok: token.DEFINE,
				Rhs: []ast.Expr{rhs},
			})
		}
		return &ast.BlockStmt{List: stmts}
	} else {
		return &ast.DeclStmt{
			Decl: &ast.GenDecl{
				Tok:   token.VAR,
				Specs: []ast.Spec{&ast.ValueSpec{Names: lhsIdents}},
			},
		}
	}
}

// VisitLetDestructuredObj handles 'let {id1, id2} = expr' or 'let {id1, id2}'
func (v *ManuscriptAstVisitor) VisitLetDestructuredObj(ctx *parser.LetDestructuredObjContext) interface{} {
	return v.destructuredLet(
		ctx.TypedIDList(),
		ctx.Expr(),
		false,
		func(tempVar *ast.Ident, _ int, name string) ast.Expr {
			return &ast.SelectorExpr{X: tempVar, Sel: ast.NewIdent(name)}
		},
		ctx,
	)
}

// VisitLetDestructuredArray handles 'let [id1, id2] = expr' or 'let [id1, id2]'
func (v *ManuscriptAstVisitor) VisitLetDestructuredArray(ctx *parser.LetDestructuredArrayContext) interface{} {
	return v.destructuredLet(
		ctx.TypedIDList(),
		ctx.Expr(),
		true,
		func(tempVar *ast.Ident, idx int, _ string) ast.Expr {
			return &ast.IndexExpr{X: tempVar, Index: &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(idx)}}
		},
		ctx,
	)
}

// Type information is currently ignored for let LHS.
func (v *ManuscriptAstVisitor) VisitTypedID(ctx *parser.TypedIDContext) interface{} {
	if ctx.ID() != nil {
		return ast.NewIdent(ctx.ID().GetText())
	}
	v.addError("NamedID does not have an ID: "+ctx.GetText(), ctx.GetStart())
	return nil
}

func (v *ManuscriptAstVisitor) VisitTypedIDList(ctx *parser.TypedIDListContext) interface{} {
	var idents []*ast.Ident
	for _, typedIDCtx := range ctx.AllTypedID() {
		visitedIdent := v.Visit(typedIDCtx)
		if ident, ok := visitedIdent.(*ast.Ident); ok {
			idents = append(idents, ident)
		}
	}
	return idents
}

// VisitLetBlockItemSingle handles: lhsTypedId = typedID EQUALS rhsExpr = expr
func (v *ManuscriptAstVisitor) VisitLabelLetBlockItemSingle(ctx *parser.LabelLetBlockItemSingleContext) interface{} {
	lhsVisited := v.Visit(ctx.TypedID())
	lhsIdent, okLHS := lhsVisited.(*ast.Ident)
	if !okLHS {
		v.addError("LHS of let block item is not an identifier: "+ctx.TypedID().GetText(), ctx.TypedID().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	rhsVisited := v.Visit(ctx.Expr())
	rhsExpr, okRHS := rhsVisited.(ast.Expr)
	if !okRHS {
		v.addError("RHS of let block item is not an expression: "+ctx.Expr().GetText(), ctx.Expr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	return []ast.Stmt{
		&ast.AssignStmt{
			Lhs: []ast.Expr{lhsIdent}, Tok: token.DEFINE, Rhs: []ast.Expr{rhsExpr},
		},
	}
}

// VisitLetBlockItemDestructuredObj handles: LBRACE TypedIDList RBRACE EQUALS expr
func (v *ManuscriptAstVisitor) VisitLabelLetBlockItemDestructuredObj(ctx *parser.LabelLetBlockItemDestructuredObjContext) interface{} {
	var lhsIdents []*ast.Ident
	typedIDListCtx := ctx.TypedIDList().(*parser.TypedIDListContext)
	for _, typedIDInterface := range typedIDListCtx.AllTypedID() {
		idVisited := v.Visit(typedIDInterface)
		if ident, isIdent := idVisited.(*ast.Ident); isIdent {
			lhsIdents = append(lhsIdents, ident)
		}
	}
	if len(lhsIdents) == 0 {
		v.addError("Let block object destructuring no LHS: "+ctx.TypedIDList().GetText(), ctx.TypedIDList().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	rhsVisited := v.Visit(ctx.Expr())
	rhsExpr, okRHS := rhsVisited.(ast.Expr)
	if !okRHS {
		v.addError("RHS of let block object destructuring not expr: "+ctx.Expr().GetText(), ctx.Expr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	tempVarIdent := ast.NewIdent("__val" + v.nextTempVarCounter())
	stmts := []ast.Stmt{
		&ast.AssignStmt{
			Lhs: []ast.Expr{tempVarIdent}, Tok: token.DEFINE, Rhs: []ast.Expr{rhsExpr},
		},
	}
	for _, ident := range lhsIdents {
		stmts = append(stmts, &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent(ident.Name)}, Tok: token.DEFINE,
			Rhs: []ast.Expr{&ast.SelectorExpr{X: tempVarIdent, Sel: ast.NewIdent(ident.Name)}},
		})
	}
	return stmts
}

// VisitLetBlockItemDestructuredArray handles: LSQBR TypedIDList RSQBR EQUALS expr
func (v *ManuscriptAstVisitor) VisitLabelLetBlockItemDestructuredArray(ctx *parser.LabelLetBlockItemDestructuredArrayContext) interface{} {
	var lhsIdents []*ast.Ident
	typedIDListCtx := ctx.TypedIDList().(*parser.TypedIDListContext)
	for _, typedIDInterface := range typedIDListCtx.AllTypedID() {
		idVisited := v.Visit(typedIDInterface)
		if ident, isIdent := idVisited.(*ast.Ident); isIdent {
			lhsIdents = append(lhsIdents, ident)
		}
	}
	if len(lhsIdents) == 0 {
		v.addError("Let block array destructuring no LHS: "+ctx.TypedIDList().GetText(), ctx.TypedIDList().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	rhsVisited := v.Visit(ctx.Expr())
	rhsExpr, okRHS := rhsVisited.(ast.Expr)
	if !okRHS {
		v.addError("RHS of let block array destructuring not expr: "+ctx.Expr().GetText(), ctx.Expr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	tempVarIdent := ast.NewIdent("__val" + v.nextTempVarCounter())
	stmts := []ast.Stmt{
		&ast.AssignStmt{
			Lhs: []ast.Expr{tempVarIdent}, Tok: token.DEFINE, Rhs: []ast.Expr{rhsExpr},
		},
	}
	for i, ident := range lhsIdents {
		stmts = append(stmts, &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent(ident.Name)}, Tok: token.DEFINE,
			Rhs: []ast.Expr{&ast.IndexExpr{X: tempVarIdent, Index: &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(i)}}},
		})
	}
	return stmts
}

// VisitLetSingle handles 'let typedID = expr' or 'let typedID'
func (v *ManuscriptAstVisitor) VisitLetSingle(ctx *parser.LetSingleContext) interface{} {
	if ctx.TypedID() == nil {
		v.addError("Missing pattern in single let assignment: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	patternRaw := v.Visit(ctx.TypedID())
	ident, ok := patternRaw.(*ast.Ident)
	if !ok {
		v.addError("Pattern did not evaluate to an identifier: "+ctx.TypedID().GetText(), ctx.TypedID().GetStart())
		return &ast.EmptyStmt{}
	}
	if ctx.EQUALS() != nil && ctx.Expr() != nil {
		valueVisited := v.Visit(ctx.Expr())
		sourceExpr, okVal := valueVisited.(ast.Expr)
		if !okVal {
			v.addError("Value did not evaluate to an expression: "+ctx.Expr().GetText(), ctx.Expr().GetStart())
			return &ast.EmptyStmt{}
		}
		return &ast.AssignStmt{
			Lhs: []ast.Expr{ident},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{sourceExpr},
		}
	}
	return &ast.DeclStmt{
		Decl: &ast.GenDecl{
			Tok:   token.VAR,
			Specs: []ast.Spec{&ast.ValueSpec{Names: []*ast.Ident{ident}}},
		},
	}
}

// VisitLetBlockItemList aggregates all let block items into a flat []ast.Stmt
func (v *ManuscriptAstVisitor) VisitLetBlockItemList(ctx *parser.LetBlockItemListContext) interface{} {
	if ctx == nil {
		v.addError("VisitLetBlockItemList called with nil context", nil)
		return []ast.Stmt{&ast.BadStmt{}}
	}
	var stmts []ast.Stmt
	for _, itemCtx := range ctx.AllLetBlockItem() {
		itemResult := v.Visit(itemCtx)
		if itemResult == nil {
			continue
		}
		if stmt, ok := itemResult.(ast.Stmt); ok {
			stmts = append(stmts, stmt)
		} else if stmtList, ok := itemResult.([]ast.Stmt); ok {
			stmts = append(stmts, stmtList...)
		} else {
			v.addError("LetBlockItem did not return ast.Stmt or []ast.Stmt", itemCtx.GetStart())
		}
	}
	return stmts
}
