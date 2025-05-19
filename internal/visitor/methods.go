package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitMethodsDecl(ctx *parser.MethodsDeclContext) interface{} {
	receiverName := ctx.GetReceiver().GetText()
	target := ctx.GetTarget().GetText()

	var decls []ast.Decl
	for _, methodCtx := range ctx.AllMethodImpl() {
		if mCtx, ok := methodCtx.(*parser.MethodImplContext); ok {
			method := v.VisitMethodImpl(mCtx)
			if method, ok := method.(*ast.FuncDecl); ok {
				method.Recv = &ast.FieldList{
					List: []*ast.Field{
						{
							Names: []*ast.Ident{ast.NewIdent(receiverName)},
							Type:  &ast.StarExpr{X: ast.NewIdent(target)},
						},
					},
				}
				decls = append(decls, method)
			}
		}
	}
	return decls
}

func (v *ManuscriptAstVisitor) VisitMethodImpl(ctx *parser.MethodImplContext) interface{} {
	parts, success := v.buildFunctionEssentials(
		ctx.InterfaceMethod().NamedID().GetText(),        // fnNameForError
		ctx.InterfaceMethod().NamedID().ID().GetSymbol(), // overallFnToken
		ctx.InterfaceMethod().Parameters(),               // paramsCtx
		ctx.InterfaceMethod().TypeAnnotation(),           // typeAnnotationCtx
		ctx.InterfaceMethod().EXCLAMATION(),              // exclamationNode
		ctx.CodeBlock(),                                  // codeBlockCtx
		true,                                             // allowReturnTypeInference
	)
	if !success {
		return nil
	}

	return &ast.FuncDecl{
		Name: ast.NewIdent(ctx.InterfaceMethod().NamedID().GetText()),
		Type: &ast.FuncType{
			Params:  parts.paramsAST,
			Results: parts.resultsAST,
		},
		Body: parts.bodyAST,
	}
}
