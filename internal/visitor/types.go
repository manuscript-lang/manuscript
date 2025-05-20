package visitor

import (
	"fmt"
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitTypeAnnotation handles type annotations based on the new grammar:
// typeAnnotation: (idAsType=ID | tupleAsType=tupleType | funcAsType=fnSignature | VOID) (isNullable=QUESTION)? (arrayMarker=LSQBR RSQBR)?;
func (v *ManuscriptAstVisitor) VisitTypeAnnotation(ctx *parser.TypeAnnotationContext) interface{} {
	var baseExpr ast.Expr

	if ctx.VOID() != nil {
		// Void type is represented as nil ast.Expr
		baseExpr = v.handleVoidType()
	} else if ctx.GetIdAsType() != nil {
		typeName := ctx.GetIdAsType().GetText()
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
	} else if ctx.GetTupleAsType() != nil {
		tupleTypeCtx := ctx.GetTupleAsType().(*parser.TupleTypeContext) // This is *parser.TupleTypeContext
		visitedTuple := v.VisitTupleType(tupleTypeCtx)
		if vt, ok := visitedTuple.(ast.Expr); ok {
			baseExpr = vt
		} else {
			v.addError("Tuple type annotation did not resolve to an expression: "+tupleTypeCtx.GetText(), tupleTypeCtx.GetStart())
			return &ast.BadExpr{}
		}
	} else if ctx.GetFuncAsType() != nil {
		fnSigCtx := ctx.GetFuncAsType().(*parser.FnSignatureContext) // This is *parser.FnSignatureContext
		visitedFnSig := v.VisitFunctionType(fnSigCtx)
		if ft, ok := visitedFnSig.(ast.Expr); ok { // *ast.FuncType is an ast.Expr
			baseExpr = ft
		} else {
			v.addError("Function type annotation (fnSignature) did not resolve to an ast.FuncType: "+fnSigCtx.GetText(), fnSigCtx.GetStart())
			return &ast.BadExpr{}
		}
	} else {
		v.addError("Invalid type annotation structure: "+ctx.GetText(), ctx.GetStart())
		return &ast.BadExpr{}
	}

	// Handle optional nullable marker '?'
	if ctx.QUESTION() != nil {
		if baseExpr == nil { // void?
			v.addError("Cannot make void type nullable: "+ctx.GetText(), ctx.QUESTION().GetSymbol())
			return &ast.BadExpr{}
		}

		isAlreadyNullableOrPointer := false
		switch be := baseExpr.(type) {
		case *ast.StarExpr: // Already a pointer *T
			isAlreadyNullableOrPointer = true
		case *ast.Ident:
			if be.Name == "interface{}" { // interface{} is nullable
				isAlreadyNullableOrPointer = true
			}
		case *ast.ArrayType: // Represents a slice Type[], which is nullable
			isAlreadyNullableOrPointer = true
		case *ast.MapType: // map[K]V is nullable
			isAlreadyNullableOrPointer = true
		case *ast.FuncType: // fn() is nullable
			isAlreadyNullableOrPointer = true
			// Note: ast.StructType is a value type and needs *ast.StarExpr if nullable.
		}

		if !isAlreadyNullableOrPointer {
			baseExpr = &ast.StarExpr{X: baseExpr}
		}
	}

	// Handle optional array marker '[]'
	if ctx.LSQBR() != nil && ctx.RSQBR() != nil { // arrayMarker = LSQBR RSQBR
		if baseExpr == nil { // Cannot have array of void, e.g. void[]
			v.addError("Cannot create an array of void type: "+ctx.GetText(), ctx.LSQBR().GetSymbol())
			return &ast.BadExpr{}
		}
		return &ast.ArrayType{Elt: baseExpr} // Represents a slice in Go AST if Len is nil
	}

	return baseExpr // Return nil for void if not an array/nullable, or the ast.Expr
}

// VisitFunctionType now handles an FnSignatureContext directly to produce an *ast.FuncType.
// This is used by TypeAnnotation for function types like `fn(int): string`.
func (v *ManuscriptAstVisitor) VisitFunctionType(ctx *parser.FnSignatureContext) interface{} {
	var funcNameForError string
	if ctx.NamedID() != nil { // fnSignature can have a name, but in type context it is anonymous
		funcNameForError = ctx.NamedID().GetText() + " (in type signature)"
	} else {
		funcNameForError = "anonymous function type"
	}

	// Assuming FnSignatureContext has Parameters() IParametersContext and TypeAnnotation() ITypeAnnotationContext
	paramsAST, _, paramDetails := v.ProcessParameters(ctx.Parameters()) // Use existing helper

	// Check for default values in function type parameters, which is usually not allowed.
	for _, detail := range paramDetails {
		if detail.DefaultValue != nil {
			v.addError(fmt.Sprintf("Default value for parameter '%s' not allowed in function type signature.", detail.Name.Name), detail.NameToken)
			// Depending on strictness, might return nil or BadExpr here
		}
	}

	// Interface methods in Go AST don't have parameter names, only types.
	// Function types in Go also typically only care about types for matching.
	// Create a new FieldList for Params with only types.
	paramTypesOnlyAST := &ast.FieldList{List: []*ast.Field{}}
	if paramsAST != nil {
		for _, p := range paramsAST.List {
			paramTypesOnlyAST.List = append(paramTypesOnlyAST.List, &ast.Field{Type: p.Type})
		}
	}

	resultsAST := v.ProcessReturnType(ctx.TypeAnnotation(), ctx.EXCLAMATION(), funcNameForError) // Use existing helper

	return &ast.FuncType{
		Params:  paramTypesOnlyAST,
		Results: resultsAST,
	}
}

// VisitTupleType handles tuple type signatures.
// e.g., (Type1, Type2, Type3)
// Grammar for tupleType: LPAREN (typeAnnotation (COMMA typeAnnotation)*)? RPAREN;
func (v *ManuscriptAstVisitor) VisitTupleType(ctx *parser.TupleTypeContext) interface{} {
	fields := []*ast.Field{}
	typeAnnotations := ctx.GetElements().GetTypes() // Assuming this is the correct accessor

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
