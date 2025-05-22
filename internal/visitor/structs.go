package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"reflect"

	"github.com/antlr4-go/antlr/v4"
)

// VisitTypeDecl handles type declarations (structs and aliases).
// type MyStruct { field: Type } or type MyAlias = AnotherType
func (v *ManuscriptAstVisitor) VisitTypeDecl(ctx *parser.TypeDeclContext) interface{} {
	name := ctx.ID()
	if name == nil || name.GetText() == "" {
		v.addError("Type declaration is missing a name.", ctx.GetStart())
		return nil
	}
	typeNameStr := name.GetText()

	// Check for type alias vs. struct definition
	if typeAliasCtx := ctx.TypeAlias(); typeAliasCtx != nil {
		// This is a type alias: type Name = AliasType
		aliasTargetNode := typeAliasCtx.TypeAnnotation()
		if aliasTargetNode == nil {
			// Should not happen if grammar is `typeAlias: EQUALS aliasTarget=typeAnnotation`
			v.addError("Malformed type alias for \""+typeNameStr+"\": missing alias target.", typeAliasCtx.GetStart())
			return nil
		}

		aliasTypeExpr, ok := v.processTypeAnnotationToExpr(aliasTargetNode, "alias target for \""+typeNameStr+"\"")
		if !ok {
			return nil // Error already added by helper
		}

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
	}

	body := ctx.TypeDefBody()
	bodyCtx, ok := body.(*parser.TypeDefBodyContext)
	if !ok || bodyCtx == nil {
		v.addError("Malformed type declaration for \""+typeNameStr+"\": missing or invalid struct body.", name.GetSymbol())
		return nil
	}

	fields := v.structFields(bodyCtx, typeNameStr)
	if fields == nil {
		return nil
	}
	return typeDecl(typeNameStr, &ast.StructType{Fields: &ast.FieldList{List: fields}})
}

// processTypeAnnotationToExpr is a helper function to process type annotations to Go AST expressions
func (v *ManuscriptAstVisitor) processTypeAnnotationToExpr(typeAnnCtx parser.ITypeAnnotationContext, contextDescription string) (ast.Expr, bool) {
	if typeAnnCtx == nil {
		// This should ideally be caught by the caller before passing nil.
		// Providing a generic token or nil if no specific token is available.
		v.addError("Internal error: nil TypeAnnotation provided for "+contextDescription, nil)
		return nil, false
	}

	// Accept any context that implements Accept(antlr.ParseTreeVisitor)
	if visitable, ok := typeAnnCtx.(interface {
		Accept(antlr.ParseTreeVisitor) interface{}
	}); ok {
		visitedNode := visitable.Accept(v)
		if expr, isExpr := visitedNode.(ast.Expr); isExpr && expr != nil {
			return expr, true
		} else {
			v.addError("Invalid type expression for "+contextDescription, typeAnnCtx.GetStart())
			return nil, false
		}
	}

	// Fallback: error
	v.addError("Internal error: unexpected type for TypeAnnotation ("+reflect.TypeOf(typeAnnCtx).String()+") for "+contextDescription, typeAnnCtx.GetStart())
	return nil, false
}

func typeDecl(name string, typ ast.Expr) *ast.GenDecl {
	return &ast.GenDecl{
		Tok: token.TYPE,
		Specs: []ast.Spec{
			&ast.TypeSpec{
				Name: ast.NewIdent(name),
				Type: typ,
			},
		},
	}
}

func (v *ManuscriptAstVisitor) structFields(body *parser.TypeDefBodyContext, typeName string) []*ast.Field {
	var fields []*ast.Field

	if ext := body.EXTENDS(); ext != nil {
		typeList := body.TypeList()
		if typeList == nil || len(typeList.AllTypeAnnotation()) == 0 {
			v.addError("Type \""+typeName+"\" has EXTENDS clause but no base types specified.", ext.GetSymbol())
			return nil
		}
		for _, base := range typeList.AllTypeAnnotation() {
			baseCtx, ok := base.(*parser.TypeAnnotationContext)
			if !ok || baseCtx == nil {
				v.addError("Invalid type annotation for base type for struct \""+typeName+"\".", nil)
				return nil
			}
			expr, ok := v.VisitTypeAnnotation(baseCtx).(ast.Expr)
			if !ok || expr == nil {
				v.addError("Invalid type expression for base type for struct \""+typeName+"\": "+baseCtx.GetText(), baseCtx.GetStart())
				return nil
			}
			fields = append(fields, &ast.Field{Type: expr})
		}
	}

	allFieldDeclCtxs := body.AllFieldDecl()
	if len(allFieldDeclCtxs) > 0 {
		for _, f_inter := range allFieldDeclCtxs {
			fdCtx, ok := f_inter.(*parser.FieldDeclContext)
			if !ok || fdCtx == nil {
				v.addError("Internal error: Unexpected structure for field declaration in \""+typeName+"\".", f_inter.GetStart())
				return nil // critical error
			}
			astField := v.fieldDeclToAstField(fdCtx)
			if astField == nil {
				return nil // error in fieldDeclToAstField
			}
			fields = append(fields, astField)
		}
	}
	return fields
}

func (v *ManuscriptAstVisitor) fieldDeclToAstField(ctx *parser.FieldDeclContext) *ast.Field {
	name := ctx.ID()
	if name == nil {
		v.addError("Field declaration is missing a name.", ctx.GetStart())
		return nil
	}
	fieldName := name.GetText()
	fieldTypeAnn := ctx.TypeAnnotation()
	if fieldTypeAnn == nil {
		v.addError("Missing type annotation for field \""+fieldName+"\".", name.GetSymbol())
		return nil
	}

	// Use processTypeAnnotationToExpr for all type annotation forms
	var expr ast.Expr
	expr, ok := v.processTypeAnnotationToExpr(fieldTypeAnn, "field \""+fieldName+"\"")
	if !ok {
		return nil
	}

	if ctx.QUESTION() != nil {
		switch expr.(type) {
		case *ast.Ident, *ast.SelectorExpr:
			expr = &ast.StarExpr{X: expr}
		}
	}
	return &ast.Field{
		Names: []*ast.Ident{ast.NewIdent(fieldName)},
		Type:  expr,
	}
}

// VisitFieldDecl handles field declarations within a type (struct).
// fieldDecl: ID (QUESTION)? typeAnnotation;
func (v *ManuscriptAstVisitor) VisitFieldDecl(ctx *parser.FieldDeclContext) interface{} {
	return v.fieldDeclToAstField(ctx)
}
