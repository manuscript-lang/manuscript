package visitor

import (
	"fmt"
	"go/ast"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// VisitTypeAnnotation dispatches to the correct type annotation handler using the ANTLR visitor pattern.
func (v *ManuscriptAstVisitor) VisitTypeAnnotation(ctx *parser.TypeAnnotationContext) interface{} {
	if ctx == nil {
		v.addError("VisitTypeAnnotation called with nil context", nil)
		return &ast.BadExpr{}
	}
	return ctx.Accept(v)
}

// VisitLabelTypeAnnID handles simple identifier type annotations (e.g., int, string, MyType).
func (v *ManuscriptAstVisitor) VisitLabelTypeAnnID(ctx *parser.LabelTypeAnnIDContext) interface{} {
	if ctx == nil || ctx.ID() == nil {
		v.addError("TypeAnnID missing ID", ctx.GetStart())
		return &ast.BadExpr{}
	}
	switch name := ctx.ID().GetText(); name {
	case "string":
		return ast.NewIdent("string")
	case "int":
		return ast.NewIdent("int64")
	case "float":
		return ast.NewIdent("float64")
	case "bool":
		return ast.NewIdent("bool")
	default:
		return ast.NewIdent(name)
	}
}

// VisitLabelTypeAnnArray handles array type annotations (e.g., int[]).
func (v *ManuscriptAstVisitor) VisitLabelTypeAnnArray(ctx *parser.LabelTypeAnnArrayContext) interface{} {
	arrayTypeCtx, ok := ctx.ArrayType().(*parser.ArrayTypeContext)
	if ctx == nil || !ok || arrayTypeCtx == nil {
		v.addError("TypeAnnArray missing or invalid ArrayType", ctx.GetStart())
		return &ast.BadExpr{}
	}
	result := v.VisitArrayType(arrayTypeCtx)
	if expr, ok := result.(ast.Expr); ok {
		return expr
	}
	v.addError("Array type annotation did not resolve to an expression", ctx.GetStart())
	return &ast.BadExpr{}
}

// VisitLabelTypeAnnTuple handles tuple type annotations (e.g., (int, string)).
func (v *ManuscriptAstVisitor) VisitLabelTypeAnnTuple(ctx *parser.LabelTypeAnnTupleContext) interface{} {
	tupleTypeCtx, ok := ctx.TupleType().(*parser.TupleTypeContext)
	if ctx == nil || !ok || tupleTypeCtx == nil {
		v.addError("TypeAnnTuple missing or invalid TupleType", ctx.GetStart())
		return &ast.BadExpr{}
	}
	result := v.VisitTupleType(tupleTypeCtx)
	if expr, ok := result.(ast.Expr); ok {
		return expr
	}
	v.addError("Tuple type annotation did not resolve to an expression", ctx.GetStart())
	return &ast.BadExpr{}
}

// VisitLabelTypeAnnFn handles function type annotations (e.g., fn(int): string).
func (v *ManuscriptAstVisitor) VisitLabelTypeAnnFn(ctx *parser.LabelTypeAnnFnContext) interface{} {
	fnTypeCtx, ok := ctx.FnType().(*parser.FnTypeContext)
	if ctx == nil || !ok || fnTypeCtx == nil {
		v.addError("TypeAnnFn missing or invalid FnType", ctx.GetStart())
		return &ast.BadExpr{}
	}
	result := v.VisitFnType(fnTypeCtx)
	if expr, ok := result.(ast.Expr); ok {
		return expr
	}
	v.addError("Function type annotation did not resolve to an expression", ctx.GetStart())
	return &ast.BadExpr{}
}

// VisitLabelTypeAnnVoid handles the void type annotation.
func (v *ManuscriptAstVisitor) VisitLabelTypeAnnVoid(ctx *parser.LabelTypeAnnVoidContext) interface{} {
	return v.handleVoidType()
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
		nil,                  // No EXCLAMATION for fnType
		"anonymous function type",
	)
}

// VisitFunctionType now handles an FnSignatureContext directly to produce an *ast.FuncType.
// This is used by TypeAnnotation for function types like `fn(int): string`.
// It's also used for actual function signatures in fnDecl.
func (v *ManuscriptAstVisitor) VisitFunctionType(ctx *parser.FnSignatureContext) interface{} {
	var funcNameForError string
	if ctx.ID() != nil {
		funcNameForError = ctx.ID().GetText() + " (in type signature)"
	} else {
		// This path might not be hit if ID is mandatory in FnSignature grammar.
		funcNameForError = "function signature"
	}

	return v.buildAstFuncType(
		ctx.Parameters(),
		ctx.TypeAnnotation(),
		ctx.EXCLAMATION(),
		funcNameForError,
	)
}

// buildAstFuncType constructs an *ast.FuncType from parameter and return type contexts.
func (v *ManuscriptAstVisitor) buildAstFuncType(
	paramsCtx parser.IParametersContext,
	returnTypeCtx parser.ITypeAnnotationContext,
	exclNode antlr.TerminalNode,
	desc string,
) *ast.FuncType {
	params := v.buildFuncParams(paramsCtx, desc)
	results := v.buildFuncResults(returnTypeCtx, exclNode, desc)
	return &ast.FuncType{Params: params, Results: results}
}

// buildFuncParams processes the parameters context into a Go AST FieldList.
func (v *ManuscriptAstVisitor) buildFuncParams(paramsCtx parser.IParametersContext, desc string) *ast.FieldList {
	params := &ast.FieldList{List: []*ast.Field{}}
	if paramsCtx == nil {
		return params
	}
	concrete, ok := paramsCtx.(*parser.ParametersContext)
	if !ok {
		if !paramsCtx.IsEmpty() {
			v.addError("Internal error: parameters context is not *parser.ParametersContext for "+desc, paramsCtx.GetStart())
			return &ast.FieldList{List: []*ast.Field{{Type: &ast.BadExpr{}}}}
		}
		return params
	}
	details, ok := v.VisitParameters(concrete).([]ParamDetail)
	if !ok {
		v.addError("Internal error: VisitParameters did not return []ParamDetail for "+desc, concrete.GetStart())
		return params
	}
	for _, d := range details {
		if d.DefaultValue != nil {
			v.addError(
				fmt.Sprintf("Default value for parameter '%s' not allowed in %s.", d.Name.Name, desc),
				d.NameToken,
			)
		}
		field := &ast.Field{Type: d.Type}
		if d.Name != nil && d.Name.Name != "" {
			field.Names = []*ast.Ident{d.Name}
		}
		params.List = append(params.List, field)
	}
	return params
}

// buildFuncResults processes the return type context into a Go AST FieldList.
func (v *ManuscriptAstVisitor) buildFuncResults(
	returnTypeCtx parser.ITypeAnnotationContext,
	exclNode antlr.TerminalNode,
	desc string,
) *ast.FieldList {
	// Always use the visitor pattern for return type
	return v.ProcessReturnType(returnTypeCtx, exclNode, desc)
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
