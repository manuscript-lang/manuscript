package msparse

import (
	"manuscript-co/manuscript/internal/ast"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ParseTreeToAST) VisitInterfaceDecl(ctx *parser.InterfaceDeclContext) interface{} {
	interfaceDecl := &ast.InterfaceDecl{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}

	// Handle extends clause
	if ctx.TypeList() != nil {
		if typeList := ctx.TypeList().Accept(v); typeList != nil {
			interfaceDecl.Extends = typeList.([]ast.TypeAnnotation)
		}
	}

	// Handle methods
	for _, methodCtx := range ctx.AllInterfaceMethod() {
		if method := methodCtx.Accept(v); method != nil {
			interfaceDecl.Methods = append(interfaceDecl.Methods, method.(ast.InterfaceMethod))
		}
	}

	return interfaceDecl
}

func (v *ParseTreeToAST) VisitInterfaceMethod(ctx *parser.InterfaceMethodContext) interface{} {
	method := ast.InterfaceMethod{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
		CanThrow: ctx.EXCLAMATION() != nil,
	}

	// Handle parameters
	if ctx.Parameters() != nil {
		if params := ctx.Parameters().Accept(v); params != nil {
			method.Parameters = params.([]ast.Parameter)
		}
	}

	// Handle return type
	if ctx.TypeAnnotation() != nil {
		if typeAnn := ctx.TypeAnnotation().Accept(v); typeAnn != nil {
			method.ReturnType = typeAnn.(ast.TypeAnnotation)
		}
	}

	return method
}

// Function declarations

func (v *ParseTreeToAST) VisitFnDecl(ctx *parser.FnDeclContext) interface{} {
	fnDecl := &ast.FnDecl{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
		},
	}

	// Extract function signature
	if ctx.FnSignature() != nil {
		if sig := ctx.FnSignature().Accept(v); sig != nil {
			signature := sig.(map[string]interface{})
			fnDecl.Name = signature["name"].(string)
			if params, ok := signature["parameters"]; ok {
				fnDecl.Parameters = params.([]ast.Parameter)
			}
			if returnType, ok := signature["returnType"]; ok {
				fnDecl.ReturnType = returnType.(ast.TypeAnnotation)
			}
			if canThrow, ok := signature["canThrow"]; ok {
				fnDecl.CanThrow = canThrow.(bool)
			}
		}
	}

	// Extract body
	if ctx.CodeBlock() != nil {
		if body := ctx.CodeBlock().Accept(v); body != nil {
			fnDecl.Body = body.(*ast.CodeBlock)
		}
	}

	return fnDecl
}

func (v *ParseTreeToAST) VisitFnSignature(ctx *parser.FnSignatureContext) interface{} {
	signature := make(map[string]interface{})

	signature["name"] = ctx.ID().GetText()
	signature["canThrow"] = ctx.EXCLAMATION() != nil

	if ctx.Parameters() != nil {
		if params := ctx.Parameters().Accept(v); params != nil {
			signature["parameters"] = params
		}
	}

	if ctx.TypeAnnotation() != nil {
		if typeAnn := ctx.TypeAnnotation().Accept(v); typeAnn != nil {
			signature["returnType"] = typeAnn
		}
	}

	return signature
}

func (v *ParseTreeToAST) VisitParameters(ctx *parser.ParametersContext) interface{} {
	var params []ast.Parameter
	for _, paramCtx := range ctx.AllParam() {
		if param := paramCtx.Accept(v); param != nil {
			params = append(params, param.(ast.Parameter))
		}
	}
	return params
}

func (v *ParseTreeToAST) VisitParam(ctx *parser.ParamContext) interface{} {
	param := ast.Parameter{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}

	if ctx.TypeAnnotation() != nil {
		if typeAnn := ctx.TypeAnnotation().Accept(v); typeAnn != nil {
			param.Type = typeAnn.(ast.TypeAnnotation)
		}
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			param.DefaultValue = expr.(ast.Expression)
		}
	}

	return param
}

// Method declarations

func (v *ParseTreeToAST) VisitMethodsDecl(ctx *parser.MethodsDeclContext) interface{} {
	methodsDecl := &ast.MethodsDecl{
		BaseNode:  ast.BaseNode{Position: v.getPosition(ctx)},
		TypeName:  ctx.AllID()[0].GetText(),
		Interface: ctx.AllID()[1].GetText(),
	}

	if ctx.MethodImplList() != nil {
		if methods := ctx.MethodImplList().Accept(v); methods != nil {
			methodsDecl.Methods = methods.([]ast.MethodImpl)
		}
	}

	return methodsDecl
}

func (v *ParseTreeToAST) VisitMethodImplList(ctx *parser.MethodImplListContext) interface{} {
	var methods []ast.MethodImpl
	for _, methodCtx := range ctx.AllMethodImpl() {
		if method := methodCtx.Accept(v); method != nil {
			methods = append(methods, method.(ast.MethodImpl))
		}
	}
	return methods
}

func (v *ParseTreeToAST) VisitMethodImpl(ctx *parser.MethodImplContext) interface{} {
	method := ast.MethodImpl{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
		},
	}

	// Extract method signature from interface method
	if ctx.InterfaceMethod() != nil {
		if interfaceMethod := ctx.InterfaceMethod().Accept(v); interfaceMethod != nil {
			im := interfaceMethod.(ast.InterfaceMethod)
			method.Name = im.Name
			method.Parameters = im.Parameters
			method.ReturnType = im.ReturnType
			method.CanThrow = im.CanThrow
		}
	}

	// Extract body
	if ctx.CodeBlock() != nil {
		if body := ctx.CodeBlock().Accept(v); body != nil {
			method.Body = body.(*ast.CodeBlock)
		}
	}

	return method
}
