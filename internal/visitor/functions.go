package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"

	"github.com/antlr4-go/antlr/v4"
)

// ParamDetail holds extracted information about a function parameter, including any default value.
type ParamDetail struct {
	Name         *ast.Ident
	NameToken    antlr.Token // Store the original token for error reporting
	Type         ast.Expr
	DefaultValue ast.Expr // nil if no default value
}

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

// inferTypeFromExpression attempts to infer a Go AST type from a given expression.
// It's a basic inference, primarily for literals and simple cases.
func (v *ManuscriptAstVisitor) inferTypeFromExpression(expr ast.Expr, funcParams *ast.FieldList) ast.Expr {
	if expr == nil {
		return nil
	}
	switch e := expr.(type) {
	case *ast.BasicLit:
		switch e.Kind {
		case token.INT:
			return ast.NewIdent("int64") // Manuscript 'int' typically maps to 'int64'
		case token.FLOAT:
			return ast.NewIdent("float64") // Manuscript 'float' typically maps to 'float64'
		case token.STRING:
			return ast.NewIdent("string")
		default:
			return nil
		}
	case *ast.Ident:
		// Check for boolean literals (if Manuscript parses them as Idents)
		// This needs to align with actual grammar for booleans.
		// if e.Name == "true" || e.Name == "false" { // Assuming "true"/"false" are idents for bools
		// 	return ast.NewIdent("bool")
		// }

		// Check if 'e' is a parameter name, and get its type from funcParams
		if funcParams != nil {
			for _, field := range funcParams.List {
				for _, name := range field.Names {
					if name.Name == e.Name {
						// The field.Type is already an ast.Expr representing the type.
						return field.Type
					}
				}
			}
		}
		return nil // Cannot infer from other idents without a symbol table/type system
	case *ast.BinaryExpr:
		// Very basic inference: if operands can be inferred to the same type, assume that type.
		// This doesn't handle type promotion (e.g., int + float = float) or complex cases.
		leftType := v.inferTypeFromExpression(e.X, funcParams)
		// rightType := v.inferTypeFromExpression(e.Y, funcParams) // Not used in simple model for now

		// If left operand's type can be inferred, assume binary op results in same type.
		// This is a major simplification, especially for ops like comparisons (-> bool)
		// or mixed-type arithmetic.
		// For `a + b + d`: if `a` is int64, this might infer `int64` if `a` is `e.X`.
		if leftType != nil {
			// Check if leftType is one of the numeric types we handle
			if lt, ok := leftType.(*ast.Ident); ok {
				if lt.Name == "int64" || lt.Name == "float64" { // Add other types if needed
					// This assumes the binary operation preserves the type of the left operand.
					// A more robust solution would check e.Op and types of both X and Y.
					return ast.NewIdent(lt.Name)
				}
				// Could add bool for comparison operators, e.g.
				// switch e.Op {
				// case token.EQL, token.LSS, token.GTR, token.NEQ, token.LEQ, token.GEQ:
				// return ast.NewIdent("bool")
				// }
			}
		}
		return nil
	case *ast.CompositeLit:
		// For composite literals like `[]int{1,2}` or `MyStruct{}{}`, e.Type is the AST node for the type.
		return e.Type
	case *ast.CallExpr:
		// If the function being called is an identifier that represents a type (e.g. type conversion)
		// like `string(x)`, `int(num)`, then e.Fun is that type.
		if typeIdent, ok := e.Fun.(*ast.Ident); ok {
			// Basic check: does it look like a built-in Go type?
			// A more robust way would be to have a list of known types or a symbol table.
			switch typeIdent.Name {
			case "string", "int", "int8", "int16", "int32", "int64",
				"uint", "uint8", "uint16", "uint32", "uint64", "uintptr",
				"float32", "float64", "complex64", "complex128",
				"bool", "byte", "rune", "error":
				return typeIdent // The function name itself is the type.
			}
			// If it's not a known built-in type, we can't infer without a symbol table.
			// For project-specific types or functions, this would need more info.
			// For now, let's assume if it's not a basic Go type, we can't infer the return from the call expr alone.
			// However, if the call is `MyType(arg)` and MyType is a defined type in Manuscript,
			// then e.Fun might be an *ast.Ident{Name: "MyType"}.
			// This requires knowing it's a type.
		}
		// If e.Fun is a more complex expression (e.g. a selector like `pkg.MyFunc()`),
		// or if it's an identifier for a function whose return type isn't known here,
		// we can't infer easily.
		// TODO: A more advanced system would look up the function signature in a symbol table.
		return nil
	default:
		return nil // Cannot infer by default
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

// buildParamsAST builds the Go AST parameter list and default assignments from ParamDetail list.
func (v *ManuscriptAstVisitor) buildParamsAST(paramDetailsList []ParamDetail) (*ast.FieldList, []ast.Stmt) {
	paramsAST := &ast.FieldList{List: []*ast.Field{}}
	var defaultAssignments []ast.Stmt
	hasDefaultArg := false
	firstDefaultArgIndex := -1
	for i, pd := range paramDetailsList {
		if pd.DefaultValue != nil {
			hasDefaultArg = true
			if firstDefaultArgIndex == -1 {
				firstDefaultArgIndex = i
			}
		} else if hasDefaultArg {
			v.addError(
				fmt.Sprintf("Non-default argument '%s' follows default argument. Manuscript requires default arguments to be at the end of the parameter list.", pd.Name.Name),
				pd.NameToken,
			)
		}
	}
	if hasDefaultArg {
		paramsAST.List = []*ast.Field{{Names: []*ast.Ident{ast.NewIdent("args")}, Type: &ast.Ellipsis{Elt: ast.NewIdent("interface{}")}}}
		for i, pd := range paramDetailsList {
			paramIdent := pd.Name
			if pd.DefaultValue != nil {
				declStmt := &ast.DeclStmt{
					Decl: &ast.GenDecl{
						Tok: token.VAR,
						Specs: []ast.Spec{
							&ast.ValueSpec{
								Names:  []*ast.Ident{paramIdent},
								Type:   pd.Type,
								Values: []ast.Expr{pd.DefaultValue},
							},
						},
					},
				}
				defaultAssignments = append(defaultAssignments, declStmt)
				ifStmt := &ast.IfStmt{
					Cond: &ast.BinaryExpr{
						X:  &ast.CallExpr{Fun: ast.NewIdent("len"), Args: []ast.Expr{ast.NewIdent("args")}},
						Op: token.GTR,
						Y:  &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(i)},
					},
					Body: &ast.BlockStmt{
						List: []ast.Stmt{
							&ast.AssignStmt{
								Lhs: []ast.Expr{paramIdent},
								Tok: token.ASSIGN,
								Rhs: []ast.Expr{
									&ast.TypeAssertExpr{
										X: &ast.IndexExpr{
											X:     ast.NewIdent("args"),
											Index: &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(i)},
										},
										Type: pd.Type,
									},
								},
							},
						},
					},
				}
				defaultAssignments = append(defaultAssignments, ifStmt)
			} else {
				assignStmt := &ast.AssignStmt{
					Lhs: []ast.Expr{paramIdent},
					Tok: token.DEFINE,
					Rhs: []ast.Expr{
						&ast.TypeAssertExpr{
							X: &ast.IndexExpr{
								X:     ast.NewIdent("args"),
								Index: &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(i)},
							},
							Type: pd.Type,
						},
					},
				}
				defaultAssignments = append(defaultAssignments, assignStmt)
			}
		}
	} else {
		for _, pd := range paramDetailsList {
			paramsAST.List = append(paramsAST.List, &ast.Field{Names: []*ast.Ident{pd.Name}, Type: pd.Type})
		}
	}
	return paramsAST, defaultAssignments
}
