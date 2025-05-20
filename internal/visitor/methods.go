package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitMethodsDecl(ctx *parser.MethodsDeclContext) interface{} {
	if ctx == nil {
		v.addError("VisitMethodsDecl called with nil context", nil)
		return nil
	}

	receiverNode := ctx.GetReceiver()
	targetNode := ctx.GetTarget()
	if receiverNode == nil || targetNode == nil {
		v.addError("Methods declaration missing receiver or target", ctx.GetStart())
		return nil
	}

	receiver := ast.NewIdent(receiverNode.GetText())
	target := &ast.StarExpr{X: ast.NewIdent(targetNode.GetText())}
	var decls []ast.Decl

	for _, m := range ctx.AllMethodImpl() {
		methodCtx, ok := m.(*parser.MethodImplContext)
		if !ok || methodCtx == nil {
			v.addError("Invalid method implementation context in methods declaration", ctx.GetStart())
			continue
		}
		method := v.VisitMethodImpl(methodCtx)
		fn, ok := method.(*ast.FuncDecl)
		if !ok || fn == nil {
			v.addError("Method implementation did not return a valid Go function", methodCtx.GetStart())
			continue
		}
		fn.Recv = &ast.FieldList{
			List: []*ast.Field{{Names: []*ast.Ident{receiver}, Type: target}},
		}
		decls = append(decls, fn)
	}
	return decls
}

func (v *ManuscriptAstVisitor) VisitMethodImpl(ctx *parser.MethodImplContext) interface{} {
	if ctx == nil || ctx.InterfaceMethod() == nil || ctx.InterfaceMethod().NamedID() == nil {
		v.addError("VisitMethodImpl called with nil or incomplete context", nil)
		return nil
	}
	nameId := ctx.InterfaceMethod().NamedID()
	parts, ok := v.buildFunctionEssentials(
		nameId.GetText(),
		nameId.ID().GetSymbol(),
		ctx.InterfaceMethod().Parameters(),
		ctx.InterfaceMethod().TypeAnnotation(),
		ctx.InterfaceMethod().EXCLAMATION(),
		ctx.CodeBlock(),
		true,
	)
	if !ok {
		v.addError("Failed to build function essentials for method "+nameId.GetText(), nameId.ID().GetSymbol())
		return nil
	}
	return &ast.FuncDecl{
		Name: ast.NewIdent(nameId.GetText()),
		Type: &ast.FuncType{
			Params:  parts.paramsAST,
			Results: parts.resultsAST,
		},
		Body: parts.bodyAST,
	}
}
