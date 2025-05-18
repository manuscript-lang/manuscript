package visitor

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"
	"reflect"

	"github.com/antlr4-go/antlr/v4"
)

// processTypeAnnotationToExpr visits a TypeAnnotationContext and expects an ast.Expr.
// It adds an error and returns (nil, false) on failure.
// 'contextDescription' is used in error messages.
func (v *ManuscriptAstVisitor) processTypeAnnotationToExpr(
	typeAnnCtx parser.ITypeAnnotationContext,
	contextDescription string,
) (ast.Expr, bool) {
	if typeAnnCtx == nil {
		// This should ideally be caught by the caller before passing nil.
		// Providing a generic token or nil if no specific token is available.
		v.addError("Internal error: nil TypeAnnotation provided for "+contextDescription, nil)
		return nil, false
	}

	concreteTypeAnnCtx, ok := typeAnnCtx.(*parser.TypeAnnotationContext)
	if !ok {
		// This case means ITypeAnnotationContext was not its concrete *parser.TypeAnnotationContext.
		// This should ideally not happen if the grammar and parser generation are consistent.
		v.addError("Internal error: unexpected type for TypeAnnotation ("+reflect.TypeOf(typeAnnCtx).String()+") for "+contextDescription, typeAnnCtx.GetStart())
		return nil, false
	}

	visitedNode := v.VisitTypeAnnotation(concreteTypeAnnCtx) // Visit the concrete type
	expr, isExpr := visitedNode.(ast.Expr)
	if !isExpr || expr == nil {
		v.addError("Invalid type expression for "+contextDescription+": "+concreteTypeAnnCtx.GetText(), concreteTypeAnnCtx.GetStart())
		return nil, false
	}
	return expr, true
}

// VisitTypeDecl handles type declarations (structs and aliases).
// type MyStruct { field: Type } or type MyAlias = AnotherType
func (v *ManuscriptAstVisitor) VisitTypeDecl(ctx *parser.TypeDeclContext) interface{} {
	if ctx.GetTypeName() == nil || ctx.GetTypeName().GetText() == "" {
		v.addError("Type declaration is missing a name.", ctx.GetStart())
		return nil
	}
	typeNameStr := ctx.GetTypeName().GetText()

	// Check for type alias vs. struct definition
	if typeAliasCtx := ctx.TypeAlias(); typeAliasCtx != nil {
		// This is a type alias: type Name = AliasType
		aliasTargetNode := typeAliasCtx.GetAliasTarget()
		if aliasTargetNode == nil {
			// Should not happen if grammar is `typeAlias: EQUALS aliasTarget=typeAnnotation`
			v.addError("Malformed type alias for \""+typeNameStr+"\": missing alias target.", typeAliasCtx.GetStart())
			return nil
		}

		aliasTypeExpr, ok := v.processTypeAnnotationToExpr(aliasTargetNode, "alias target for \""+typeNameStr+"\"")
		if !ok {
			return nil // Error already added by helper
		}

		log.Printf("VisitTypeDecl: '%s' is a type alias for %T", typeNameStr, aliasTypeExpr)
		// TODO: Handle EXTENDS constraintTypes = typeList for type aliases if needed in Go output
		return &ast.GenDecl{
			Tok: token.TYPE,
			Specs: []ast.Spec{
				&ast.TypeSpec{
					Name: ast.NewIdent(typeNameStr),
					Type: aliasTypeExpr,
				},
			},
		}
	} else if typeDefBodyCtx := ctx.TypeDefBody(); typeDefBodyCtx != nil {
		// This is a struct-like type definition
		log.Printf("VisitTypeDecl: '%s' is a struct type", typeNameStr)
		structFields := []*ast.Field{}

		// Handle EXTENDS (embedded base types)
		if typeDefBodyCtx.EXTENDS() != nil {
			extendedTypesListCtx := typeDefBodyCtx.GetExtendedTypes()
			if extendedTypesListCtx == nil {
				// This case should ideally not be reached if grammar ensures TypeList is present when EXTENDS exists.
				v.addError("Type \""+typeNameStr+"\" has EXTENDS clause but no valid base types structure found.", typeDefBodyCtx.EXTENDS().GetSymbol())
				return nil
			}

			baseTypesAntlr := extendedTypesListCtx.GetTypes() // This is []ITypeAnnotationContext
			if len(baseTypesAntlr) == 0 {
				// EXTENDS token present, but GetTypes() returned empty list
				v.addError("Type \""+typeNameStr+"\" has EXTENDS clause but no base types specified.", typeDefBodyCtx.EXTENDS().GetSymbol())
				return nil
			}

			for _, baseTypeAntlrNode := range baseTypesAntlr {
				baseTypeExpr, ok := v.processTypeAnnotationToExpr(baseTypeAntlrNode, "base type for struct \""+typeNameStr+"\"")
				if !ok {
					return nil // Error added by helper
				}
				// Embedded fields in Go have no name, just the type
				structFields = append(structFields, &ast.Field{Type: baseTypeExpr})
			}
		}

		// Handle declared fields
		// fields += fieldDecl (COMMA fields += fieldDecl)* (COMMA)?
		for _, fieldDeclAntlrNode := range typeDefBodyCtx.GetFields() { // GetFields returns []IFieldDeclContext
			fieldDeclCtx, isFieldDeclCtx := fieldDeclAntlrNode.(*parser.FieldDeclContext)
			if !isFieldDeclCtx {
				token := ctx.GetTypeName().GetStart() // Fallback
				if prc, okPrc := fieldDeclAntlrNode.(antlr.ParserRuleContext); okPrc {
					token = prc.GetStart()
				}
				v.addError("Internal error: Unexpected structure for field declaration in \""+typeNameStr+"\". Expected FieldDeclContext, got "+reflect.TypeOf(fieldDeclAntlrNode).String(), token)
				return nil
			}

			visitedField := v.VisitFieldDecl(fieldDeclCtx)
			astField, isAstField := visitedField.(*ast.Field)
			if !isAstField || astField == nil {
				// If visitedField was nil, VisitFieldDecl already added an error.
				// If it was not nil but not *ast.Field, it's an internal error.
				if visitedField != nil {
					v.addError("Internal error: Field declaration processing for struct \""+typeNameStr+"\" returned unexpected type.", fieldDeclCtx.GetStart())
				}
				return nil
			}

			// Properly set field names
			if len(astField.Names) > 0 {
				fieldName := astField.Names[0].Name
				log.Printf("Adding field '%s' to struct '%s'", fieldName, typeNameStr)
			} else {
				log.Printf("Adding unnamed field to struct '%s'", typeNameStr)
			}

			structFields = append(structFields, astField)
		}

		return &ast.GenDecl{
			Tok: token.TYPE,
			Specs: []ast.Spec{
				&ast.TypeSpec{
					Name: ast.NewIdent(typeNameStr),
					Type: &ast.StructType{Fields: &ast.FieldList{List: structFields}},
				},
			},
		}
	} else {
		// Neither TypeAlias nor TypeDefBody is present, which is an issue.
		v.addError("Malformed type declaration for \""+typeNameStr+"\": missing struct body or alias target.", ctx.GetTypeName().GetStart())
		return nil
	}
}

