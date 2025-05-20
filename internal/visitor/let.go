package visitor

import (
	"go/ast"
	"go/token"
	msParser "manuscript-co/manuscript/internal/parser"
	"strconv"
)

// It can return a single ast.Stmt or a []ast.Stmt if the 'let' expands to multiple Go statements.
func (v *ManuscriptAstVisitor) VisitLetDecl(ctx *msParser.LetDeclContext) interface{} {
	if singleLetCtx := ctx.LetSingle(); singleLetCtx != nil {
		return v.Visit(singleLetCtx)
	}
	if blockLetCtx := ctx.LetBlock(); blockLetCtx != nil {
		return v.Visit(blockLetCtx)
	}
	if destructuredObjCtx := ctx.LetDestructuredObj(); destructuredObjCtx != nil {
		return v.Visit(destructuredObjCtx)
	}
	if destructuredArrayCtx := ctx.LetDestructuredArray(); destructuredArrayCtx != nil {
		return v.Visit(destructuredArrayCtx)
	}
	v.addError("Unrecognized let declaration structure: "+ctx.GetText(), ctx.GetStart())
	return &ast.EmptyStmt{}
}

// VisitLetSingle handles 'let typedID = expr' or 'let typedID'
// ctx is parser.ILetSingleContext
func (v *ManuscriptAstVisitor) VisitLetSingle(ctx *msParser.LetSingleContext) interface{} {
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
	} else if ctx.EQUALS() != nil && ctx.Expr() == nil {
		v.addError("Incomplete assignment in single let: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	} else {
		return &ast.DeclStmt{
			Decl: &ast.GenDecl{
				Tok: token.VAR,
				Specs: []ast.Spec{
					&ast.ValueSpec{Names: []*ast.Ident{ident}},
				},
			},
		}
	}
}

// It can return a single ast.Stmt or a []ast.Stmt if the 'let' expands to multiple Go statements.
func (v *ManuscriptAstVisitor) VisitLetBlock(ctx *msParser.LetBlockContext) interface{} {
	blockItems := ctx.AllLetBlockItem()
	if len(blockItems) == 0 {
		return &ast.EmptyStmt{}
	}
	var stmts []ast.Stmt
	for _, itemCtx := range blockItems {
		visitedItem := v.Visit(itemCtx)
		if individualStmts, ok := visitedItem.([]ast.Stmt); ok {
			stmts = append(stmts, individualStmts...)
		}
	}
	if len(stmts) == 1 {
		return stmts[0]
	}
	return stmts
}

