package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strings"
)

// generateReceiverName creates a conventional Go receiver name (e.g., "m" for "MyType").
func generateReceiverName(typeName string) string {
	if typeName == "" {
		return "r" // Default receiver name
	}
	// Consider if typeName could be a pointer like "*MyType"
	// For now, assume it's a simple identifier.
	return strings.ToLower(string(typeName[0]))
}

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

	for _, sigCtx := range ctx.AllFnSignature() {
		concreteSigCtx, ok := sigCtx.(*parser.FnSignatureContext)
		if !ok {
			v.addError("Method signature in interface has unexpected context type.", sigCtx.GetStart())
			continue
		}
		methodField := v.VisitInterfaceMethodDecl(concreteSigCtx)
		if field, ok := methodField.(*ast.Field); ok {
			methods = append(methods, field)
		} else {
			// Error already added by VisitInterfaceMethodDecl or it returned nil
		}
	}

	// TODO: Handle extends ctx.ExtendedInterfaces() which is ITypeListContext
	if ctx.EXTENDS() != nil && ctx.TypeList() != nil {
		v.addError(fmt.Sprintf("Interface extension (extends) for '%s' is not yet fully implemented.", interfaceName), ctx.EXTENDS().GetSymbol())
	}

	return &ast.GenDecl{
		Tok: token.INTERFACE,
		Specs: []ast.Spec{
			&ast.TypeSpec{
				Name: ast.NewIdent(interfaceName),
				Type: &ast.InterfaceType{
					Methods: &ast.FieldList{List: methods},
				},
			},
		},
	}
}

// VisitInterfaceMethodDecl handles a method signature within an interface.
// myMethod(a: TypeA): ReturnType -> Name: myMethod, Type: func(a TypeA) ReturnType
func (v *ManuscriptAstVisitor) VisitInterfaceMethodDecl(ctx *parser.FnSignatureContext) interface{} {
	if ctx.NamedID() == nil || ctx.LPAREN() == nil || ctx.RPAREN() == nil {
		v.addError(fmt.Sprintf("Malformed method signature in interface: %s", ctx.GetText()), ctx.GetStart())
		return nil // Indicate error to caller
	}
	methodName := ctx.NamedID().GetText()

	// Use ProcessParameters for parameters
	paramsAST, _, paramDetails := v.ProcessParameters(ctx.Parameters()) // Renamed
	if paramDetails != nil {                                            // Check if paramDetails were actually returned
		for _, detail := range paramDetails {
			if detail.DefaultValue != nil {
				v.addError(fmt.Sprintf("Default value for parameter '%s' not allowed in interface method signature.", detail.Name.Name), detail.NameToken)
			}
		}
	}

	// Interface methods in Go AST don't have parameter names, only types.
	// Need to strip names from paramsAST if ProcessParameters includes them.
	// For now, assuming ProcessParameters returns FieldList suitable for signatures or can be adapted.
	// A quick fix for interface params:
	interfaceParamsList := []*ast.Field{}
	if paramsAST != nil {
		for _, p := range paramsAST.List {
			interfaceParamsList = append(interfaceParamsList, &ast.Field{Type: p.Type})
		}
	}
	finalParams := &ast.FieldList{List: interfaceParamsList}

	// Use ProcessReturnType for results
	resultsList := v.ProcessReturnType(ctx.TypeAnnotation(), ctx.EXCLAMATION(), methodName) // Renamed

	return &ast.Field{
		Names: []*ast.Ident{ast.NewIdent(methodName)},
		Type: &ast.FuncType{
			Params:  finalParams, // Use modified params
			Results: resultsList,
		},
	}
}

