package visitor

import (
	"fmt"
	"go/ast"
	"manuscript-co/manuscript/internal/parser"

	gotoken "go/token"

	"github.com/antlr4-go/antlr/v4"
)

// VisitTypeAnnotation handles type annotations based on the grammar:
// typeAnnotation: ID | arrayType | tupleType | fnType | VOID;
func (v *ManuscriptAstVisitor) VisitTypeAnnotation(ctx *parser.TypeAnnotationContext) interface{} {
	var baseExpr ast.Expr

	if ctx.VOID() != nil {
		// Void type is represented as nil ast.Expr
		baseExpr = v.handleVoidType()
	} else if ctx.ID() != nil {
		typeName := ctx.ID().GetText()
		switch typeName {
		case "string":
			baseExpr = ast.NewIdent("string")
		case "int":
			baseExpr = ast.NewIdent("int64")
		case "float":
			baseExpr = ast.NewIdent("float64")
		case "bool":
			baseExpr = ast.NewIdent("bool")
		default:
			baseExpr = ast.NewIdent(typeName) // User-defined types
		}
	} else if ctx.TupleType() != nil {
		tupleTypeCtx := ctx.TupleType().(*parser.TupleTypeContext)
		visitedTuple := v.VisitTupleType(tupleTypeCtx)
		if vt, ok := visitedTuple.(ast.Expr); ok {
			baseExpr = vt
		} else {
			v.addError("Tuple type annotation did not resolve to an expression: "+tupleTypeCtx.GetText(), tupleTypeCtx.GetStart())
			return &ast.BadExpr{}
		}
	} else if ctx.ArrayType() != nil {
		arrayTypeCtx := ctx.ArrayType().(*parser.ArrayTypeContext)
		visitedArray := v.VisitArrayType(arrayTypeCtx)
		if at, ok := visitedArray.(ast.Expr); ok {
			baseExpr = at
		} else {
			v.addError("Array type annotation did not resolve to an expression: "+arrayTypeCtx.GetText(), arrayTypeCtx.GetStart())
			return &ast.BadExpr{}
		}
	} else if ctx.FnType() != nil {
		fnTypeCtx := ctx.FnType().(*parser.FnTypeContext)
		visitedFn := v.VisitFnType(fnTypeCtx)
		if ft, ok := visitedFn.(ast.Expr); ok {
			baseExpr = ft
		} else {
			v.addError("Function type annotation did not resolve to an expression: "+fnTypeCtx.GetText(), fnTypeCtx.GetStart())
			return &ast.BadExpr{}
		}
	} else {
		v.addError("Invalid type annotation structure: "+ctx.GetText(), ctx.GetStart())
		return &ast.BadExpr{}
	}

	return baseExpr // Return nil for void, or the ast.Expr
}

// VisitArrayType handles array type signatures.
// Grammar: arrayType: ID LSQBR RSQBR;
func (v *ManuscriptAstVisitor) VisitArrayType(ctx *parser.ArrayTypeContext) interface{} {
	var eltType ast.Expr
	typeName := ctx.ID().GetText()
	switch typeName {
	case "string":
		eltType = ast.NewIdent("string")
	case "int":
		eltType = ast.NewIdent("int64")
	case "float":
		eltType = ast.NewIdent("float64")
	case "bool":
		eltType = ast.NewIdent("bool")
	default:
		// For user-defined types or other built-ins not explicitly listed.
		// This assumes typeName is a valid Go identifier or will be resolved later.
		eltType = ast.NewIdent(typeName)
	}

	return &ast.ArrayType{
		// Len: nil, // For slices in Go, Len is nil
		Elt: eltType,
	}
}

// VisitFnType handles function type signatures from an FnTypeContext.
// Grammar: fnType: FN LPAREN parameters? RPAREN typeAnnotation?;
func (v *ManuscriptAstVisitor) VisitFnType(ctx *parser.FnTypeContext) interface{} {
	return v.buildAstFuncType(
		ctx.Parameters(),     // parser.IParametersContext or nil
		ctx.TypeAnnotation(), // parser.ITypeAnnotationContext or nil
		nil,                  // No ID for fnType
		nil,                  // No EXCLAMATION for fnType
		"anonymous function type",
		ctx.GetStart(), // Pass token for error reporting if needed by buildAstFuncType
	)
}

// VisitFunctionType now handles an FnSignatureContext directly to produce an *ast.FuncType.
// This is used by TypeAnnotation for function types like `fn(int): string`.
// It's also used for actual function signatures in fnDecl.
func (v *ManuscriptAstVisitor) VisitFunctionType(ctx *parser.FnSignatureContext) interface{} {
	var funcNameForError string
	var errorToken antlr.Token
	if ctx.ID() != nil {
		funcNameForError = ctx.ID().GetText() + " (in type signature)"
		errorToken = ctx.ID().GetSymbol()
	} else {
		// This path might not be hit if ID is mandatory in FnSignature grammar.
		funcNameForError = "function signature"
		errorToken = ctx.GetStart()
	}

	return v.buildAstFuncType(
		ctx.Parameters(),
		ctx.TypeAnnotation(),
		ctx.ID(),
		ctx.EXCLAMATION(),
		funcNameForError,
		errorToken,
	)
}

