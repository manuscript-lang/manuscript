package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitMethodsDecl(ctx *parser.MethodsDeclContext) interface{} {
	if ctx == nil {
		v.addError("VisitMethodsDecl called with nil context", nil)
		return nil
	}

	receiverNode := ctx.ID(0)
	receiverAliasNode := ctx.ID(1)
	if receiverNode == nil || receiverAliasNode == nil {
		v.addError("Methods declaration missing receiver or alias", ctx.GetStart())
		return nil
	}

	receiverType := ast.NewIdent(receiverNode.GetText())
	receiverAlias := receiverAliasNode.GetText()
	target := &ast.StarExpr{X: receiverType}
	var decls []ast.Decl

	if stmtListItems := ctx.Stmt_list_items(); stmtListItems != nil {
		for _, stmtCtx := range stmtListItems.AllStmt() {
			visited := v.Visit(stmtCtx) // Assuming Visit can handle IStmtContext and dispatch correctly
			if methodImpl, ok := visited.(*parser.MethodImplContext); ok {
				method := v.VisitMethodImplWithAlias(methodImpl, receiverAlias, receiverType.Name)
				fn, ok := method.(*ast.FuncDecl)
				if !ok || fn == nil {
					v.addError("Method implementation did not return a valid Go function", stmtCtx.GetStart())
					continue
				}
				fn.Recv = &ast.FieldList{
					List: []*ast.Field{{Names: []*ast.Ident{ast.NewIdent(receiverAlias)}, Type: target}},
				}
				decls = append(decls, fn)
			}
		}
	}
	return decls
}

func (v *ManuscriptAstVisitor) VisitMethodImpl(ctx *parser.MethodImplContext) interface{} {
	if ctx == nil || ctx.InterfaceMethod() == nil || ctx.InterfaceMethod().ID() == nil {
		v.addError("VisitMethodImpl called with nil or incomplete context", nil)
		return nil
	}
	nameId := ctx.InterfaceMethod().ID()
	paramsCtx := ctx.InterfaceMethod().Parameters()
	typeAnnotation := ctx.InterfaceMethod().TypeAnnotation()

	var paramDetailsList []ParamDetail
	var paramsAST *ast.FieldList
	var defaultAssignments []ast.Stmt
	if paramsCtx != nil {
		paramDetailsRaw := v.Visit(paramsCtx)
		if paramDetails, ok := paramDetailsRaw.([]ParamDetail); ok {
			paramDetailsList = paramDetails
			paramsAST, defaultAssignments = v.buildParamsAST(paramDetailsList)
		}
	} else {
		paramsAST = &ast.FieldList{List: []*ast.Field{}}
	}

	if ctx.CodeBlock() == nil {
		v.addError("No code block found for method "+nameId.GetText(), nameId.GetSymbol())
		return nil
	}
	concreteCodeBlockCtx, ok := ctx.CodeBlock().(*parser.CodeBlockContext)
	if !ok {
		v.addError("Internal error: Unexpected context type for code block in method "+nameId.GetText(), ctx.CodeBlock().GetStart())
		return nil
	}
	bodyInterface := v.Visit(concreteCodeBlockCtx)
	b, okBody := bodyInterface.(*ast.BlockStmt)
	if !okBody {
		v.addError("Method "+nameId.GetText()+" must have a valid code block body.", ctx.CodeBlock().GetStart())
		return nil
	}
	bodyAST := b
	if len(defaultAssignments) > 0 {
		newBodyList := append([]ast.Stmt{}, defaultAssignments...)
		newBodyList = append(newBodyList, bodyAST.List...)
		bodyAST.List = newBodyList
	}

	var lastExpr ast.Expr
	if len(bodyAST.List) > 0 {
		if exprStmt, ok := bodyAST.List[len(bodyAST.List)-1].(*ast.ExprStmt); ok {
			lastExpr = exprStmt.X
		} else if retStmt, ok := bodyAST.List[len(bodyAST.List)-1].(*ast.ReturnStmt); ok && len(retStmt.Results) > 0 {
			lastExpr = retStmt.Results[0]
		}
	}

	var resultsAST *ast.FieldList
	goFuncWillHaveReturn := false
	if typeAnnotation != nil {
		resultsAST = v.ProcessReturnType(typeAnnotation, nil, nameId.GetText())
		if resultsAST != nil && len(resultsAST.List) > 0 {
			goFuncWillHaveReturn = true
		}
	} else if lastExpr != nil {
		inferredType := v.inferTypeFromExpression(lastExpr, paramsAST)
		if inferredType != nil {
			resultsAST = &ast.FieldList{List: []*ast.Field{{Type: inferredType}}}
			goFuncWillHaveReturn = true
		}
	}

	if goFuncWillHaveReturn && len(bodyAST.List) > 0 {
		if exprStmt, ok := bodyAST.List[len(bodyAST.List)-1].(*ast.ExprStmt); ok && exprStmt.X == lastExpr {
			bodyAST.List[len(bodyAST.List)-1] = &ast.ReturnStmt{Return: exprStmt.X.Pos(), Results: []ast.Expr{exprStmt.X}}
		}
	}

	if bodyAST == nil {
		bodyAST = &ast.BlockStmt{}
	}

	var receiverType string
	if parent := ctx.GetParent(); parent != nil {
		if methodsDecl, ok := parent.(*parser.MethodsDeclContext); ok {
			if methodsDecl.ID(0) != nil {
				receiverType = methodsDecl.ID(0).GetText()
			}
		}
	}
	// Use the type name as both the receiver variable and type
	return &ast.FuncDecl{
		Recv: &ast.FieldList{List: []*ast.Field{{Names: []*ast.Ident{ast.NewIdent(receiverType)}, Type: &ast.StarExpr{X: ast.NewIdent(receiverType)}}}},
		Name: ast.NewIdent(nameId.GetText()),
		Type: &ast.FuncType{
			Params:  paramsAST,
			Results: resultsAST,
		},
		Body: bodyAST,
	}
}

