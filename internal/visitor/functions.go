package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"

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

	var fnName string
	if fnSig.NamedID() != nil {
		fnName = fnSig.NamedID().GetText()
	} else {
		v.addError("Function signature is missing name.", fnSig.GetStart())
		return nil
	}

	// Parameters
	var paramsAST = &ast.FieldList{List: []*ast.Field{}}
	var defaultAssignments []ast.Stmt

	if fnSig.Parameters() != nil {
		// ProcessParameters now returns []ParamDetail as its third value
		var pdl []ParamDetail
		paramsAST, defaultAssignments, pdl = v.ProcessParameters(fnSig.Parameters())
		_ = pdl // Use pdl to satisfy the linter if no other logic uses it right now.
		// If pdl is meant to be used for other checks below, that logic should be implemented.

		// The paramsAST is already populated by ProcessParameters
	}

	// Return Type
	var results *ast.FieldList
	if fnSig.TypeAnnotation() != nil || fnSig.EXCLAMATION() != nil {
		results = v.ProcessReturnType(fnSig.TypeAnnotation(), fnSig.EXCLAMATION(), fnName)
	}

	// Function Body
	var body *ast.BlockStmt
	if ctx.CodeBlock() != nil {
		// v.VisitCodeBlock expects parser.ICodeBlockContext, which ctx.CodeBlock() returns.
		// The actual VisitCodeBlock method in the visitor might expect *parser.CodeBlockContext.
		bodyInterface := v.VisitCodeBlock(ctx.CodeBlock().(*parser.CodeBlockContext))
		if b, ok := bodyInterface.(*ast.BlockStmt); ok {
			body = b
			if len(defaultAssignments) > 0 {
				body.List = append(defaultAssignments, body.List...)
			}
		} else {
			v.addError(fmt.Sprintf("Function \"%s\" must have a valid code block body.", fnName), ctx.CodeBlock().GetStart())
			return nil
		}
	} else {
		v.addError(fmt.Sprintf("No code block found for function \"%s\".", fnName), fnSig.NamedID().GetStart()) // Use name from signature
		return nil
	}

	return &ast.FuncDecl{
		Name: ast.NewIdent(fnName),
		Type: &ast.FuncType{
			Params:  paramsAST,
			Results: results,
		},
		Body: body,
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
		log.Printf("VisitParam: Processing default value for '%s': %s", paramName.Name, ctx.Expr().GetText())
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
		for _, pd := range paramDetailsList {
			field := &ast.Field{
				Names: []*ast.Ident{pd.Name},
				Type:  pd.Type,
			}
			paramsAST.List = append(paramsAST.List, field)

			if pd.DefaultValue != nil {
				log.Printf("ProcessParameters: Generating default value assignment for %s.", pd.Name.Name)
				// Simplified zero value check, needs robust implementation based on type system
				var zeroValExpr ast.Expr = ast.NewIdent("nil") // Default to nil for non-basic types
				if ident, okType := pd.Type.(*ast.Ident); okType {
					switch ident.Name {
					case "int", "int32", "int64", "float32", "float64":
						zeroValExpr = &ast.BasicLit{Kind: token.INT, Value: "0"}
					case "string":
						zeroValExpr = &ast.BasicLit{Kind: token.STRING, Value: `""`}
					case "bool":
						zeroValExpr = ast.NewIdent("false")
					}
				} else if pd.Type != nil { // Only add error if type was present but not an ident we handle for zero val
					v.addError(fmt.Sprintf("Could not determine specific zero value for type of param %s for default value; using 'nil' check. Type: %T", pd.Name.Name, pd.Type), pd.NameToken)
				}

				ifStmt := &ast.IfStmt{
					Cond: &ast.BinaryExpr{X: pd.Name, Op: token.EQL, Y: zeroValExpr},
					Body: &ast.BlockStmt{List: []ast.Stmt{
						&ast.AssignStmt{Lhs: []ast.Expr{pd.Name}, Tok: token.ASSIGN, Rhs: []ast.Expr{pd.DefaultValue}},
					}},
				}
				defaultAssignments = append(defaultAssignments, ifStmt)
			}
		}
	} else if rawParamDetails != nil { // If it's not nil and not []ParamDetail, it's an error
		v.addError("Internal error: Parameter processing (v.VisitParameters) did not return expected []ParamDetail.", paramsCtx.GetStart())
	}

	return paramsAST, defaultAssignments, paramDetailsList
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
			} else if returnTypeExpr == nil && okRT {
				// Valid visit but no type (e.g. error in VisitTypeAnnotation)
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

	// Parameters & Default Value Assignments
	paramsAST, defaultAssignments, _ := v.ProcessParameters(ctx.Parameters()) // Using helper

	// Return Type
	var resultsAST *ast.FieldList
	if ctx.TypeAnnotation() != nil { // Check EXCLAMATION too for the helper
		resultsAST = v.ProcessReturnType(ctx.TypeAnnotation(), nil, "anonymous function expression") // Using helper, passed nil for EXCLAMATION
	}

	// Function Body
	bodyAST := &ast.BlockStmt{}
	if ctx.CodeBlock() != nil {
		// VisitCodeBlock expects *parser.CodeBlockContext.
		concreteCodeBlockCtx, ok := ctx.CodeBlock().(*parser.CodeBlockContext)
		if !ok {
			v.addError("Function expression body has unexpected context type.", ctx.CodeBlock().GetStart())
		} else {
			bodyInterface := v.VisitCodeBlock(concreteCodeBlockCtx)
			if b, okBody := bodyInterface.(*ast.BlockStmt); okBody {
				bodyAST = b
				if len(defaultAssignments) > 0 {
					bodyAST.List = append(defaultAssignments, bodyAST.List...)
				}
			} else {
				v.addError("Function expression body did not resolve to a valid block statement.", concreteCodeBlockCtx.GetStart())
			}
		}
	} else {
		v.addError("Function expression has no code block.", ctx.GetStart())
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
