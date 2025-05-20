package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// VisitTypeDecl handles type declarations (structs and aliases).
// type MyStruct { field: Type } or type MyAlias = AnotherType
func (v *ManuscriptAstVisitor) VisitTypeDecl(ctx *parser.TypeDeclContext) interface{} {
	name := ctx.GetTypeName()
	if name == nil || name.GetText() == "" {
		v.addError("Type declaration is missing a name.", ctx.GetStart())
		return nil
	}
	typeName := name.GetText()

	if alias := ctx.TypeAlias(); alias != nil {
		target := alias.GetAliasTarget()
		typeAnn, ok := target.(*parser.TypeAnnotationContext)
		if target == nil || !ok || typeAnn == nil {
			v.addError("Malformed or missing alias target for \""+typeName+"\".", alias.GetStart())
			return nil
		}
		expr, ok := v.VisitTypeAnnotation(typeAnn).(ast.Expr)
		if !ok || expr == nil {
			v.addError("Invalid type expression for alias target for \""+typeName+"\": "+typeAnn.GetText(), typeAnn.GetStart())
			return nil
		}
		return typeDecl(typeName, expr)
	}

	bodyCtx, ok := ctx.TypeDefBody().(*parser.TypeDefBodyContext)
	if ctx.TypeDefBody() == nil || !ok {
		v.addError("Malformed type declaration for \""+typeName+"\": missing or invalid struct body.", name.GetStart())
		return nil
	}

	fields := v.structFields(bodyCtx, typeName)
	if fields == nil {
		return nil
	}
	return typeDecl(typeName, &ast.StructType{Fields: &ast.FieldList{List: fields}})
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
		extList := body.GetExtendedTypes()
		if extList == nil || len(extList.GetTypes()) == 0 {
			v.addError("Type \""+typeName+"\" has EXTENDS clause but no base types specified.", ext.GetSymbol())
			return nil
		}
		for _, base := range extList.GetTypes() {
			typeAnn, ok := base.(*parser.TypeAnnotationContext)
			if !ok || typeAnn == nil {
				v.addError("Invalid or missing type annotation for base type for struct \""+typeName+"\"", nil)
				return nil
			}
			expr, ok := v.VisitTypeAnnotation(typeAnn).(ast.Expr)
			if !ok || expr == nil {
				v.addError("Invalid type expression for base type for struct \""+typeName+"\": "+typeAnn.GetText(), typeAnn.GetStart())
				return nil
			}
			fields = append(fields, &ast.Field{Type: expr})
		}
	}

	for _, f := range body.GetFields() {
		fd, ok := f.(*parser.FieldDeclContext)
		if !ok {
			tok := body.GetStart()
			if prc, ok := f.(antlr.ParserRuleContext); ok {
				tok = prc.GetStart()
			}
			v.addError("Internal error: Unexpected structure for field declaration in \""+typeName+"\".", tok)
			return nil
		}
		astField := v.fieldDeclToAstField(fd)
		if astField == nil {
			return nil
		}
		fields = append(fields, astField)
	}
	return fields
}

func (v *ManuscriptAstVisitor) fieldDeclToAstField(ctx *parser.FieldDeclContext) *ast.Field {
	name := ctx.GetFieldName()
	if name == nil || name.GetName() == nil {
		v.addError("Field declaration is missing a name.", ctx.GetStart())
		return nil
	}
	fieldName := name.GetName().GetText()
	typeAnn, ok := ctx.GetType_().(*parser.TypeAnnotationContext)
	if ctx.GetType_() == nil || !ok || typeAnn == nil {
		v.addError("Missing or invalid type annotation for field \""+fieldName+"\".", name.GetName())
		return nil
	}
	expr, ok := v.VisitTypeAnnotation(typeAnn).(ast.Expr)
	if !ok || expr == nil {
		v.addError("Invalid type expression for field \""+fieldName+"\": "+typeAnn.GetText(), typeAnn.GetStart())
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
// fieldDecl: fieldName = namedID (isOptionalField = QUESTION)? COLON type = typeAnnotation;
func (v *ManuscriptAstVisitor) VisitFieldDecl(ctx *parser.FieldDeclContext) interface{} {
	return v.fieldDeclToAstField(ctx)
}