// buildAstFuncType is a helper to construct an *ast.FuncType from context parts.
func (v *ManuscriptAstVisitor) buildAstFuncType(
	paramsParserCtx parser.IParametersContext,
	returnTypeParserCtx parser.ITypeAnnotationContext,
	_ antlr.TerminalNode, // idNode, currently unused in this refactored helper but kept for signature consistency
	exclamationNode antlr.TerminalNode,
	errorContextName string,
	errorToken antlr.Token, // Token for error reporting context
) *ast.FuncType {

	paramsAST := &ast.FieldList{List: []*ast.Field{}}
	if paramsParserCtx != nil {
		if concreteParamsCtx, ok := paramsParserCtx.(*parser.ParametersContext); ok {
			if paramDetails, okVisit := v.VisitParameters(concreteParamsCtx).([]ParamDetail); okVisit {
				for _, detail := range paramDetails {
					if detail.DefaultValue != nil {
						v.addError(fmt.Sprintf("Default value for parameter '%s' not allowed in %s.", detail.Name.Name, errorContextName), detail.NameToken)
					}
					field := &ast.Field{Type: detail.Type}
					if detail.Name != nil && detail.Name.Name != "" {
						field.Names = []*ast.Ident{detail.Name}
					}
					paramsAST.List = append(paramsAST.List, field)
				}
			} else {
				// VisitParameters should ideally always return []ParamDetail or an error handled within it.
				// If it returns something else, that's an internal issue.
				v.addError(fmt.Sprintf("Internal error: VisitParameters did not return []ParamDetail for %s", errorContextName), concreteParamsCtx.GetStart())
			}
		} else if !paramsParserCtx.IsEmpty() {
			v.addError(fmt.Sprintf("Internal error: parameters context is not *parser.ParametersContext for %s", errorContextName), paramsParserCtx.GetStart())
			// Using gotoken.NoPos for BadExpr positions
			return &ast.FuncType{Params: &ast.FieldList{List: []*ast.Field{{Type: &ast.BadExpr{From: gotoken.NoPos, To: gotoken.NoPos}}}}}
		}
	}

	var concreteReturnTypeCtx *parser.TypeAnnotationContext
	if returnTypeParserCtx != nil {
		if c, ok := returnTypeParserCtx.(*parser.TypeAnnotationContext); ok {
			concreteReturnTypeCtx = c
		} else if !returnTypeParserCtx.IsEmpty() {
			v.addError(fmt.Sprintf("Internal error: return type context is not *parser.TypeAnnotationContext for %s", errorContextName), returnTypeParserCtx.GetStart())
			// Using gotoken.NoPos for BadExpr positions
			return &ast.FuncType{Results: &ast.FieldList{List: []*ast.Field{{Type: &ast.BadExpr{From: gotoken.NoPos, To: gotoken.NoPos}}}}}
		}
	}

	resultsAST := v.ProcessReturnType(concreteReturnTypeCtx, exclamationNode, errorContextName)

	return &ast.FuncType{
		Params:  paramsAST,
		Results: resultsAST,
	}
}

// VisitTupleType handles tuple type signatures.
// e.g., (Type1, Type2, Type3)
// Grammar for tupleType: LPAREN (typeAnnotation (COMMA typeAnnotation)*)? RPAREN;
func (v *ManuscriptAstVisitor) VisitTupleType(ctx *parser.TupleTypeContext) interface{} {
	fields := []*ast.Field{}
	typeAnnotations := ctx.TypeList().AllTypeAnnotation()

	for i, typeAntlrCtxInterface := range typeAnnotations {
		// Each element is an ITypeAnnotationContext
		typeAntlrCtx, okAssert := typeAntlrCtxInterface.(*parser.TypeAnnotationContext)
		if !okAssert {
			v.addError(fmt.Sprintf("Internal error: tuple type element %d is not TypeAnnotationContext", i), ctx.GetStart())
			return &ast.BadExpr{}
		}

		fieldTypeInterface := v.VisitTypeAnnotation(typeAntlrCtx)
		if fieldTypeExpr, ok := fieldTypeInterface.(ast.Expr); ok && fieldTypeExpr != nil {
			fieldName := fmt.Sprintf("_T%d", i) // Generates field names like _T0, _T1 for the struct
			fields = append(fields, &ast.Field{
				Names: []*ast.Ident{ast.NewIdent(fieldName)},
				Type:  fieldTypeExpr,
			})
		} else if fieldTypeInterface == nil { // Explicit void type in tuple element
			v.addError(fmt.Sprintf("Tuple element %d cannot be void: %s", i, typeAntlrCtx.GetText()), typeAntlrCtx.GetStart())
			return &ast.BadExpr{}
		} else { // Some other error from VisitTypeAnnotation
			v.addError(fmt.Sprintf("Invalid type for tuple element %d: %s", i, typeAntlrCtx.GetText()), typeAntlrCtx.GetStart())
			return &ast.BadExpr{}
		}
	}

	// Represent Manuscript tuple type as a Go struct type
	// Example: (int, string) -> struct { _T0 int; _T1 string }
	return &ast.StructType{
		Fields:     &ast.FieldList{List: fields},
		Incomplete: len(fields) == 0 && len(typeAnnotations) > 0, // Mark incomplete if parsing failed for some elements
	}
}

// handleVoidType processes void type appropriately for Go code.
// In Manuscript, 'void' is used where Go would typically use no return value.
// Returns nil to indicate absence of a return type, with the caller responsible for
// creating the appropriate empty FieldList.
func (v *ManuscriptAstVisitor) handleVoidType() ast.Expr {
	// In Go, a function with no return values has a nil or empty result FieldList.
	// We return nil here to indicate there is no return type, not even an empty interface.
	return nil
}