// VisitMethodImplWithAlias is like VisitMethodImpl but takes the receiver alias and type name.
func (v *ManuscriptAstVisitor) VisitMethodImplWithAlias(ctx *parser.MethodImplContext, receiverAlias string, receiverType string) interface{} {
	if ctx == nil || ctx.InterfaceMethod() == nil || ctx.InterfaceMethod().ID() == nil {
		v.addError("VisitMethodImpl called with nil or incomplete context", nil)
		return nil
	}
	nameId := ctx.InterfaceMethod().ID()
	paramsCtx := ctx.InterfaceMethod().Parameters()
	typeAnnotation := ctx.InterfaceMethod().TypeAnnotation()

	var paramDetailsList []ParamDetail
	var paramsAST *ast.FieldList
	var defaultAssignments []ast.Stmt
	if paramsCtx != nil {
		paramDetailsRaw := v.Visit(paramsCtx)
		if paramDetails, ok := paramDetailsRaw.([]ParamDetail); ok {
			paramDetailsList = paramDetails
			paramsAST, defaultAssignments = v.buildParamsAST(paramDetailsList)
		}
	} else {
		paramsAST = &ast.FieldList{List: []*ast.Field{}}
	}

	if ctx.CodeBlock() == nil {
		v.addError("No code block found for method "+nameId.GetText(), nameId.GetSymbol())
		return nil
	}
	concreteCodeBlockCtx, ok := ctx.CodeBlock().(*parser.CodeBlockContext)
	if !ok {
		v.addError("Internal error: Unexpected context type for code block in method "+nameId.GetText(), ctx.CodeBlock().GetStart())
		return nil
	}
	bodyInterface := v.Visit(concreteCodeBlockCtx)
	b, okBody := bodyInterface.(*ast.BlockStmt)
	if !okBody {
		v.addError("Method "+nameId.GetText()+" must have a valid code block body.", ctx.CodeBlock().GetStart())
		return nil
	}
	bodyAST := b
	if len(defaultAssignments) > 0 {
		newBodyList := append([]ast.Stmt{}, defaultAssignments...)
		newBodyList = append(newBodyList, bodyAST.List...)
		bodyAST.List = newBodyList
	}

	var lastExpr ast.Expr
	if len(bodyAST.List) > 0 {
		if exprStmt, ok := bodyAST.List[len(bodyAST.List)-1].(*ast.ExprStmt); ok {
			lastExpr = exprStmt.X
		} else if retStmt, ok := bodyAST.List[len(bodyAST.List)-1].(*ast.ReturnStmt); ok && len(retStmt.Results) > 0 {
			lastExpr = retStmt.Results[0]
		}
	}

	var resultsAST *ast.FieldList
	goFuncWillHaveReturn := false
	if typeAnnotation != nil {
		resultsAST = v.ProcessReturnType(typeAnnotation, nil, nameId.GetText())
		if resultsAST != nil && len(resultsAST.List) > 0 {
			goFuncWillHaveReturn = true
		}
	} else if lastExpr != nil {
		inferredType := v.inferTypeFromExpression(lastExpr, paramsAST)
		if inferredType != nil {
			resultsAST = &ast.FieldList{List: []*ast.Field{{Type: inferredType}}}
			goFuncWillHaveReturn = true
		}
	}

	if goFuncWillHaveReturn && len(bodyAST.List) > 0 {
		if exprStmt, ok := bodyAST.List[len(bodyAST.List)-1].(*ast.ExprStmt); ok && exprStmt.X == lastExpr {
			bodyAST.List[len(bodyAST.List)-1] = &ast.ReturnStmt{Return: exprStmt.X.Pos(), Results: []ast.Expr{exprStmt.X}}
		}
	}

	if bodyAST == nil {
		bodyAST = &ast.BlockStmt{}
	}

	return &ast.FuncDecl{
		Recv: &ast.FieldList{List: []*ast.Field{{Names: []*ast.Ident{ast.NewIdent(receiverAlias)}, Type: &ast.StarExpr{X: ast.NewIdent(receiverType)}}}},
		Name: ast.NewIdent(nameId.GetText()),
		Type: &ast.FuncType{
			Params:  paramsAST,
			Results: resultsAST,
		},
		Body: bodyAST,
	}
}
