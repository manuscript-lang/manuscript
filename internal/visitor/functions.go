package visitor

import (
	"fmt"
	"go/ast"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// VisitFnDecl handles function declarations.
// fn foo(a: TypeA, b: TypeB = defaultVal): ReturnType! { body }
func (v *ManuscriptAstVisitor) VisitFnDecl(ctx *parser.FnDeclContext) interface{} {
	fnSig := ctx.FnSignature()
	if fnSig == nil {
		v.addError("Function declaration is missing signature.", ctx.GetStart())
		return nil
	}
	fnName := ""
	fnNameToken := fnSig.GetStart()
	if fnSig.ID() != nil {
		fnName = fnSig.ID().GetText()
		fnNameToken = fnSig.ID().GetSymbol()
	}
	paramsCtx := fnSig.Parameters()
	typeAnnotation := fnSig.TypeAnnotation()

	var paramDetailsList []ParamDetail
	var paramsAST *ast.FieldList
	var defaultAssignments []ast.Stmt
	if paramsCtx != nil {
		if details, ok := v.VisitParameters(paramsCtx.(*parser.ParametersContext)).([]ParamDetail); ok {
			paramDetailsList = details
			paramsAST, defaultAssignments = v.buildParamsAST(paramDetailsList)
		}
	} else {
		paramsAST = &ast.FieldList{List: []*ast.Field{}}
	}

	if ctx.CodeBlock() == nil {
		v.addError(fmt.Sprintf("No code block found for function '%s'.", fnName), fnNameToken)
		return nil
	}
	concreteCodeBlockCtx, ok := ctx.CodeBlock().(*parser.CodeBlockContext)
	if !ok {
		v.addError(fmt.Sprintf("Internal error: Unexpected context type for code block in function '%s'.", fnName), ctx.CodeBlock().GetStart())
		return nil
	}
	bodyInterface := v.Visit(concreteCodeBlockCtx)
	b, okBody := bodyInterface.(*ast.BlockStmt)
	if !okBody {
		v.addError(fmt.Sprintf("Function '%s' must have a valid code block body.", fnName), ctx.CodeBlock().GetStart())
		return nil
	}
	bodyAST := b
	if len(defaultAssignments) > 0 {
		newBodyList := append([]ast.Stmt{}, defaultAssignments...)
		newBodyList = append(newBodyList, bodyAST.List...)
		bodyAST.List = newBodyList
	}

	var resultsAST *ast.FieldList
	if typeAnnotation != nil || fnSig.EXCLAMATION() != nil {
		resultsAST = v.ProcessReturnType(typeAnnotation, fnSig.EXCLAMATION(), fnName)
	}

	// Only convert last expression statement to return if function has a non-void return type
	if resultsAST != nil && len(resultsAST.List) > 0 && len(bodyAST.List) > 0 {
		if exprStmt, ok := bodyAST.List[len(bodyAST.List)-1].(*ast.ExprStmt); ok && exprStmt.X != nil {
			// Special case: if the last expression is a match lowering (IIFE), wrap it in a return
			if callExpr, isCall := exprStmt.X.(*ast.CallExpr); isCall {
				if funcLit, isFuncLit := callExpr.Fun.(*ast.FuncLit); isFuncLit && len(funcLit.Body.List) > 0 {
					// Heuristic: check if the first statement is a var decl for __match_result
					if declStmt, isDecl := funcLit.Body.List[0].(*ast.DeclStmt); isDecl {
						if genDecl, isGen := declStmt.Decl.(*ast.GenDecl); isGen && len(genDecl.Specs) > 0 {
							if valSpec, isVal := genDecl.Specs[0].(*ast.ValueSpec); isVal && len(valSpec.Names) > 0 && valSpec.Names[0].Name == "__match_result" {
								// Looks like a match lowering, emit as return
								bodyAST.List[len(bodyAST.List)-1] = &ast.ReturnStmt{Results: []ast.Expr{exprStmt.X}}
							}
						}
					}
				}
			}
			// Otherwise, default: return last expr
			if _, alreadyReturn := bodyAST.List[len(bodyAST.List)-1].(*ast.ReturnStmt); !alreadyReturn {
				bodyAST.List[len(bodyAST.List)-1] = &ast.ReturnStmt{Results: []ast.Expr{exprStmt.X}}
			}
		}
	}

	if bodyAST == nil {
		bodyAST = &ast.BlockStmt{}
	}

	return &ast.FuncDecl{
		Name: ast.NewIdent(fnName),
		Type: &ast.FuncType{
			Params:  paramsAST,
			Results: resultsAST,
		},
		Body: bodyAST,
	}
}

// VisitParameters handles a list of function parameters.
// ctx is parser.IParametersContext
// This method is called by ProcessParameters. It should return []ParamDetail.
func (v *ManuscriptAstVisitor) VisitParameters(ctx *parser.ParametersContext) interface{} {
	if ctx == nil {
		return []ParamDetail{}
	}
	var details []ParamDetail
	for _, param := range ctx.AllParam() {
		if detail, ok := v.Visit(param).(ParamDetail); ok {
			details = append(details, detail)
		}
	}
	return details
}

func (v *ManuscriptAstVisitor) VisitParam(ctx *parser.ParamContext) interface{} {
	return v.VisitIParam(ctx)
}

// VisitParam handles a single function parameter.
// param: (label=ID)? name=namedID COLON type_=typeAnnotation (EQUALS defaultValue=expr)?;\n// ctx is parser.IParamContext
// This method is called by VisitParameters. It should return ParamDetail.
func (v *ManuscriptAstVisitor) VisitIParam(ctx parser.IParamContext) interface{} {
	var paramName *ast.Ident
	var paramNameToken antlr.Token

	if ctx.ID() != nil {
		paramNameToken = ctx.ID().GetSymbol()
		paramName = ast.NewIdent(paramNameToken.GetText())
	} else {
		v.addError("Parameter must have a name", ctx.GetStart())
		return nil
	}

	// Type Annotation
	var paramType ast.Expr
	if ctx.TypeAnnotation() != nil {
		if pt, ok := v.Visit(ctx.TypeAnnotation()).(ast.Expr); ok {
			paramType = pt
		} else {
			v.addError(fmt.Sprintf("Invalid type for parameter \"%s\".", paramName.Name), ctx.TypeAnnotation().GetStart())
			return nil
		}
	} else {
		v.addError(fmt.Sprintf("Missing type annotation for parameter \"%s\".", paramName.Name), paramNameToken)
		return nil
	}
	var defaultValueExpr ast.Expr
	if ctx.EQUALS() != nil && ctx.Expr() != nil {
		if dvExpr, ok := v.Visit(ctx.Expr()).(ast.Expr); ok {
			defaultValueExpr = dvExpr
		} else {
			v.addError(fmt.Sprintf("Default value for parameter \"%s\" is not a valid expression.", paramName.Name), ctx.Expr().GetStart())
		}
	} else if ctx.EQUALS() != nil && ctx.Expr() == nil {
		v.addError(fmt.Sprintf("Incomplete default value for parameter \"%s\".", paramName.Name), ctx.EQUALS().GetSymbol())
		return nil
	}
	return ParamDetail{
		Name:         paramName,
		NameToken:    paramNameToken,
		Type:         paramType,
		DefaultValue: defaultValueExpr,
	}
}

// ProcessReturnType processes return type for functions and methods.
// It returns an *ast.FieldList for the results.
func (v *ManuscriptAstVisitor) ProcessReturnType(typeAnnotationCtx parser.ITypeAnnotationContext, exclamationNode antlr.TerminalNode, funcName string) *ast.FieldList {
	var results *ast.FieldList

	if typeAnnotationCtx != nil {
		returnTypeInterface := typeAnnotationCtx.Accept(v)
		if returnTypeExpr, okRT := returnTypeInterface.(ast.Expr); okRT && returnTypeExpr != nil {
			field := &ast.Field{Type: returnTypeExpr}
			results = &ast.FieldList{List: []*ast.Field{field}}
		} else if returnTypeInterface == nil {
			// For void return type, we create an empty results list
			results = &ast.FieldList{List: []*ast.Field{}}
		} else {
			v.addError(fmt.Sprintf("Invalid return type for function/method \"%s\"", funcName), typeAnnotationCtx.GetStart())
		}
	}

	if exclamationNode != nil {
		errorType := ast.NewIdent("error")
		errorField := &ast.Field{Type: errorType}
		if results == nil {
			results = &ast.FieldList{List: []*ast.Field{errorField}}
		} else {
			// Check if error type is already there to prevent duplication if a function explicitly returns error AND uses '!'
			alreadyHasError := false
			for _, f := range results.List {
				if id, okId := f.Type.(*ast.Ident); okId && id.Name == "error" {
					alreadyHasError = true
					break
				}
			}
			if !alreadyHasError {
				results.List = append(results.List, errorField)
			}
		}
	}
	return results
}

// VisitFnExpr handles function expressions (anonymous functions).
// fnExpr: FN LPAREN Parameters? RPAREN (COLON TypeAnnotation)? CodeBlock;
// (ASYNC and EXCLAMATION are not directly on FnExprContext based on current findings)
func (v *ManuscriptAstVisitor) VisitFnExpr(ctx *parser.FnExprContext) interface{} {
	paramsCtx := ctx.Parameters()
	typeAnnotation := ctx.TypeAnnotation()

	var paramDetailsList []ParamDetail
	var paramsAST *ast.FieldList
	var defaultAssignments []ast.Stmt
	if paramsCtx != nil {
		if details, ok := v.VisitParameters(paramsCtx.(*parser.ParametersContext)).([]ParamDetail); ok {
			paramDetailsList = details
			paramsAST, defaultAssignments = v.buildParamsAST(paramDetailsList)
		}
	} else {
		paramsAST = &ast.FieldList{List: []*ast.Field{}}
	}

	if ctx.CodeBlock() == nil {
		v.addError("No code block found for anonymous function expression.", ctx.FN().GetSymbol())
		return nil
	}
	concreteCodeBlockCtx, ok := ctx.CodeBlock().(*parser.CodeBlockContext)
	if !ok {
		v.addError("Internal error: Unexpected context type for code block in anonymous function expression.", ctx.CodeBlock().GetStart())
		return nil
	}
	bodyInterface := v.Visit(concreteCodeBlockCtx)
	b, okBody := bodyInterface.(*ast.BlockStmt)
	if !okBody {
		v.addError("Anonymous function expression must have a valid code block body.", ctx.CodeBlock().GetStart())
		return nil
	}
	bodyAST := b
	if len(defaultAssignments) > 0 {
		newBodyList := append([]ast.Stmt{}, defaultAssignments...)
		newBodyList = append(newBodyList, bodyAST.List...)
		bodyAST.List = newBodyList
	}

	var resultsAST *ast.FieldList
	if typeAnnotation != nil {
		resultsAST = v.ProcessReturnType(typeAnnotation, nil, "anonymous function expression")
	}

	// Only convert last expression statement to return if function has a non-void return type
	if resultsAST != nil && len(resultsAST.List) > 0 && len(bodyAST.List) > 0 {
		if exprStmt, ok := bodyAST.List[len(bodyAST.List)-1].(*ast.ExprStmt); ok && exprStmt.X != nil {
			bodyAST.List[len(bodyAST.List)-1] = &ast.ReturnStmt{Return: exprStmt.X.Pos(), Results: []ast.Expr{exprStmt.X}}
		}
	}

	return &ast.FuncLit{
		Type: &ast.FuncType{
			Func:    v.pos(ctx.FN().GetSymbol()),
			Params:  paramsAST,
			Results: resultsAST,
		},
		Body: bodyAST,
	}
}
