package mastb

import (
	"manuscript-lang/manuscript/internal/ast"
	"manuscript-lang/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

func (v *ParseTreeToAST) VisitLabelTypeAnnID(ctx *parser.LabelTypeAnnIDContext) interface{} {
	return ast.NewSimpleType(ctx.ID().GetText())
}

func (v *ParseTreeToAST) VisitLabelTypeAnnArray(ctx *parser.LabelTypeAnnArrayContext) interface{} {
	return ctx.ArrayType().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelTypeAnnTuple(ctx *parser.LabelTypeAnnTupleContext) interface{} {
	return ctx.TupleType().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelTypeAnnFn(ctx *parser.LabelTypeAnnFnContext) interface{} {
	return ctx.FnType().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelTypeAnnVoid(ctx *parser.LabelTypeAnnVoidContext) interface{} {
	return ast.NewVoidType()
}

func (v *ParseTreeToAST) VisitTupleType(ctx *parser.TupleTypeContext) interface{} {
	var elementTypes []ast.TypeAnnotation
	if ctx.TypeList() != nil {
		elementTypes = ctx.TypeList().Accept(v).([]ast.TypeAnnotation)
	}
	return ast.NewTupleType(elementTypes)
}

func (v *ParseTreeToAST) VisitArrayType(ctx *parser.ArrayTypeContext) interface{} {
	baseType := ast.NewSimpleType(ctx.ID().GetText())
	return ast.NewArrayType(baseType)
}

func (v *ParseTreeToAST) VisitFnType(ctx *parser.FnTypeContext) interface{} {
	var params []ast.Parameter
	if ctx.Parameters() != nil {
		params = ctx.Parameters().Accept(v).([]ast.Parameter)
	}

	var returnType ast.TypeAnnotation
	if ctx.TypeAnnotation() != nil {
		returnType = ctx.TypeAnnotation().Accept(v).(ast.TypeAnnotation)
	}

	return ast.NewFunctionType(params, returnType)
}

func (v *ParseTreeToAST) VisitTypeAnnotation(ctx *parser.TypeAnnotationContext) interface{} {
	for _, child := range ctx.GetChildren() {
		if ruleCtx, ok := child.(antlr.RuleContext); ok {
			return ruleCtx.Accept(v)
		}
	}
	return nil
}

func (v *ParseTreeToAST) VisitTypeDecl(ctx *parser.TypeDeclContext) interface{} {
	typeDecl := &ast.TypeDecl{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}

	if ctx.TypeDefBody() != nil {
		typeDecl.Body = ctx.TypeDefBody().Accept(v).(ast.TypeBody)
	} else if ctx.TypeAlias() != nil {
		typeDecl.Body = ctx.TypeAlias().Accept(v).(ast.TypeBody)
	}

	return typeDecl
}

func (v *ParseTreeToAST) VisitTypeDefBody(ctx *parser.TypeDefBodyContext) interface{} {
	body := &ast.TypeDefBody{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypeList() != nil {
		body.Extends = ctx.TypeList().Accept(v).([]ast.TypeAnnotation)
	}

	for _, fieldCtx := range ctx.AllFieldDecl() {
		body.Fields = append(body.Fields, fieldCtx.Accept(v).(ast.FieldDecl))
	}

	return body
}

func (v *ParseTreeToAST) VisitTypeAlias(ctx *parser.TypeAliasContext) interface{} {
	alias := &ast.TypeAlias{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypeAnnotation() != nil {
		alias.Type = ctx.TypeAnnotation().Accept(v).(ast.TypeAnnotation)
	}

	if ctx.TypeList() != nil {
		alias.Extends = ctx.TypeList().Accept(v).([]ast.TypeAnnotation)
	}

	return alias
}

func (v *ParseTreeToAST) VisitFieldDecl(ctx *parser.FieldDeclContext) interface{} {
	field := ast.FieldDecl{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
		Optional: ctx.QUESTION() != nil,
	}

	if ctx.TypeAnnotation() != nil {
		field.Type = ctx.TypeAnnotation().Accept(v).(ast.TypeAnnotation)
	}

	return field
}

func (v *ParseTreeToAST) VisitTypeList(ctx *parser.TypeListContext) interface{} {
	var types []ast.TypeAnnotation
	for _, typeCtx := range ctx.AllTypeAnnotation() {
		types = append(types, typeCtx.Accept(v).(ast.TypeAnnotation))
	}
	return types
}