// VisitMethodsDecl handles a 'methods for MyType (implements MyInterface)' block.
// methods MyInterface for MyType { ... } or methods for MyType { ... }
func (v *ManuscriptAstVisitor) VisitMethodsDecl(ctx *parser.MethodsDeclContext) interface{} {
	if ctx.METHODS() == nil || ctx.ID() == nil || ctx.LBRACE() == nil || ctx.RBRACE() == nil {
		v.addError(fmt.Sprintf("Malformed methods declaration: %s", ctx.GetText()), ctx.GetStart())
		return &ast.BadDecl{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
	receiverTypeName := ctx.ID().GetText()
	receiverName := generateReceiverName(receiverTypeName)

	// Optional: 'implements InterfaceName' part
	if ctx.FOR() != nil && ctx.TypeAnnotation() != nil {
		v.addError(fmt.Sprintf("Processing of 'implements %s' for methods on '%s' is not fully handled yet.", ctx.TypeAnnotation().GetText(), receiverTypeName), ctx.FOR().GetSymbol())
	}

	decls := []ast.Decl{}
	for _, implCtx := range ctx.AllFnDecl() { // Corrected: Use AllFnDecl based on grammar `impls += fnDecl`
		// implCtx is of type parser.IFnDeclContext
		methodDecl := v.VisitMethodImpl(implCtx, receiverName, receiverTypeName)
		if decl, ok := methodDecl.(ast.Decl); ok {
			decls = append(decls, decl)
		} else if methodDecl != nil {
			// VisitMethodImpl is expected to return nil on error and log its own detailed error.
			// If methodDecl is non-nil and not an ast.Decl, it's an unexpected state.
			v.addError(fmt.Sprintf("Processing method implementation for struct '%s' yielded an unexpected result.", receiverTypeName), implCtx.GetStart())
		}
	}

	if len(decls) == 0 && ctx.FOR() != nil { // If it was 'methods SomeInterface for SomeType {}' with no actual methods
		// This might be valid if it's just asserting an interface implementation without adding new methods
		// or if it's an empty methods block. For now, we just produce no Go code.
	}
	return decls // Return a slice of ast.Decl (specifically *ast.FuncDecl)
}

// VisitMethodImpl handles a single method implementation within a 'methods' block.
// It receives an FnSignatureContext because the parser (currently) only provides that for method impls.
// This means it CANNOT GENERATE A BODY correctly. It will produce a func decl without a body.
func (v *ManuscriptAstVisitor) VisitMethodImpl(implCtx parser.IFnDeclContext, receiverName string, receiverTypeName string) interface{} {
	if implCtx == nil {
		v.addError("Received nil method implementation context.", nil) // Position unknown if implCtx is nil
		return nil
	}

	signatureCtxNode := implCtx.GetSignature() // Corrected: Use GetSignature()
	if signatureCtxNode == nil {
		v.addError("Method implementation is missing a signature.", implCtx.GetStart())
		return nil
	}
	concreteSigCtx, ok := signatureCtxNode.(*parser.FnSignatureContext)
	if !ok {
		v.addError("Method signature in implementation has unexpected context type.", signatureCtxNode.GetStart())
		return nil
	}

	if concreteSigCtx.NamedID() == nil || concreteSigCtx.LPAREN() == nil || concreteSigCtx.RPAREN() == nil {
		v.addError(fmt.Sprintf("Malformed method implementation signature: %s", concreteSigCtx.GetText()), concreteSigCtx.GetStart())
		return nil
	}
	fnName := concreteSigCtx.NamedID().GetText()

	paramsList, defaultAssignments, _ := v.ProcessParameters(concreteSigCtx.Parameters())
	resultsList := v.ProcessReturnType(concreteSigCtx.TypeAnnotation(), concreteSigCtx.EXCLAMATION(), fnName)

	receiverField := &ast.Field{
		Names: []*ast.Ident{ast.NewIdent(receiverName)},
		Type:  ast.NewIdent(receiverTypeName), // Should this be a pointer type, e.g., *ast.StarExpr? Depends on convention.
	}

	// Process the method body
	bodyAntlrNode := implCtx.GetBlock() // Corrected: Use GetBlock()
	var funcBody *ast.BlockStmt

	if bodyAntlrNode == nil {
		// Grammar: fnDecl: signature = fnSignature block = codeBlock; block is mandatory.
		v.addError(fmt.Sprintf("Method '%s' implementation is missing the required body block in parser tree.", fnName), concreteSigCtx.GetStop()) // Position at end of signature
		return nil
	}

	concreteBodyAntlrNode, ok := bodyAntlrNode.(*parser.CodeBlockContext)
	if !ok {
		v.addError(fmt.Sprintf("Method '%s' has an unexpected body context type. Expected CodeBlockContext.", fnName), bodyAntlrNode.GetStart())
		// Create a minimal error body to allow parsing to continue if possible
		funcBody = &ast.BlockStmt{
			Lbrace: v.pos(bodyAntlrNode.GetStart()),
			Rbrace: v.pos(bodyAntlrNode.GetStop()),
			List:   defaultAssignments, // At least include default param assignments
		}
	} else {
		// Assuming v.VisitCodeBlock(ctx *parser.CodeBlockContext) interface{} returns *ast.BlockStmt or nil
		visitedBodyResult := v.VisitCodeBlock(concreteBodyAntlrNode)

		if visitedBodyResult == nil {
			// VisitCodeBlock should have added an error.
			// Create a minimal body to allow further processing.
			// Error already logged by VisitCodeBlock hopefully.
			funcBody = &ast.BlockStmt{
				Lbrace: v.pos(concreteBodyAntlrNode.GetStart()),
				Rbrace: v.pos(concreteBodyAntlrNode.GetStop()),
				List:   defaultAssignments,
			}
		} else if bs, ok := visitedBodyResult.(*ast.BlockStmt); ok {
			funcBody = bs
			// Prepend defaultAssignments to the actual body statements
			if funcBody.List == nil { // Ensure list is initialized
				funcBody.List = []ast.Stmt{}
			}
			funcBody.List = append(defaultAssignments, funcBody.List...)
		} else {
			v.addError(fmt.Sprintf("VisitCodeBlock for method '%s' returned an unexpected type (%T). Expected *ast.BlockStmt.", fnName, visitedBodyResult), concreteBodyAntlrNode.GetStart())
			funcBody = &ast.BlockStmt{ // Fallback
				Lbrace: v.pos(concreteBodyAntlrNode.GetStart()),
				Rbrace: v.pos(concreteBodyAntlrNode.GetStop()),
				List:   defaultAssignments,
			}
		}
	}

	return &ast.FuncDecl{
		Recv: &ast.FieldList{List: []*ast.Field{receiverField}},
		Name: ast.NewIdent(fnName),
		Type: &ast.FuncType{
			Params:  paramsList,
			Results: resultsList,
		},
		Body: funcBody,
	}
}
