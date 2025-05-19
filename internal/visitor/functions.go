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

// Helper structure for function construction
type functionConstructionParts struct {
	paramsAST          *ast.FieldList
	defaultAssignments []ast.Stmt // Kept for clarity, though bodyAST will have them prepended
	bodyAST            *ast.BlockStmt
	resultsAST         *ast.FieldList
}

// buildFunctionEssentials consolidates common logic for processing function parts.
// It handles parameters, body construction (with default assignments), return type determination (explicit/inferred),
// and conversion of the last expression to a return statement if applicable.
func (v *ManuscriptAstVisitor) buildFunctionEssentials(
	fnNameForError string, // For error messages
	overallFnToken antlr.Token, // For error reporting when specific part tokens are unavailable
	paramsCtx parser.IParametersContext,
	typeAnnotationCtx parser.ITypeAnnotationContext,
	exclamationNode antlr.TerminalNode,
	codeBlockCtx parser.ICodeBlockContext,
	allowReturnTypeInference bool,
) (*functionConstructionParts, bool) { // returns parts and success status

	parts := &functionConstructionParts{}
	var paramDetailsList []ParamDetail

	// 1. Process Parameters
	if paramsCtx != nil {
		// ProcessParameters expects IParametersContext, which paramsCtx is.
		// Internally, ProcessParameters might cast to *parser.ParametersContext if needed.
		parts.paramsAST, parts.defaultAssignments, paramDetailsList = v.ProcessParameters(paramsCtx)
		_ = paramDetailsList // Currently unused by the direct callers of buildFunctionEssentials
	} else {
		parts.paramsAST = &ast.FieldList{List: []*ast.Field{}}
		parts.defaultAssignments = []ast.Stmt{}
	}

	// 2. Process Body and identify potential last expression for return
	var potentialLastExprForReturn ast.Expr
	if codeBlockCtx == nil {
		v.addError(fmt.Sprintf("No code block found for function '%s'.", fnNameForError), overallFnToken)
		return nil, false
	}

	concreteCodeBlockCtx, ok := codeBlockCtx.(*parser.CodeBlockContext)
	if !ok {
		v.addError(fmt.Sprintf("Internal error: Unexpected context type for code block in function '%s'.", fnNameForError), codeBlockCtx.GetStart())
		return nil, false
	}
	bodyInterface := v.VisitCodeBlock(concreteCodeBlockCtx)

	if b, okBody := bodyInterface.(*ast.BlockStmt); okBody {
		parts.bodyAST = b
		// Prepend default value assignments to the beginning of the actual body statements
		if len(parts.defaultAssignments) > 0 {
			// Ensure a new slice is created to avoid modifying underlying array of defaultAssignments if it's reused.
			currentBodyList := parts.bodyAST.List
			newBodyList := make([]ast.Stmt, 0, len(parts.defaultAssignments)+len(currentBodyList))
			newBodyList = append(newBodyList, parts.defaultAssignments...)
			newBodyList = append(newBodyList, currentBodyList...)
			parts.bodyAST.List = newBodyList
		}

		// Identify potential last expression from the (now fully assembled) body
		if len(parts.bodyAST.List) > 0 {
			lastIdx := len(parts.bodyAST.List) - 1
			finalStmtInBody := parts.bodyAST.List[lastIdx]
			if exprStmt, isExpr := finalStmtInBody.(*ast.ExprStmt); isExpr {
				potentialLastExprForReturn = exprStmt.X
			} else if retStmt, isRet := finalStmtInBody.(*ast.ReturnStmt); isRet {
				// If it's already a return statement, its expression can be used for type inference if needed.
				if len(retStmt.Results) > 0 {
					potentialLastExprForReturn = retStmt.Results[0]
				}
			}
		}
	} else {
		v.addError(fmt.Sprintf("Function '%s' must have a valid code block body.", fnNameForError), codeBlockCtx.GetStart())
		return nil, false
	}

	// 3. Determine Go Function Return Type ('resultsAST')
	goFuncWillHaveReturn := false
	if typeAnnotationCtx != nil || exclamationNode != nil { // Explicit MS return type
		parts.resultsAST = v.ProcessReturnType(typeAnnotationCtx, exclamationNode, fnNameForError)
		if parts.resultsAST != nil && len(parts.resultsAST.List) > 0 {
			goFuncWillHaveReturn = true
		}
	} else if allowReturnTypeInference && potentialLastExprForReturn != nil { // No explicit MS return, try to infer
		inferredTypeExpr := v.inferTypeFromExpression(potentialLastExprForReturn, parts.paramsAST)
		if inferredTypeExpr != nil {
			parts.resultsAST = &ast.FieldList{List: []*ast.Field{{Type: inferredTypeExpr}}}
			goFuncWillHaveReturn = true
		}
	}

	// 4. Convert last expression to ReturnStmt if a Go return type is expected
	// and the last statement in the body is an expression that matches our potential candidate.
	if goFuncWillHaveReturn && parts.bodyAST != nil && len(parts.bodyAST.List) > 0 {
		lastIdx := len(parts.bodyAST.List) - 1
		if exprStmt, isExpr := parts.bodyAST.List[lastIdx].(*ast.ExprStmt); isExpr {
			// Ensure this expression statement is the one we identified as 'potentialLastExprForReturn'.
			// This avoids converting if 'potentialLastExprForReturn' came from an already existing ReturnStmt.
			if exprStmt.X == potentialLastExprForReturn {
				retStmt := &ast.ReturnStmt{Return: exprStmt.X.Pos(), Results: []ast.Expr{exprStmt.X}}
				parts.bodyAST.List[lastIdx] = retStmt
			}
		}
	}

	// Ensure bodyAST is not nil, even if it was originally empty (it might contain default assignments).
	if parts.bodyAST == nil {
		parts.bodyAST = &ast.BlockStmt{}
	}

	return parts, true
}

