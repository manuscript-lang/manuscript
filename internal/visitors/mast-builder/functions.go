package mastb

import (
	"manuscript-lang/manuscript/internal/ast"
	"manuscript-lang/manuscript/internal/parser"
)

func (v *ParseTreeToAST) VisitInterfaceDecl(ctx *parser.InterfaceDeclContext) interface{} {
	idToken := ctx.ID().GetSymbol()
	interfaceDecl := &ast.InterfaceDecl{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPositionFromToken(idToken)},
			Name:     ctx.ID().GetText(),
		},
	}

	if typeList := v.acceptIfNotNil(ctx.TypeList()); typeList != nil {
		interfaceDecl.Extends = typeList.([]ast.TypeAnnotation)
	}

	for _, methodCtx := range ctx.AllInterfaceMethod() {
		if method := methodCtx.Accept(v); method != nil {
			interfaceDecl.Methods = append(interfaceDecl.Methods, method.(ast.InterfaceMethod))
		}
	}

	return interfaceDecl
}

func (v *ParseTreeToAST) VisitInterfaceMethod(ctx *parser.InterfaceMethodContext) interface{} {
	idToken := ctx.ID().GetSymbol()
	method := ast.InterfaceMethod{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPositionFromToken(idToken)},
			Name:     ctx.ID().GetText(),
		},
		CanThrow: ctx.EXCLAMATION() != nil,
	}

	if params := v.acceptIfNotNil(ctx.Parameters()); params != nil {
		method.Parameters = params.([]ast.Parameter)
	}

	if typeAnn := v.acceptIfNotNil(ctx.TypeAnnotation()); typeAnn != nil {
		method.ReturnType = typeAnn.(ast.TypeAnnotation)
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

	if sig := v.acceptIfNotNil(ctx.FnSignature()); sig != nil {
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

	if body := v.acceptIfNotNil(ctx.CodeBlock()); body != nil {
		fnDecl.Body = body.(*ast.CodeBlock)
	}

	return fnDecl
}

func (v *ParseTreeToAST) VisitFnSignature(ctx *parser.FnSignatureContext) interface{} {
	signature := map[string]interface{}{
		"name":     ctx.ID().GetText(),
		"canThrow": ctx.EXCLAMATION() != nil,
	}

	if params := v.acceptIfNotNil(ctx.Parameters()); params != nil {
		signature["parameters"] = params
	}

	if typeAnn := v.acceptIfNotNil(ctx.TypeAnnotation()); typeAnn != nil {
		signature["returnType"] = typeAnn
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
	// Use the ID token for more precise positioning
	idToken := ctx.ID().GetSymbol()
	param := ast.Parameter{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPositionFromToken(idToken)},
			Name:     ctx.ID().GetText(),
		},
	}

	if typeAnn := v.acceptIfNotNil(ctx.TypeAnnotation()); typeAnn != nil {
		param.Type = typeAnn.(ast.TypeAnnotation)
	}

	if expr := v.acceptIfNotNil(ctx.Expr()); expr != nil {
		param.DefaultValue = expr.(ast.Expression)
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

	if methods := v.acceptIfNotNil(ctx.MethodImplList()); methods != nil {
		methodsDecl.Methods = methods.([]ast.MethodImpl)
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

	if interfaceMethod := v.acceptIfNotNil(ctx.InterfaceMethod()); interfaceMethod != nil {
		im := interfaceMethod.(ast.InterfaceMethod)
		method.Name = im.Name
		method.Parameters = im.Parameters
		method.ReturnType = im.ReturnType
		method.CanThrow = im.CanThrow
	}

	if body := v.acceptIfNotNil(ctx.CodeBlock()); body != nil {
		method.Body = body.(*ast.CodeBlock)
	}

	return method
}
