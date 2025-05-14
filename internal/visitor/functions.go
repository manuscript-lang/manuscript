package visitor

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// paramDetail holds extracted information about a function parameter, including any default value.
type paramDetail struct {
	Name         *ast.Ident
	NameToken    antlr.Token // Store the original token for error reporting
	Type         ast.Expr
	DefaultValue ast.Expr // nil if no default value
}

// VisitFnDecl handles function declarations.
// fn foo(a: TypeA, b: TypeB = defaultVal): ReturnType! { body }
func (v *ManuscriptAstVisitor) VisitFnDecl(ctx *parser.FnDeclContext) interface{} {
	log.Printf("VisitFnDecl: Called for '%s'", ctx.GetText())

	fnName := ctx.ID().GetText()

	// Parameters
	var paramsAST = &ast.FieldList{List: []*ast.Field{}}
	var defaultAssignments []ast.Stmt
	var paramDetailsList []paramDetail

	if ctx.Parameters() != nil {
		paramsInterface := v.VisitParameters(ctx.Parameters().(*parser.ParametersContext))
		if pdl, ok := paramsInterface.([]paramDetail); ok {
			paramDetailsList = pdl
			for _, pd := range paramDetailsList {
				field := &ast.Field{
					Names: []*ast.Ident{pd.Name},
					Type:  pd.Type,
				}
				paramsAST.List = append(paramsAST.List, field)

				if pd.DefaultValue != nil {
					// Create the condition: if param == <zero_value_for_type>
					// This is a simplified check. A robust check for "zero value" is complex.
					// For common types, we might check against 0, "", false, nil.
					// This example assumes the zero value check might be against 'nil' if the type allows it,
					// or requires more sophisticated type-specific zero value generation.
					// For now, we'll create a placeholder or a very simple check.
					// A more robust solution would be needed for production.

					// Placeholder for zero value expression - this needs to be type-aware
					// For example, for an 'int' type, it would be ast.NewIdent("0")
					// For a 'string' type, it would be &ast.BasicLit{Kind: token.STRING, Value: "\"\""}
					// This part is complex and depends on how types are represented and resolved.
					// Let's assume for now we are checking if the parameter is its Go zero value.
					// This is a conceptual placeholder for how one might check.
					// A simple `if param == defaultValue` is not right.
					// It should be `if param == <zero value for param's type> { param = defaultValue }`

					// Example: if param is an int, check `param == 0`
					// Example: if param is a string, check `param == ""`
					// This part is highly dependent on the actual Go type being generated for pd.Type
					// For this pass, I will generate a simple assignment statement and log the need for a proper zero-value check.
					log.Printf("VisitFnDecl: Generating default value assignment for %s. Zero-value check needs to be implemented robustly based on type.", pd.Name.Name)

					// The following ifStmt structure an assignment `param = defaultValue`
					// if `param == <zero_value_for_type>`.
					// The determination of `zeroValExpr` is crucial and currently simplified.

					var zeroValExpr ast.Expr
					// This switch is illustrative and not exhaustive or fully correct for all types
					if ident, okType := pd.Type.(*ast.Ident); okType {
						switch ident.Name {
						case "int", "int32", "int64", "float32", "float64": // Add other numeric types
							zeroValExpr = &ast.BasicLit{Kind: token.INT, Value: "0"}
						case "string":
							zeroValExpr = &ast.BasicLit{Kind: token.STRING, Value: `""`}
						case "bool":
							zeroValExpr = ast.NewIdent("false")
						default:
							// For other types (structs, interfaces, pointers), 'nil' is often the zero value.
							// This is a simplification.
							zeroValExpr = ast.NewIdent("nil")
						}
					} else {
						// Default to nil for complex types or if type determination fails here
						zeroValExpr = ast.NewIdent("nil")
						v.addError("Could not determine specific zero value for type of param "+pd.Name.Name+"; defaulting to 'nil' check for default value assignment.", pd.NameToken)
					}

					ifStmt := &ast.IfStmt{
						Cond: &ast.BinaryExpr{
							X:  pd.Name,     // The parameter identifier
							Op: token.EQL,   // ==
							Y:  zeroValExpr, // The zero value for the parameter's type
						},
						Body: &ast.BlockStmt{
							List: []ast.Stmt{
								&ast.AssignStmt{
									Lhs: []ast.Expr{pd.Name}, // Assign to the parameter
									Tok: token.ASSIGN,
									Rhs: []ast.Expr{pd.DefaultValue}, // Assign the default value
								},
							},
						},
					}
					defaultAssignments = append(defaultAssignments, ifStmt)
				}
			}
		} else {
			v.addError("Internal error: Expected parameter details from parameter processing.", ctx.Parameters().GetStart())
			return nil
		}
	}

	// Return Type
	var results *ast.FieldList
	if ctx.TypeAnnotation() != nil {
		returnTypeInterface := v.VisitTypeAnnotation(ctx.TypeAnnotation().(*parser.TypeAnnotationContext))
		if returnTypeExpr, ok := returnTypeInterface.(ast.Expr); ok {
			field := &ast.Field{Type: returnTypeExpr}
			results = &ast.FieldList{List: []*ast.Field{field}}
		} else {
			v.addError("Invalid return type for function \""+fnName+"\"", ctx.TypeAnnotation().GetStart())
			// Allow functions with no explicit return type (void)
			results = nil
		}
	}

	// Handle error indicator '!'
	if ctx.EXCLAMATION() != nil {
		// Add error type to results
		errorType := ast.NewIdent("error") // Standard Go error type
		errorField := &ast.Field{Type: errorType}
		if results == nil {
			results = &ast.FieldList{List: []*ast.Field{errorField}}
		} else {
			results.List = append(results.List, errorField)
		}
	}

	// Function Body
	var body *ast.BlockStmt
	if ctx.CodeBlock() != nil {
		bodyInterface := v.VisitCodeBlock(ctx.CodeBlock().(*parser.CodeBlockContext))
		if b, ok := bodyInterface.(*ast.BlockStmt); ok {
			body = b
			// Prepend default value assignment statements to the function body
			if len(defaultAssignments) > 0 {
				body.List = append(defaultAssignments, body.List...)
			}
		} else {
			v.addError("Function \""+fnName+"\" must have a valid code block body.", ctx.CodeBlock().GetStart())
			return nil // Function must have a body
		}
	} else {
		v.addError("No code block found for function \""+fnName+"\".", ctx.ID().GetSymbol())
		return nil // Function must have a body
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
func (v *ManuscriptAstVisitor) VisitParameters(ctx *parser.ParametersContext) interface{} {
	log.Printf("VisitParameters: Called for '%s'", ctx.GetText())
	details := []paramDetail{}
	for _, paramCtx := range ctx.AllParam() {
		paramInterface := v.VisitParam(paramCtx.(*parser.ParamContext))
		if detail, ok := paramInterface.(paramDetail); ok { // Expect paramDetail
			details = append(details, detail)
		} else if field, okField := paramInterface.(*ast.Field); okField && field == nil {
			// This case can happen if VisitParam returns nil (e.g. error)
			// An error would have already been added by VisitParam, so just skip here.
		} else {
			v.addError("Internal error: Unexpected type returned from parameter processing for: "+paramCtx.GetText(), paramCtx.GetStart())
			// Optionally skip problematic param or return error
		}
	}
	return details // Return slice of paramDetail
}

// VisitParam handles a single function parameter.
// param: (label=ID)? name=ID COLON type_=typeAnnotation (EQUALS defaultValue=expr)?;
func (v *ManuscriptAstVisitor) VisitParam(ctx *parser.ParamContext) interface{} {
	log.Printf("VisitParam: Called for '%s'", ctx.GetText())

	var paramName *ast.Ident
	var paramNameToken antlr.Token
	ids := ctx.AllID()
	if len(ids) > 0 {
		paramNameToken = ids[len(ids)-1].GetSymbol()
		paramName = ast.NewIdent(paramNameToken.GetText())
	} else {
		v.addError("Parameter name is missing.", ctx.GetStart())
		return nil // Return nil to indicate an error
	}

	// Type Annotation
	var paramType ast.Expr
	if ctx.TypeAnnotation() != nil {
		typeInterface := v.VisitTypeAnnotation(ctx.TypeAnnotation().(*parser.TypeAnnotationContext))
		if pt, ok := typeInterface.(ast.Expr); ok {
			paramType = pt
		} else {
			v.addError("Invalid type for parameter \""+paramName.Name+"\".", ctx.TypeAnnotation().GetStart())
			return nil // Type annotation is mandatory
		}
	} else {
		// log.Printf("VisitParam: No type annotation for parameter '%s'", paramName.Name)
		v.addError("Missing type annotation for parameter \""+paramName.Name+"\".", paramNameToken)
		return nil // Type annotation is mandatory
	}

	// Handle default value (ctx.Expr()).
	var defaultValueExpr ast.Expr
	if ctx.Expr() != nil {
		log.Printf("VisitParam: Processing default value for '%s': %s", paramName.Name, ctx.Expr().GetText())
		// Assuming v.Visit(ctx.Expr()) will correctly visit the expression node
		// and return an ast.Expr. If ctx.Expr() is a specific type from parser,
		// a more direct Visit<SpecificExprType> might be called, or a general Visit.
		defaultValInterface := v.Visit(ctx.Expr()) // Generic visit for the expression
		if dvExpr, ok := defaultValInterface.(ast.Expr); ok {
			defaultValueExpr = dvExpr
		} else {
			// log.Printf("VisitParam: Could not convert default value expression to ast.Expr for param '%s'. Got %T", paramName.Name, defaultValInterface)
			v.addError("Default value for parameter \""+paramName.Name+"\" is not a valid expression.", ctx.Expr().GetStart())
			// Decide: return error, or proceed without default value? For now, proceed without.
			defaultValueExpr = nil
		}
	}

	return paramDetail{ // Return paramDetail struct
		Name:         paramName,
		NameToken:    paramNameToken,
		Type:         paramType,
		DefaultValue: defaultValueExpr,
	}
}
