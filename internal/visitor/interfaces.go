package visitor

import (
	"fmt"
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitInterfaceDecl handles interface declarations.
//
//	interface MyInterface {
//	  myMethod(a: TypeA): ReturnType
//	}
func (v *ManuscriptAstVisitor) VisitInterfaceDecl(ctx *parser.InterfaceDeclContext) interface{} {
	if ctx.INTERFACE() == nil || ctx.NamedID() == nil || ctx.LBRACE() == nil || ctx.RBRACE() == nil {
		v.addError(fmt.Sprintf("Malformed interface declaration: %s", ctx.GetText()), ctx.GetStart())
		return &ast.BadDecl{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
	interfaceName := ctx.NamedID().GetText()
	methods := []*ast.Field{}

	for _, sigCtx := range ctx.AllInterfaceMethod() {
		concreteSigCtx, ok := sigCtx.(*parser.InterfaceMethodContext)
		if !ok {
			v.addError("Method signature in interface has unexpected context type.", sigCtx.GetStart())
			continue
		}
		methodField := v.VisitInterfaceMethod(concreteSigCtx)
		if field, ok := methodField.(*ast.Field); ok {
			methods = append(methods, field)
		} else {
			// Error already added by VisitInterfaceMethod or it returned nil
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

// VisitInterfaceMethod handles a method signature within an interface.
// myMethod(a: TypeA): ReturnType -> Name: myMethod, Type: func(a TypeA) ReturnType
func (v *ManuscriptAstVisitor) VisitInterfaceMethod(ctx *parser.InterfaceMethodContext) interface{} {
	if ctx.NamedID() == nil || ctx.LPAREN() == nil || ctx.RPAREN() == nil {
		v.addError(fmt.Sprintf("Malformed method signature in interface: %s", ctx.GetText()), ctx.GetStart())
		return nil
	}
	methodName := ctx.NamedID().GetText()

	paramsAST, _, paramDetails := v.ProcessParameters(ctx.Parameters())
	for _, detail := range paramDetails {
		if detail.DefaultValue != nil {
			v.addError(fmt.Sprintf("Default value for parameter '%s' not allowed in interface method signature.", detail.Name.Name), detail.NameToken)
		}
	}

	interfaceParamsList := []*ast.Field{}
	if paramsAST != nil && paramsAST.List != nil {
		for _, p := range paramsAST.List {
			interfaceParamsList = append(
				interfaceParamsList, &ast.Field{
					Type:  p.Type,
					Names: p.Names,
				},
			)
		}
	}
	finalParams := &ast.FieldList{List: interfaceParamsList}

	resultsList := v.ProcessReturnType(ctx.TypeAnnotation(), ctx.EXCLAMATION(), methodName)

	return &ast.Field{
		Names: []*ast.Ident{ast.NewIdent(methodName)},
		Type: &ast.FuncType{
			Params:  finalParams,
			Results: resultsList,
		},
	}
}