// VisitFnDecl handles function declarations.
// fn foo(a: TypeA, b: TypeB = defaultVal): ReturnType! { body }
func (v *ManuscriptAstVisitor) VisitFnDecl(ctx *parser.FnDeclContext) interface{} {
	fnSig := ctx.FnSignature()
	if fnSig == nil {
		v.addError("Function declaration is missing signature.", ctx.GetStart())
		return nil
	}

	var fnName string
	var fnNameToken antlr.Token
	if fnSig.NamedID() != nil && fnSig.NamedID().ID() != nil { // Ensure ID is present
		fnName = fnSig.NamedID().GetText()
		fnNameToken = fnSig.NamedID().ID().GetSymbol()
	} else {
		v.addError("Function signature is missing name.", fnSig.GetStart())
		return nil
	}

	var paramsCtx parser.IParametersContext
	if fnSig.Parameters() != nil {
		paramsCtx = fnSig.Parameters()
	}

	var typeAnnotation parser.ITypeAnnotationContext
	if fnSig.TypeAnnotation() != nil {
		typeAnnotation = fnSig.TypeAnnotation()
	}

	parts, success := v.buildFunctionEssentials(
		fnName,
		fnNameToken, // Token for the function name, for error reporting context
		paramsCtx,
		typeAnnotation,
		fnSig.EXCLAMATION(),
		ctx.CodeBlock(),
		true, // Allow return type inference for function declarations
	)

	if !success {
		return nil // Error already added by helper
	}

	return &ast.FuncDecl{
		Name: ast.NewIdent(fnName),
		Type: &ast.FuncType{
			Params:  parts.paramsAST,
			Results: parts.resultsAST,
		},
		Body: parts.bodyAST,
	}
}

// VisitParameters handles a list of function parameters.
// ctx is parser.IParametersContext
// This method is called by ProcessParameters. It should return []ParamDetail.
func (v *ManuscriptAstVisitor) VisitParameters(ctx *parser.ParametersContext) interface{} {
	details := []ParamDetail{}
	if ctx == nil { // Guard against nil parameters context
		return details
	}
	for _, paramInterface := range ctx.AllParam() { // paramInterface is IParamContext
		// v.VisitParam expects parser.IParamContext
		visitedParam := v.VisitIParam(paramInterface)
		if detail, ok := visitedParam.(ParamDetail); ok {
			details = append(details, detail)
		} else if visitedParam == nil {
			// Error already added by VisitParam
		} else {
			v.addError("Internal error: Unexpected type returned from parameter processing for: "+paramInterface.GetText(), paramInterface.GetStart())
		}
	}
	return details
}

