package visitor

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// VisitTypeDecl handles type declarations (structs and aliases).
// type MyStruct { field: Type } or type MyAlias = AnotherType
func (v *ManuscriptAstVisitor) VisitTypeDecl(ctx *parser.TypeDeclContext) interface{} {
	typeNameStr := ctx.ID().GetText()
	// Check for type alias: type Name = AliasType
	// The grammar is: typeDecl: ... (LBRACE ... | EQ alias=typeAnnotation SEMICOLON? );
	// We look for the presence of LBRACE. If not present, and an alias TypeAnnotation is, it's an alias.
	// TypeDeclContext has `_typeAnnotation ITypeAnnotationContext` which is the `alias` if EQ is used.
	// It also has `AllFieldDecl()` and `LBRACE()`.

	if ctx.LBRACE() == nil { // Potentially an alias if Get_typeAnnotation() is not nil
		if aliasTypeCtx := ctx.Get_typeAnnotation(); aliasTypeCtx != nil {
			// This is a type alias
			if concreteAliasTypeCtx, ok := aliasTypeCtx.(*parser.TypeAnnotationContext); ok {
				visitedAliasType := v.VisitTypeAnnotation(concreteAliasTypeCtx)
				if aliasTypeExpr, isExpr := visitedAliasType.(ast.Expr); isExpr && aliasTypeExpr != nil {
					log.Printf("VisitTypeDecl: '%s' is a type alias for %T", typeNameStr, aliasTypeExpr)
					return &ast.GenDecl{
						Tok: token.TYPE,
						Specs: []ast.Spec{
							&ast.TypeSpec{
								Name: ast.NewIdent(typeNameStr),
								Type: aliasTypeExpr,
							},
						},
					}
				} else {
					v.addError("Type alias \""+typeNameStr+"\" has an invalid or void target type: "+concreteAliasTypeCtx.GetText(), concreteAliasTypeCtx.GetStart())
					return nil
				}
			} else {
				token := ctx.ID().GetSymbol() // Fallback
				if prc, okPrc := aliasTypeCtx.(antlr.ParserRuleContext); okPrc {
					token = prc.GetStart()
				}
				v.addError("Internal error: Unexpected structure for alias type target of \""+typeNameStr+"\".", token)
				return nil
			}
		} else {
			// No LBRACE and no alias type annotation - this should ideally not happen based on the grammar structure presented.
			// It could imply `type Foo;` which is not valid Go for a new type without definition.
			v.addError("Malformed type declaration for \""+typeNameStr+"\": missing struct body or alias target.", ctx.ID().GetSymbol())
			return nil
		}
	} else {
		// This is a struct-like type definition
		log.Printf("VisitTypeDecl: '%s' is a struct type", typeNameStr)
		structFields := []*ast.Field{}

		// Handle EXTENDS (embedded base types)
		if ctx.EXTENDS() != nil {
			// baseTypes are stored in TypeDeclContext.baseTypes []ITypeAnnotationContext
			// The parser rule uses `baseTypes+=typeAnnotation`
			for _, baseTypeAntlrInterface := range ctx.GetBaseTypes() {
				if baseTypeAntlrCtx, okAssert := baseTypeAntlrInterface.(*parser.TypeAnnotationContext); okAssert {
					visitedBaseType := v.VisitTypeAnnotation(baseTypeAntlrCtx)
					if baseTypeExpr, isExpr := visitedBaseType.(ast.Expr); isExpr && baseTypeExpr != nil {
						// Embedded fields in Go have no name, just the type
						structFields = append(structFields, &ast.Field{Type: baseTypeExpr})
					} else {
						v.addError("Base type \""+baseTypeAntlrCtx.GetText()+"\" for struct \""+typeNameStr+"\" is invalid or void.", baseTypeAntlrCtx.GetStart())
						return nil // Error processing a base type
					}
				} else {
					token := ctx.ID().GetSymbol() // Fallback
					if prc, okPrc := baseTypeAntlrInterface.(antlr.ParserRuleContext); okPrc {
						token = prc.GetStart()
					}
					v.addError("Internal error: Unexpected structure for base type of \""+typeNameStr+"\".", token)
					return nil
				}
			}
		}

		// Handle declared fields
		for _, fieldDeclCtxInterface := range ctx.AllFieldDecl() {
			if fieldDeclCtx, okAssert := fieldDeclCtxInterface.(*parser.FieldDeclContext); okAssert {
				visitedField := v.VisitFieldDecl(fieldDeclCtx)
				if astField, isField := visitedField.(*ast.Field); isField && astField != nil {
					structFields = append(structFields, astField)
				} else {
					// Error already added by VisitFieldDecl if it returned nil.
					if visitedField != nil { // If it wasn't nil, then it was an unexpected type.
						v.addError("Internal error: Field declaration processing for struct \""+typeNameStr+"\" returned unexpected type.", fieldDeclCtx.GetStart())
					}
					return nil // Error processing a field
				}
			} else {
				token := ctx.ID().GetSymbol() // Fallback
				if prc, okPrc := fieldDeclCtxInterface.(antlr.ParserRuleContext); okPrc {
					token = prc.GetStart()
				}
				v.addError("Internal error: Unexpected structure for field declaration in \""+typeNameStr+"\".", token)
				return nil
			}
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
	}
}

// VisitFieldDecl handles field declarations within a type (struct).
// fieldDecl: (COMMENT_START? QUESTION COMMENT_END?)? name=ID (QUESTION)? COLON typeAnnotation SEMICOLON?;
func (v *ManuscriptAstVisitor) VisitFieldDecl(ctx *parser.FieldDeclContext) interface{} {
	fieldName := ctx.GetName().GetText()
	isOptional := ctx.QUESTION() != nil // Check if the '?' token is present after the name

	var fieldType ast.Expr
	if ctx.TypeAnnotation() != nil {
		typeInterface := v.VisitTypeAnnotation(ctx.TypeAnnotation().(*parser.TypeAnnotationContext))
		if ft, ok := typeInterface.(ast.Expr); ok {
			fieldType = ft
		} else {
			v.addError("Invalid type for field \""+fieldName+"\": "+ctx.TypeAnnotation().GetText(), ctx.TypeAnnotation().GetStart())
			return nil // Field must have a valid type
		}
	} else {
		v.addError("Missing type annotation for field \""+fieldName+"\".", ctx.GetName())
		return nil // Field must have a type
	}

	// If the field is optional, and the type is not already a pointer or map or slice, make it a pointer.
	// This is a common way to represent optional fields in Go.
	if isOptional {
		switch fieldType.(type) {
		case *ast.Ident, *ast.SelectorExpr: // Simple types or qualified types that are not pointers
			// Check if it's already a pointer through some other means, though TypeAnnotation should handle base pointers.
			// For simplicity, we assume if it's an Ident or SelectorExpr, it's not yet a pointer from this optional marker.
			fieldType = &ast.StarExpr{X: fieldType}
			log.Printf("VisitFieldDecl: Field '%s' is optional, converted type to pointer: %T", fieldName, fieldType)
		case *ast.StarExpr, *ast.ArrayType, *ast.MapType, *ast.InterfaceType, *ast.FuncType:
			// Already a pointer, slice, map, interface, or func type; optionality is inherent or handled differently.
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
