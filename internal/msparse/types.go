package msparse

import (
	"manuscript-co/manuscript/internal/ast"
	"manuscript-co/manuscript/internal/parser"

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
		if typeList := ctx.TypeList().Accept(v); typeList != nil {
			elementTypes = typeList.([]ast.TypeAnnotation)
		}
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
		if parameters := ctx.Parameters().Accept(v); parameters != nil {
			params = parameters.([]ast.Parameter)
		}
	}

	var returnType ast.TypeAnnotation
	if ctx.TypeAnnotation() != nil {
		if retType := ctx.TypeAnnotation().Accept(v); retType != nil {
			returnType = retType.(ast.TypeAnnotation)
		}
	}

	return ast.NewFunctionType(params, returnType)
}

// TypeAnnotation visitor - was missing
func (v *ParseTreeToAST) VisitTypeAnnotation(ctx *parser.TypeAnnotationContext) interface{} {
	// The TypeAnnotation context is a base type that gets specialized into specific labeled contexts
	// We need to handle it by checking the children and delegating
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
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
		if body := ctx.TypeDefBody().Accept(v); body != nil {
			typeDecl.Body = body.(ast.TypeBody)
		}
	} else if ctx.TypeAlias() != nil {
		if alias := ctx.TypeAlias().Accept(v); alias != nil {
			typeDecl.Body = alias.(ast.TypeBody)
		}
	}

	return typeDecl
}

func (v *ParseTreeToAST) VisitTypeDefBody(ctx *parser.TypeDefBodyContext) interface{} {
	body := &ast.TypeDefBody{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	// Handle extends clause
	if ctx.TypeList() != nil {
		if typeList := ctx.TypeList().Accept(v); typeList != nil {
			body.Extends = typeList.([]ast.TypeAnnotation)
		}
	}

	// Handle field declarations
	for _, fieldCtx := range ctx.AllFieldDecl() {
		if field := fieldCtx.Accept(v); field != nil {
			body.Fields = append(body.Fields, field.(ast.FieldDecl))
		}
	}

	return body
}

func (v *ParseTreeToAST) VisitTypeAlias(ctx *parser.TypeAliasContext) interface{} {
	alias := &ast.TypeAlias{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypeAnnotation() != nil {
		if typeAnn := ctx.TypeAnnotation().Accept(v); typeAnn != nil {
			alias.Type = typeAnn.(ast.TypeAnnotation)
		}
	}

	if ctx.TypeList() != nil {
		if typeList := ctx.TypeList().Accept(v); typeList != nil {
			alias.Extends = typeList.([]ast.TypeAnnotation)
		}
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
		if typeAnn := ctx.TypeAnnotation().Accept(v); typeAnn != nil {
			field.Type = typeAnn.(ast.TypeAnnotation)
		}
	}

	return field
}

func (v *ParseTreeToAST) VisitTypeList(ctx *parser.TypeListContext) interface{} {
	var types []ast.TypeAnnotation
	for _, typeCtx := range ctx.AllTypeAnnotation() {
		if typeAnn := typeCtx.Accept(v); typeAnn != nil {
			types = append(types, typeAnn.(ast.TypeAnnotation))
		}
	}
	return types
}