// VisitFieldDecl handles field declarations within a type (struct).
// fieldDecl: fieldName = namedID (isOptionalField = QUESTION)? COLON type = typeAnnotation;
func (v *ManuscriptAstVisitor) VisitFieldDecl(ctx *parser.FieldDeclContext) interface{} {
	if ctx.GetFieldName() == nil || ctx.GetFieldName().GetName() == nil { // Check NamedID and its internal ID token
		v.addError("Field declaration is missing a name.", ctx.GetStart())
		return nil
	}
	fieldName := ctx.GetFieldName().GetName().GetText()
	isOptional := ctx.QUESTION() != nil // isOptionalField = QUESTION in grammar, check for QUESTION token directly

	var fieldType ast.Expr
	typeAnnotationNode := ctx.GetType_() // GetType_() because 'type' is a label, returns ITypeAnnotationContext
	if typeAnnotationNode == nil {
		v.addError("Missing type annotation for field \""+fieldName+"\".", ctx.GetFieldName().GetName())
		return nil
	}

	var ok bool
	fieldType, ok = v.processTypeAnnotationToExpr(typeAnnotationNode, "type for field \""+fieldName+"\"")
	if !ok {
		return nil // Error added by helper
	}

	// If the field is optional, and the type is not already a pointer or map or slice, make it a pointer.
	// This is a common way to represent optional fields in Go.
	if isOptional {
		switch fieldType.(type) {
		case *ast.Ident, *ast.SelectorExpr: // Simple types or qualified types that are not pointers
			fieldType = &ast.StarExpr{X: fieldType}
			log.Printf("VisitFieldDecl: Field '%s' is optional, converted type to pointer: %T", fieldName, fieldType)
		case *ast.StarExpr, *ast.ArrayType, *ast.MapType, *ast.InterfaceType, *ast.FuncType:
			log.Printf("VisitFieldDecl: Field '%s' is optional, but type %T is already a pointer/reference type.", fieldName, fieldType)
		default:
			log.Printf("VisitFieldDecl: Field '%s' is optional, but its type %T is not being converted to a pointer automatically. Consider manual pointer if needed.", fieldName, fieldType)
		}
	}

	return &ast.Field{
		Names: []*ast.Ident{ast.NewIdent(fieldName)},
		Type:  fieldType,
		// TODO: Handle tags if Manuscript supports struct tags for fields
	}
}
