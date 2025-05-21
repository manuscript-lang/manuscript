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
	paramsAST, bodyAST, resultsAST, err := v.buildFunctionAst(
		fnSig.Parameters(),
		fnSig.TypeAnnotation(),
		fnSig.EXCLAMATION(),
		ctx.CodeBlock(),
		fnName,
		fnNameToken,
	)
	if err != nil {
		return nil
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

// buildFunctionAst processes function/closure logic shared by VisitFnDecl and VisitFnExpr.
// It returns paramsAST, bodyAST, resultsAST, and any error encountered.
func (v *ManuscriptAstVisitor) buildFunctionAst(
	paramsCtx parser.IParametersContext,
	typeAnnotation parser.ITypeAnnotationContext,
	exclamation antlr.TerminalNode,
	codeBlockCtx antlr.ParserRuleContext,
	nameForError string,
	fnToken antlr.Token, // for error reporting
) (paramsAST *ast.FieldList, bodyAST *ast.BlockStmt, resultsAST *ast.FieldList, err error) {
	// --- Parameters and defaults ---
	var paramDetailsList []ParamDetail
	var defaultAssignments []ast.Stmt
	if paramsCtx != nil {
		if details, ok := v.VisitParameters(paramsCtx.(*parser.ParametersContext)).([]ParamDetail); ok {
			paramDetailsList = details
			paramsAST, defaultAssignments = v.buildParamsAST(paramDetailsList)
		}
	} else {
		paramsAST = &ast.FieldList{List: []*ast.Field{}}
	}

	// --- Code block ---
	if codeBlockCtx == nil {
		err = fmt.Errorf("no code block found for function '%s'", nameForError)
		v.addError(err.Error(), fnToken)
		return
	}
	concreteCodeBlockCtx, ok := codeBlockCtx.(*parser.CodeBlockContext)
	if !ok {
		err = fmt.Errorf("internal error: unexpected context type for code block in function '%s'", nameForError)
		v.addError(err.Error(), codeBlockCtx.GetStart())
		return
	}
	bodyInterface := v.Visit(concreteCodeBlockCtx)
	b, okBody := bodyInterface.(*ast.BlockStmt)
	if !okBody {
		err = fmt.Errorf("function must have a valid code block body. '%s'", nameForError)
		v.addError(err.Error(), codeBlockCtx.GetStart())
		return
	}
	bodyAST = b

	// --- Prepend default assignments ---
	if len(defaultAssignments) > 0 {
		newBodyList := append([]ast.Stmt{}, defaultAssignments...)
		newBodyList = append(newBodyList, bodyAST.List...)
		bodyAST.List = newBodyList
	}

	// --- Return type ---
	if typeAnnotation != nil || exclamation != nil {
		resultsAST = v.ProcessReturnType(typeAnnotation, exclamation, nameForError)
	}

	// --- Ensure last statement is a return if it's an expression ---
	v.ensureLastExprIsReturn(bodyAST)

	if bodyAST == nil {
		bodyAST = &ast.BlockStmt{}
	}
	return
}

// ensureLastExprIsReturn converts the last statement to a return if it's an expression statement.
func (v *ManuscriptAstVisitor) ensureLastExprIsReturn(bodyAST *ast.BlockStmt) {
	if bodyAST == nil || len(bodyAST.List) == 0 {
		return
	}

	// Only generate a multi-value return if the body is a single ExprStmt whose expression is an ExprList
	if len(bodyAST.List) == 1 {
		if exprStmt, ok := bodyAST.List[0].(*ast.ExprStmt); ok && exprStmt.X != nil {
			if exprListCtx, ok := exprStmt.X.(parser.IExprListContext); ok {
				var results []ast.Expr
				for _, exprNode := range exprListCtx.AllExpr() {
					visitedExpr := v.Visit(exprNode)
					if astExpr, ok := visitedExpr.(ast.Expr); ok {
						results = append(results, astExpr)
					} else {
						results = append(results, &ast.BadExpr{})
					}
				}
				bodyAST.List[0] = &ast.ReturnStmt{Results: results}
				return
			}
		}
	}

	lastIdx := len(bodyAST.List) - 1
	lastStmt := bodyAST.List[lastIdx]

	exprStmt, ok := lastStmt.(*ast.ExprStmt)
	if !ok || exprStmt.X == nil {
		return
	}

	// If the last expression is an ExprList, always return all values
	if exprListCtx, ok := exprStmt.X.(parser.IExprListContext); ok {
		var results []ast.Expr
		for _, exprNode := range exprListCtx.AllExpr() {
			visitedExpr := v.Visit(exprNode)
			if astExpr, ok := visitedExpr.(ast.Expr); ok {
				results = append(results, astExpr)
			} else {
				results = append(results, &ast.BadExpr{})
			}
		}
		bodyAST.List[lastIdx] = &ast.ReturnStmt{Results: results}
		return
	}

	// Special case: if the last expression is a match lowering (IIFE), wrap it in a return
	if callExpr, isCall := exprStmt.X.(*ast.CallExpr); isCall {
		if funcLit, isFuncLit := callExpr.Fun.(*ast.FuncLit); isFuncLit && len(funcLit.Body.List) > 0 {
			if declStmt, isDecl := funcLit.Body.List[0].(*ast.DeclStmt); isDecl {
				if genDecl, isGen := declStmt.Decl.(*ast.GenDecl); isGen && len(genDecl.Specs) > 0 {
					if valSpec, isVal := genDecl.Specs[0].(*ast.ValueSpec); isVal && len(valSpec.Names) > 0 && valSpec.Names[0].Name == "__match_result" {
						bodyAST.List[lastIdx] = &ast.ReturnStmt{Results: []ast.Expr{exprStmt.X}}
						return
					}
				}
			}
		}
	}

	// Otherwise, default: return last expr
	if _, alreadyReturn := bodyAST.List[lastIdx].(*ast.ReturnStmt); !alreadyReturn {
		bodyAST.List[lastIdx] = &ast.ReturnStmt{Results: []ast.Expr{exprStmt.X}}
	}
}

// VisitFnExpr handles function expressions (anonymous functions).
// fnExpr: FN LPAREN Parameters? RPAREN (COLON TypeAnnotation)? CodeBlock;
// (ASYNC and EXCLAMATION are not directly on FnExprContext based on current findings)
func (v *ManuscriptAstVisitor) VisitFnExpr(ctx *parser.FnExprContext) interface{} {
	paramsAST, bodyAST, resultsAST, err := v.buildFunctionAst(
		ctx.Parameters(),
		ctx.TypeAnnotation(),
		nil, // no exclamation for fnExpr
		ctx.CodeBlock(),
		"anonymous function expression",
		ctx.FN().GetSymbol(),
	)
	if err != nil {
		return nil
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