func (v *ManuscriptAstVisitor) VisitParam(ctx *parser.ParamContext) interface{} {
	// Delegate to VisitIParam which handles the full ParamDetail logic including default values.
	// *parser.ParamContext implements parser.IParamContext.
	return v.VisitIParam(ctx)
}

// VisitParam handles a single function parameter.
// param: (label=ID)? name=namedID COLON type_=typeAnnotation (EQUALS defaultValue=expr)?;\n// ctx is parser.IParamContext
// This method is called by VisitParameters. It should return ParamDetail.
func (v *ManuscriptAstVisitor) VisitIParam(ctx parser.IParamContext) interface{} {
	var paramName *ast.Ident
	var paramNameToken antlr.Token

	if ctx.NamedID() != nil && ctx.NamedID().ID() != nil {
		paramNameToken = ctx.NamedID().ID().GetSymbol()
		paramName = ast.NewIdent(paramNameToken.GetText())
	} else {
		v.addError("Parameter name is missing.", ctx.GetStart())
		return nil
	}

	// Optional Label
	// labelToken := ctx.GetLabel() // Available if needed: labelToken.GetText()

	// Type Annotation
	var paramType ast.Expr
	if ctx.TypeAnnotation() != nil {
		// v.VisitTypeAnnotation expects parser.ITypeAnnotationContext
		// The actual VisitTypeAnnotation method in the visitor might expect *parser.TypeAnnotationContext.
		typeInterface := v.VisitTypeAnnotation(ctx.TypeAnnotation().(*parser.TypeAnnotationContext))
		if pt, ok := typeInterface.(ast.Expr); ok {
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
	if ctx.EQUALS() != nil && ctx.Expr() != nil { // Check for EQUALS token before processing expression

		// v.Visit expects antlr.ParseTree, ctx.Expr() returns IExprContext which is a ParseTree
		defaultValInterface := v.Visit(ctx.Expr())
		if dvExpr, ok := defaultValInterface.(ast.Expr); ok {
			defaultValueExpr = dvExpr
		} else {
			v.addError(fmt.Sprintf("Default value for parameter \"%s\" is not a valid expression.", paramName.Name), ctx.Expr().GetStart())
			defaultValueExpr = nil // Proceed without default value on error
		}
	} else if ctx.EQUALS() != nil && ctx.Expr() == nil {
		// This case (e.g. "param: Type =") should ideally be a parser error.
		v.addError(fmt.Sprintf("Incomplete default value for parameter \"%s\".", paramName.Name), ctx.EQUALS().GetSymbol())
		return nil // Error: incomplete default value
	}

	return ParamDetail{
		Name:         paramName,
		NameToken:    paramNameToken,
		Type:         paramType,
		DefaultValue: defaultValueExpr,
	}
}

// ProcessParameters processes parameters for functions and methods.
// It returns the AST FieldList for parameters, a slice of default assignment statements,
// and a slice of ParamDetail for further use (e.g. by interface method checks).
func (v *ManuscriptAstVisitor) ProcessParameters(paramsCtx parser.IParametersContext) (*ast.FieldList, []ast.Stmt, []ParamDetail) {
	paramsAST := &ast.FieldList{List: []*ast.Field{}}
	var defaultAssignments []ast.Stmt
	var paramDetailsList []ParamDetail

	if paramsCtx == nil {
		return paramsAST, defaultAssignments, paramDetailsList
	}

	rawParamDetails := v.VisitParameters(paramsCtx.(*parser.ParametersContext)) // This should return []ParamDetail
	if pdl, ok := rawParamDetails.([]ParamDetail); ok {
		paramDetailsList = pdl
		hasDefaultArg := false
		firstDefaultArgIndex := -1 // To track the first parameter with a default value.

		// First pass: check for default arguments and validate their order.
		for i, pd := range paramDetailsList {
			if pd.DefaultValue != nil {
				hasDefaultArg = true
				if firstDefaultArgIndex == -1 {
					firstDefaultArgIndex = i
				}
			} else if hasDefaultArg { // A non-default argument after a default argument is an error.
				v.addError(
					fmt.Sprintf("Non-default argument '%s' follows default argument. Manuscript requires default arguments to be at the end of the parameter list.", pd.Name.Name),
					pd.NameToken,
				)
				// Consider returning an error or marking the function as invalid.
				// For now, the error is added, and processing continues, which might lead to malformed Go.
			}
		}

		if hasDefaultArg {
			// If there are default arguments, change the Go function signature to use variadic interfaces:
			// func foo(args ...interface{})
			paramsAST.List = []*ast.Field{
				{
					// No explicit name for `...interface{}` in Go's AST representation of parameters sometimes,
					// but `args` is typical for the variable used to access them in the body.
					// The important part is the Ellipsis Type.
					Names: []*ast.Ident{ast.NewIdent("args")}, // Name used to access in the generated body
					Type: &ast.Ellipsis{
						Elt: ast.NewIdent("interface{}"),
					},
				},
			}

			// Generate statements for argument handling within the function body.
			for i, pd := range paramDetailsList {
				paramIdent := pd.Name // This is already *ast.Ident

				if pd.DefaultValue != nil {
					// Parameter has a default value.
					// 1. Declare the variable with its type and default value:
					//    var paramName type = defaultValue
					declStmt := &ast.DeclStmt{
						Decl: &ast.GenDecl{
							Tok: token.VAR,
							Specs: []ast.Spec{
								&ast.ValueSpec{
									Names:  []*ast.Ident{paramIdent},
									Type:   pd.Type, // Original Manuscript type, translated to Go AST type
									Values: []ast.Expr{pd.DefaultValue},
								},
							},
						},
					}
					defaultAssignments = append(defaultAssignments, declStmt)

					// 2. If the argument was provided, override the default:
					//    if len(args) > i {
					//        paramName = args[i].(type)
					//    }
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
											Type: pd.Type, // Type for assertion
										},
									},
								},
							},
						},
					}
					defaultAssignments = append(defaultAssignments, ifStmt)

				} else {
					// Mandatory parameter (no default value).
					// Must be provided if function uses ...interface{} args.
					// paramName := args[i].(type)
					assignStmt := &ast.AssignStmt{
						Lhs: []ast.Expr{paramIdent},
						Tok: token.DEFINE, // := for first assignment
						Rhs: []ast.Expr{
							&ast.TypeAssertExpr{
								X: &ast.IndexExpr{
									X:     ast.NewIdent("args"),
									Index: &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(i)},
								},
								Type: pd.Type, // Type for assertion
							},
						},
					}
					defaultAssignments = append(defaultAssignments, assignStmt)
				}
			}
		} else {
			// No default arguments, construct parameter list as before.
			for _, pd := range paramDetailsList {
				field := &ast.Field{
					Names: []*ast.Ident{pd.Name},
					Type:  pd.Type,
				}
				paramsAST.List = append(paramsAST.List, field)
			}
			// The old logic for `if param == zero_value { param = default_value }`
			// is removed as it's incompatible with the variadic interface approach for default args.
		}
	} else if rawParamDetails != nil {
		v.addError("Internal error: Parameter processing (v.VisitParameters) did not return expected []ParamDetail.", paramsCtx.GetStart())
	}

	return paramsAST, defaultAssignments, paramDetailsList
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
func (v *ManuscriptAstVisitor) ProcessReturnType(typeAnnotationCtx parser.ITypeAnnotationContext, exclamationNode antlr.TerminalNode, funcNameForError string) *ast.FieldList {
	var results *ast.FieldList

	if typeAnnotationCtx != nil {
		// Ensure it's the concrete type *parser.TypeAnnotationContext if VisitTypeAnnotation expects it.
		concreteTypeAnnotationCtx, ok := typeAnnotationCtx.(*parser.TypeAnnotationContext)
		if !ok {
			v.addError(fmt.Sprintf("Return type for function/method \"%s\" has unexpected context type.", funcNameForError), typeAnnotationCtx.GetStart())
		} else {
			returnTypeInterface := v.VisitTypeAnnotation(concreteTypeAnnotationCtx)
			if returnTypeExpr, okRT := returnTypeInterface.(ast.Expr); okRT && returnTypeExpr != nil {
				field := &ast.Field{Type: returnTypeExpr}
				results = &ast.FieldList{List: []*ast.Field{field}}
			} else if returnTypeInterface == nil {
				// For void return type, we create an empty results list
				results = &ast.FieldList{List: []*ast.Field{}}
			} else {
				v.addError(fmt.Sprintf("Invalid return type for function/method \"%s\"", funcNameForError), concreteTypeAnnotationCtx.GetStart())
			}
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
	var paramsCtx parser.IParametersContext
	if ctx.Parameters() != nil {
		paramsCtx = ctx.Parameters()
	}

	var typeAnnotation parser.ITypeAnnotationContext
	if ctx.TypeAnnotation() != nil {
		typeAnnotation = ctx.TypeAnnotation()
	}

	// Anonymous functions in Manuscript (fn() { ... } or fn(): Type { ... })
	// do not use '!' for error returns and typically don't infer complex return types
	// beyond what's explicitly annotated or a simple last expression if that feature were fully enabled for them.
	// Current FnExpr visitor logic does not implement return type inference.
	parts, success := v.buildFunctionEssentials(
		"anonymous function expression",
		ctx.FN().GetSymbol(), // Token for "fn" keyword
		paramsCtx,
		typeAnnotation, // Pass explicit type annotation
		nil,            // No EXCLAMATION() in FnExpr syntax
		ctx.CodeBlock(),
		false, // Return type inference is typically not done for FnExpr in the same way as FnDecl
	)

	if !success {
		return nil // Error already added by helper
	}

	return &ast.FuncLit{
		Type: &ast.FuncType{
			Func:    v.pos(ctx.FN().GetSymbol()),
			Params:  parts.paramsAST,
			Results: parts.resultsAST,
		},
		Body: parts.bodyAST,
	}
}

// VisitLambdaExpr handles lambda expressions of the form: fn(p1, p2) = expr
// It translates them to Go's anonymous functions: func(p1, p2) <return_type_inferred_or_any> { return expr }
// Note: parser.LambdaExprContext is not defined by the current Manuscript.g4 grammar.
// This function is commented out to resolve compilation errors.
// If this lambda syntax (e.g., fn() = expr) is intended, the grammar needs to be updated,
// and this visitor method implemented accordingly.
/*
func (v *ManuscriptAstVisitor) VisitLambdaExpr(ctx *parser.LambdaExprContext) interface{} {
	// Parameters
	// Use ProcessParameters, but lambdas in this form likely don't support defaults or full type annotations in Manuscript.
	// The `ParamDetail` from `ProcessParameters` would be important to check for default values.
	paramsAST, _, paramDetailsList := v.ProcessParameters(ctx.Parameters()) // Using helper

	for _, detail := range paramDetailsList {
		if detail.DefaultValue != nil {
			v.addError(fmt.Sprintf("Default value for parameter '%s' not allowed in this lambda syntax.", detail.Name.Name), detail.NameToken)
		}
	}
	// Note: The Manuscript lambda syntax fn() = expr does not have return type annotation or '!'
	// So ProcessReturnType is not directly used here unless the interpretation changes.
	// The Go AST FuncLit.Type.Results will be nil.

	// Body Expression
	bodyExprVisited := v.Visit(ctx.Expr()) // ctx.Expr() is IExprContext
	bodyGoExpr, ok := bodyExprVisited.(ast.Expr)
	if !ok {
		v.addError("Lambda body did not resolve to a valid expression: "+ctx.Expr().GetText(), ctx.Expr().GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	// Lambda body is a single expression, so we create a block statement with a return statement.
	lambdaBodyStmts := []ast.Stmt{
		&ast.ReturnStmt{Results: []ast.Expr{bodyGoExpr}},
	}
	bodyAST := &ast.BlockStmt{
		Lbrace: v.pos(ctx.EQUALS().GetSymbol()), // Position of '=', acts as start of body block conceptually
		List:   lambdaBodyStmts,
		Rbrace: v.pos(ctx.Expr().GetStop()), // Position of end of body expression
	}

	// Lambda return type is typically inferred or `interface{}`. Manuscript lambda syntax here doesn't specify it.
	// We'll leave Results as nil for the FuncType, which Go often interprets as no return or allows inference where possible.
	// For a more robust translation, one might try to infer the type of bodyGoExpr if needed.
	return &ast.FuncLit{
		Type: &ast.FuncType{
			Func:    v.pos(ctx.FN().GetSymbol()),
			Params:  paramsAST,
			Results: nil, // No explicit return type in this lambda syntax
		},
		Body: bodyAST,
	}
}
*/