// VisitLetDestructuredObj handles 'let {id1, id2} = expr' or 'let {id1, id2}'
// ctx is parser.ILetDestructuredObjContext
func (v *ManuscriptAstVisitor) VisitLetDestructuredObj(ctx *msParser.LetDestructuredObjContext) interface{} {
	if ctx.TypedIDList() == nil {
		v.addError("Object destructuring pattern is malformed: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	var lhsIdents []*ast.Ident
	typedIDListCtx := ctx.TypedIDList().(*msParser.TypedIDListContext)
	for _, typedIDInterface := range typedIDListCtx.AllTypedID() {
		idVisited := v.Visit(typedIDInterface)
		if ident, isIdent := idVisited.(*ast.Ident); isIdent {
			lhsIdents = append(lhsIdents, ident)
		}
	}
	if len(lhsIdents) == 0 {
		v.addError("Object destructuring pattern resulted in no LHS: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	if ctx.EQUALS() != nil && ctx.Expr() != nil {
		rhsVisited := v.Visit(ctx.Expr())
		rhsExpr, okExpr := rhsVisited.(ast.Expr)
		if !okExpr {
			v.addError("RHS of object destructuring is not an expression: "+ctx.Expr().GetText(), ctx.Expr().GetStart())
			return &ast.EmptyStmt{}
		}
		var generatedStmts []ast.Stmt
		tempVarIdent := ast.NewIdent("__val" + v.nextTempVarCounter())
		generatedStmts = append(generatedStmts, &ast.AssignStmt{
			Lhs: []ast.Expr{tempVarIdent},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{rhsExpr},
		})
		for _, ident := range lhsIdents {
			generatedStmts = append(generatedStmts, &ast.AssignStmt{
				Lhs: []ast.Expr{ast.NewIdent(ident.Name)},
				Tok: token.DEFINE,
				Rhs: []ast.Expr{&ast.SelectorExpr{X: tempVarIdent, Sel: ast.NewIdent(ident.Name)}},
			})
		}
		return &ast.BlockStmt{List: generatedStmts}
	} else if ctx.EQUALS() != nil && ctx.Expr() == nil {
		v.addError("Incomplete assignment in object destructuring: "+ctx.GetText(), ctx.GetStart())
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

// VisitLetDestructuredArray handles 'let [id1, id2] = expr' or 'let [id1, id2]'
// ctx is parser.ILetDestructuredArrayContext
func (v *ManuscriptAstVisitor) VisitLetDestructuredArray(ctx *msParser.LetDestructuredArrayContext) interface{} {
	if ctx.TypedIDList() == nil {
		v.addError("Array destructuring pattern is malformed: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	var lhsIdents []*ast.Ident
	typedIDListCtx := ctx.TypedIDList().(*msParser.TypedIDListContext)
	for _, typedIDInterface := range typedIDListCtx.AllTypedID() {
		idVisited := v.Visit(typedIDInterface)
		if ident, isIdent := idVisited.(*ast.Ident); isIdent {
			lhsIdents = append(lhsIdents, ident)
		}
	}
	if len(lhsIdents) == 0 {
		v.addError("Array destructuring pattern resulted in no LHS: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	if ctx.EQUALS() != nil && ctx.Expr() != nil {
		rhsVisited := v.Visit(ctx.Expr())
		rhsExpr, okExpr := rhsVisited.(ast.Expr)
		if !okExpr {
			v.addError("RHS of array destructuring is not an expression: "+ctx.Expr().GetText(), ctx.Expr().GetStart())
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
	} else if ctx.EQUALS() != nil && ctx.Expr() == nil {
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

// Type information is currently ignored for let LHS.
func (v *ManuscriptAstVisitor) VisitTypedID(ctx *msParser.TypedIDContext) interface{} {
	if ctx.NamedID() != nil {
		return v.Visit(ctx.NamedID())
	}
	v.addError("TypedID does not have a NamedID: "+ctx.GetText(), ctx.GetStart())
	return nil
}

// This is part of the ANTLR generated visitor interface if NamedID is a parser rule.
// We provide a concrete implementation.
func (v *ManuscriptAstVisitor) VisitNamedID(ctx *msParser.NamedIDContext) interface{} {
	if ctx.ID() != nil {
		return ast.NewIdent(ctx.ID().GetText())
	}
	v.addError("NamedID does not have an ID: "+ctx.GetText(), ctx.GetStart())
	return nil
}

func (v *ManuscriptAstVisitor) VisitTypedIDList(ctx *msParser.TypedIDListContext) interface{} {
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
func (v *ManuscriptAstVisitor) VisitLetBlockItemSingle(ctx *msParser.LetBlockItemSingleContext) interface{} {
	lhsVisited := v.Visit(ctx.GetLhsTypedId())
	lhsIdent, okLHS := lhsVisited.(*ast.Ident)
	if !okLHS {
		v.addError("LHS of let block item is not an identifier: "+ctx.GetLhsTypedId().GetText(), ctx.GetLhsTypedId().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	rhsVisited := v.Visit(ctx.GetRhsExpr())
	rhsExpr, okRHS := rhsVisited.(ast.Expr)
	if !okRHS {
		v.addError("RHS of let block item is not an expression: "+ctx.GetRhsExpr().GetText(), ctx.GetRhsExpr().GetStart())
		return []ast.Stmt{&ast.BadStmt{}}
	}
	return []ast.Stmt{
		&ast.AssignStmt{
			Lhs: []ast.Expr{lhsIdent}, Tok: token.DEFINE, Rhs: []ast.Expr{rhsExpr},
		},
	}
}

// VisitLetBlockItemDestructuredObj handles: LBRACE TypedIDList RBRACE EQUALS expr
func (v *ManuscriptAstVisitor) VisitLetBlockItemDestructuredObj(ctx *msParser.LetBlockItemDestructuredObjContext) interface{} {
	var lhsIdents []*ast.Ident
	typedIDListCtx := ctx.GetLhsDestructuredIdsObj().(*msParser.TypedIDListContext)
	for _, typedIDInterface := range typedIDListCtx.AllTypedID() {
		idVisited := v.Visit(typedIDInterface)
		if ident, isIdent := idVisited.(*ast.Ident); isIdent {
			lhsIdents = append(lhsIdents, ident)
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
func (v *ManuscriptAstVisitor) VisitLetBlockItemDestructuredArray(ctx *msParser.LetBlockItemDestructuredArrayContext) interface{} {
	var lhsIdents []*ast.Ident
	typedIDListCtx := ctx.GetLhsDestructuredIdsArr().(*msParser.TypedIDListContext)
	for _, typedIDInterface := range typedIDListCtx.AllTypedID() {
		idVisited := v.Visit(typedIDInterface)
		if ident, isIdent := idVisited.(*ast.Ident); isIdent {
			lhsIdents = append(lhsIdents, ident)
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
