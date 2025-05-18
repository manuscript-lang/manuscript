package visitor

import (
	"fmt"
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitTypeAnnotation handles type annotations based on the new grammar:
// typeAnnotation: (idAsType=ID | tupleAsType=tupleType | funcAsType=fnSignature | objAsType=objectTypeAnnotation | mapAsType=mapTypeAnnotation | setAsType=setTypeAnnotation | VOID) (isNullable=QUESTION)? (arrayMarker=LSQBR RSQBR)?;
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
		case "any":
			baseExpr = ast.NewIdent("interface{}")
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
	} else if ctx.GetObjAsType() != nil {
		objTypeCtx := ctx.GetObjAsType().(*parser.ObjectTypeAnnotationContext) // This is *parser.ObjectTypeAnnotationContext
		visitedObj := v.VisitObjectTypeAnnotation(objTypeCtx)
		if ot, ok := visitedObj.(ast.Expr); ok {
			baseExpr = ot
		} else {
			v.addError("Object type annotation did not resolve to an expression: "+objTypeCtx.GetText(), objTypeCtx.GetStart())
			return &ast.BadExpr{}
		}
	} else if ctx.GetMapAsType() != nil {
		mapTypeCtx := ctx.GetMapAsType().(*parser.MapTypeAnnotationContext) // This is *parser.MapTypeAnnotationContext
		visitedMap := v.VisitMapTypeAnnotation(mapTypeCtx)
		if mt, ok := visitedMap.(ast.Expr); ok {
			baseExpr = mt
		} else {
			v.addError("Map type annotation did not resolve to an expression: "+mapTypeCtx.GetText(), mapTypeCtx.GetStart())
			return &ast.BadExpr{}
		}
	} else if ctx.GetSetAsType() != nil {
		setTypeCtx := ctx.GetSetAsType().(*parser.SetTypeAnnotationContext) // This is *parser.SetTypeAnnotationContext
		visitedSet := v.VisitSetTypeAnnotation(setTypeCtx)
		if st, ok := visitedSet.(ast.Expr); ok {
			baseExpr = st
		} else {
			v.addError("Set type annotation did not resolve to an expression: "+setTypeCtx.GetText(), setTypeCtx.GetStart())
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

// VisitObjectTypeAnnotation handles object type annotations like `{ name: string, age?: int }`
// Grammar: objectTypeAnnotation: LBRACE (fields += fieldDecl (COMMA fields += fieldDecl)* (COMMA)?)? RBRACE;
// fieldDecl: fieldName = namedID (isOptionalField = QUESTION)? COLON type = typeAnnotation;
func (v *ManuscriptAstVisitor) VisitObjectTypeAnnotation(ctx *parser.ObjectTypeAnnotationContext) interface{} {
	fields := []*ast.Field{}
	if ctx.AllFieldDecl() != nil {
		for _, fieldDeclCtxInterface := range ctx.AllFieldDecl() {
			fieldDeclCtx := fieldDeclCtxInterface.(*parser.FieldDeclContext)
			fieldNameNode := fieldDeclCtx.GetFieldName()
			if fieldNameNode == nil {
				v.addError("Missing field name in object type annotation", fieldDeclCtx.GetStart())
				return &ast.BadExpr{}
			}
			fieldName := fieldNameNode.GetText()

			typeAntlrCtx := fieldDeclCtx.GetType_()
			if typeAntlrCtx == nil {
				v.addError(fmt.Sprintf("Missing type for field '%s' in object type", fieldName), fieldDeclCtx.GetStart())
				return &ast.BadExpr{}
			}

			fieldTypeInterface := v.VisitTypeAnnotation(typeAntlrCtx.(*parser.TypeAnnotationContext))
			var fieldTypeExpr ast.Expr
			if ftExpr, ok := fieldTypeInterface.(ast.Expr); ok && ftExpr != nil {
				fieldTypeExpr = ftExpr
			} else if fieldTypeInterface == nil { // void type
				v.addError(fmt.Sprintf("Field '%s' in object type cannot be void: %s", fieldName, typeAntlrCtx.GetText()), typeAntlrCtx.GetStart())
				return &ast.BadExpr{}
			} else {
				v.addError(fmt.Sprintf("Invalid type for field '%s' in object type: %s", fieldName, typeAntlrCtx.GetText()), typeAntlrCtx.GetStart())
				return &ast.BadExpr{}
			}

			if fieldDeclCtx.QUESTION() != nil { // isOptionalField
				isAlreadyNullableOrPointer := false
				switch ft := fieldTypeExpr.(type) {
				case *ast.StarExpr:
					isAlreadyNullableOrPointer = true
				case *ast.Ident:
					if ft.Name == "interface{}" {
						isAlreadyNullableOrPointer = true
					}
				case *ast.ArrayType, *ast.MapType, *ast.FuncType:
					isAlreadyNullableOrPointer = true
				}
				if !isAlreadyNullableOrPointer {
					fieldTypeExpr = &ast.StarExpr{X: fieldTypeExpr}
				}
			}

			fields = append(fields, &ast.Field{
				Names: []*ast.Ident{ast.NewIdent(fieldName)},
				Type:  fieldTypeExpr,
			})
		}
	}

	return &ast.StructType{
		Fields:     &ast.FieldList{List: fields},
		Incomplete: false, // If any field parse fails, we return BadExpr from loop.
	}
}

// VisitMapTypeAnnotation handles map type annotations like `[string: int]`
// Grammar: mapTypeAnnotation: LSQBR keyType = typeAnnotation COLON valueType = typeAnnotation RSQBR;
func (v *ManuscriptAstVisitor) VisitMapTypeAnnotation(ctx *parser.MapTypeAnnotationContext) interface{} {
	keyTypeAntlrCtx := ctx.GetKeyType()
	if keyTypeAntlrCtx == nil {
		v.addError("Missing key type in map type annotation", ctx.GetStart())
		return &ast.BadExpr{}
	}
	keyTypeInterface := v.VisitTypeAnnotation(keyTypeAntlrCtx.(*parser.TypeAnnotationContext))
	var keyTypeExpr ast.Expr
	if ktExpr, ok := keyTypeInterface.(ast.Expr); ok && ktExpr != nil {
		keyTypeExpr = ktExpr
	} else {
		errorMsg := "Invalid key type for map type annotation"
		if keyTypeInterface == nil {
			errorMsg = "Key type for map type annotation cannot be void"
		}
		v.addError(errorMsg+": "+keyTypeAntlrCtx.GetText(), keyTypeAntlrCtx.GetStart())
		return &ast.BadExpr{}
	}

	valueTypeAntlrCtx := ctx.GetValueType()
	if valueTypeAntlrCtx == nil {
		v.addError("Missing value type in map type annotation", ctx.GetStart())
		return &ast.BadExpr{}
	}
	valueTypeInterface := v.VisitTypeAnnotation(valueTypeAntlrCtx.(*parser.TypeAnnotationContext))
	var valueTypeExpr ast.Expr
	if vtExpr, ok := valueTypeInterface.(ast.Expr); ok && vtExpr != nil {
		valueTypeExpr = vtExpr
	} else {
		errorMsg := "Invalid value type for map type annotation"
		if valueTypeInterface == nil {
			errorMsg = "Value type for map type annotation cannot be void"
		}
		v.addError(errorMsg+": "+valueTypeAntlrCtx.GetText(), valueTypeAntlrCtx.GetStart())
		return &ast.BadExpr{}
	}

	return &ast.MapType{
		Key:   keyTypeExpr,
		Value: valueTypeExpr,
	}
}

// VisitSetTypeAnnotation handles set type annotations like `<int>`
// This will be represented as map[ElementType]struct{} in Go.
// Grammar: setTypeAnnotation: LT elementType = typeAnnotation GT;
func (v *ManuscriptAstVisitor) VisitSetTypeAnnotation(ctx *parser.SetTypeAnnotationContext) interface{} {
	elementTypeAntlrCtx := ctx.GetElementType()
	if elementTypeAntlrCtx == nil {
		v.addError("Missing element type in set type annotation", ctx.GetStart())
		return &ast.BadExpr{}
	}
	elementTypeInterface := v.VisitTypeAnnotation(elementTypeAntlrCtx.(*parser.TypeAnnotationContext))
	var elementTypeExpr ast.Expr
	if etExpr, ok := elementTypeInterface.(ast.Expr); ok && etExpr != nil {
		elementTypeExpr = etExpr
	} else {
		errorMsg := "Invalid element type for set type annotation"
		if elementTypeInterface == nil {
			errorMsg = "Element type for set type annotation cannot be void"
		}
		v.addError(errorMsg+": "+elementTypeAntlrCtx.GetText(), elementTypeAntlrCtx.GetStart())
		return &ast.BadExpr{}
	}

	return &ast.MapType{
		Key:   elementTypeExpr,
		Value: &ast.StructType{Fields: &ast.FieldList{List: []*ast.Field{}}}, // Represents struct{}
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
