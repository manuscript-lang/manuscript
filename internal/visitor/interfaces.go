package visitor

import (
	"fmt"
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

//	interface MyInterface {
//	  myMethod(a: TypeA): ReturnType
//	}
func (v *ManuscriptAstVisitor) VisitInterfaceDecl(ctx *parser.InterfaceDeclContext) interface{} {
	if ctx.INTERFACE() == nil || ctx.ID() == nil || ctx.LBRACE() == nil || ctx.RBRACE() == nil {
		v.addError(fmt.Sprintf("Malformed interface declaration: %s", ctx.GetText()), ctx.GetStart())
		return &ast.BadDecl{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
	interfaceName := ctx.ID().GetText()
	methods := []*ast.Field{}

	if stmtList := ctx.Stmt_list(); stmtList != nil {
		for _, stmtCtx := range stmtList.AllStmt() {
			methodField := v.Visit(stmtCtx)
			if field, ok := methodField.(*ast.Field); ok {
				methods = append(methods, field)
			}
		}
	}

	// TODO: Handle extends ctx.ExtendedInterfaces() which is ITypeListContext
	if ctx.EXTENDS() != nil && ctx.TypeList() != nil {
		v.addError(fmt.Sprintf("Interface extension (extends) for '%s' is not yet fully implemented.", interfaceName), ctx.EXTENDS().GetSymbol())
	}

	return &ast.TypeSpec{
		Name: ast.NewIdent(interfaceName),
		Type: &ast.InterfaceType{
			Methods: &ast.FieldList{List: methods},
		},
	}
}

// myMethod(a: TypeA): ReturnType -> Name: myMethod, Type: func(a TypeA) ReturnType
func (v *ManuscriptAstVisitor) VisitInterfaceMethod(ctx *parser.InterfaceMethodContext) interface{} {
	if ctx == nil {
		v.addError("VisitInterfaceMethod called with nil context", nil)
		return nil
	}
	if ctx.ID() == nil || ctx.LPAREN() == nil || ctx.RPAREN() == nil {
		v.addError(fmt.Sprintf("Malformed method signature in interface: %s", ctx.GetText()), ctx.GetStart())
		return nil
	}
	methodName := ctx.ID().GetText()

	var paramDetails []ParamDetail
	paramsAST := &ast.FieldList{List: []*ast.Field{}} // Default to empty

	if pCtx := ctx.Parameters(); pCtx != nil {
		paramDetailsRaw := v.Visit(pCtx)
		if details, ok := paramDetailsRaw.([]ParamDetail); ok {
			paramDetails = details
			tmpParamsAST, err := v.buildParamsAST(paramDetails) // Consider error handling for buildParamsAST
			if err == nil && tmpParamsAST != nil {
				paramsAST = tmpParamsAST
			}
			// If err != nil, paramsAST remains the default empty list
		}
		// If paramDetailsRaw was not []ParamDetail (e.g., ast.BadStmt), paramsAST also remains default.
	}

	// Fix: If no return type annotation, treat as void (empty results list)
	var resultsList *ast.FieldList
	if ctx.TypeAnnotation() != nil {
		resultsList = v.ProcessReturnType(ctx.TypeAnnotation(), nil, methodName)
	} else {
		resultsList = &ast.FieldList{List: []*ast.Field{}}
	}

	return &ast.Field{
		Names: []*ast.Ident{ast.NewIdent(methodName)},
		Type: &ast.FuncType{
			Params:  paramsAST,
			Results: resultsList,
		},
	}
}
