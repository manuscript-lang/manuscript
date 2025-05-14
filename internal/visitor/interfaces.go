package visitor

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// VisitIfaceDecl handles interface declarations.
// ifaceDecl: IFACE name=ID (EXTENDS baseIface+=typeAnnotation (COMMA baseIface+=typeAnnotation)*)? LBRACE (methodDecl SEMICOLON?)* RBRACE;
func (v *ManuscriptAstVisitor) VisitIfaceDecl(ctx *parser.IfaceDeclContext) interface{} {
	ifaceName := ctx.ID().GetText()
	log.Printf("VisitIfaceDecl: Called for '%s'", ifaceName)

	methods := make([]*ast.Field, 0)

	// Handle extends (embedding other interfaces)
	if ctx.EXTENDS() != nil && len(ctx.GetBaseIfaces()) > 0 {
		log.Printf("VisitIfaceDecl: Processing EXTENDS clause for '%s'", ifaceName)
		for _, baseIfaceAntlrCtx := range ctx.GetBaseIfaces() {
			if concreteBaseIfaceCtx, ok := baseIfaceAntlrCtx.(*parser.TypeAnnotationContext); ok {
				visitedBaseType := v.VisitTypeAnnotation(concreteBaseIfaceCtx) // Use VisitTypeAnnotation
				if baseTypeExpr, isExpr := visitedBaseType.(ast.Expr); isExpr && baseTypeExpr != nil {
					// For embedding, Go just lists the embedded interface as a field with no name
					methods = append(methods, &ast.Field{Type: baseTypeExpr})
					log.Printf("VisitIfaceDecl: Added base interface %s to '%s'", concreteBaseIfaceCtx.GetText(), ifaceName)
				} else {
					v.addError("Base interface \""+concreteBaseIfaceCtx.GetText()+"\" for interface \""+ifaceName+"\" is invalid or void.", concreteBaseIfaceCtx.GetStart())
					return nil // Error processing a base interface
				}
			} else {
				token := ctx.ID().GetSymbol() // Fallback token
				if pt, okPt := baseIfaceAntlrCtx.(antlr.ParserRuleContext); okPt {
					token = pt.GetStart()
				}
				v.addError("Internal error: Unexpected structure for base interface of \""+ifaceName+"\".", token)
				return nil
			}
		}
	}

	// Add declared methods
	for _, methodDeclCtx := range ctx.AllMethodDecl() {
		if concreteMethodDeclCtx, ok := methodDeclCtx.(*parser.MethodDeclContext); ok {
			methodField := v.VisitMethodDecl(concreteMethodDeclCtx)
			if field, okM := methodField.(*ast.Field); okM && field != nil {
				methods = append(methods, field)
			} else {
				// Error already added by VisitMethodDecl if it returned nil.
				// If it returned something else, that's an internal error.
				if methodField != nil {
					v.addError("Internal error: Method declaration processing for interface \""+ifaceName+"\" returned unexpected type.", concreteMethodDeclCtx.GetStart())
				}
				// Skip this method rather than failing the whole interface
			}
		} else {
			token := ctx.ID().GetSymbol() // Fallback token
			if pt, okPt := methodDeclCtx.(antlr.ParserRuleContext); okPt {
				token = pt.GetStart()
			}
			v.addError("Internal error: Unexpected structure for method declaration in interface \""+ifaceName+"\".", token)
			// Skip this method rather than failing the whole interface
		}
	}

	// Create the interface type spec
	return &ast.GenDecl{
		Tok: token.TYPE,
		Specs: []ast.Spec{
			&ast.TypeSpec{
				Name: ast.NewIdent(ifaceName),
				Type: &ast.InterfaceType{
					Methods: &ast.FieldList{List: methods},
				},
			},
		},
	}
}

// VisitMethodDecl handles method signatures within an interface.
// methodDecl: name=ID LPAREN parameters? RPAREN (COLON returnType=typeAnnotation)? EXCLAMATION?;
func (v *ManuscriptAstVisitor) VisitMethodDecl(ctx *parser.MethodDeclContext) interface{} {
	methodName := ctx.ID().GetText()
	log.Printf("VisitMethodDecl: Called for '%s'", methodName)

	// Parameters
	var params *ast.FieldList
	if pCtx := ctx.Parameters(); pCtx != nil {
		paramsInterface := v.VisitParameters(pCtx.(*parser.ParametersContext))
		if pl, ok := paramsInterface.(*ast.FieldList); ok {
			params = pl
		} else {
			v.addError("Internal error: Parameter processing for method \""+methodName+"\" returned unexpected type.", pCtx.GetStart())
			return nil
		}
	} else {
		params = &ast.FieldList{List: []*ast.Field{}} // No parameters
	}

	// Return Type
	var results *ast.FieldList
	if rtCtx := ctx.TypeAnnotation(); rtCtx != nil {
		returnTypeInterface := v.VisitTypeAnnotation(rtCtx.(*parser.TypeAnnotationContext))
		if returnTypeExpr, ok := returnTypeInterface.(ast.Expr); ok {
			field := &ast.Field{Type: returnTypeExpr}
			results = &ast.FieldList{List: []*ast.Field{field}}
		} else {
			v.addError("Invalid return type for method \""+methodName+"\".", rtCtx.GetStart())
			// Allow methods with no explicit return type (void)
			results = nil
		}
	}

	// Handle error indicator '!'
	if ctx.EXCLAMATION() != nil {
		// Add error type to results
		errorType := ast.NewIdent("error") // Standard Go error type
		errorField := &ast.Field{Type: errorType}
		if results == nil {
			results = &ast.FieldList{List: []*ast.Field{errorField}}
		} else {
			results.List = append(results.List, errorField)
		}
	}

	// Create field with function type (method signature)
	return &ast.Field{
		Names: []*ast.Ident{ast.NewIdent(methodName)},
		Type: &ast.FuncType{
			Params:  params,
			Results: results,
		},
	}
}

// VisitMethodBlockDecl handles method implementation blocks.
// methodBlockDecl: METHODS typeName=ID (FOR ifaceName=ID)? LBRACE (methodImpl SEMICOLON?)* RBRACE
func (v *ManuscriptAstVisitor) VisitMethodBlockDecl(ctx *parser.MethodBlockDeclContext) interface{} {
	typeNameNode := ctx.GetTypeName()
	if typeNameNode == nil {
		v.addError("Method block missing target type name.", ctx.LBRACE().GetSymbol()) // Token for LBRACE as anchor
		return nil
	}
	typeName := typeNameNode.GetText()
	var implForIface string
	ifaceNameNode := ctx.GetIfaceName()
	if ifaceNameNode != nil {
		implForIface = ifaceNameNode.GetText()
	}

	if implForIface != "" {
		log.Printf("VisitMethodBlockDecl: Called for '%s' implementing '%s'", typeName, implForIface)
	} else {
		log.Printf("VisitMethodBlockDecl: Called for '%s'", typeName)
	}

	// Collect all method implementations
	var methods []ast.Decl
	for _, methodImplCtxAnltr := range ctx.AllMethodImpl() {
		if concreteMethodImplCtx, ok := methodImplCtxAnltr.(*parser.MethodImplContext); ok {
			methodDecl := concreteMethodImplCtx.Accept(v) // Relies on Accept dispatching to the corrected VisitMethodImpl
			if funcDecl, okF := methodDecl.(*ast.FuncDecl); okF && funcDecl != nil {
				methods = append(methods, funcDecl)
			} else {
				// Error would be added by VisitMethodImpl if it returned nil.
				if methodDecl != nil {
					v.addError("Internal error: Method implementation processing for type \""+typeName+"\" returned unexpected type.", concreteMethodImplCtx.GetStart())
				}
				// Skip this method rather than failing the whole block
			}
		} else {
			token := typeNameNode.(antlr.ParserRuleContext).GetStart() // typeNameNode is ITypeAnnotationContext, assert to ParserRuleContext
			if pt, okPt := methodImplCtxAnltr.(antlr.ParserRuleContext); okPt {
				token = pt.GetStart()
			}
			v.addError("Internal error: Unexpected structure for method implementation in block for \""+typeName+"\".", token)
			// Skip this method rather than failing the whole block
		}
	}

	// Return a slice of function declarations (Go doesn't have a direct equivalent to method blocks)
	return methods
}

// VisitMethodImpl handles individual method implementations.
// methodImpl: name=ID LPAREN parameters? RPAREN (COLON returnType=typeAnnotation)? EXCLAMATION? codeBlock
func (v *ManuscriptAstVisitor) VisitMethodImpl(ctx *parser.MethodImplContext) interface{} { // New signature
	methodName := ctx.ID().GetText()

	// Derive receiverTypeName from parent MethodBlockDeclContext
	parentCtx := ctx.GetParent()
	mbCtx, ok := parentCtx.(*parser.MethodBlockDeclContext)
	if !ok {
		v.addError("Internal error: Method \""+methodName+"\" not within a method block.", ctx.ID().GetSymbol())
		return nil
	}
	if mbCtx.GetTypeName() == nil { // Check if GetTypeName() itself is nil before calling GetText()
		v.addError("Internal error: Method block for \""+methodName+"\" is missing its type name.", ctx.ID().GetSymbol())
		return nil
	}
	receiverTypeName := mbCtx.GetTypeName().GetText()
	if receiverTypeName == "" {
		v.addError("Internal error: Receiver type name for method \""+methodName+"\" is empty.", ctx.ID().GetSymbol())
		return nil
	}

	log.Printf("VisitMethodImpl: Called for '%s.%s'", receiverTypeName, methodName)

	// Create receiver parameter (e.g., "r *ReceiverType")
	// Usually receiver parameter is a single letter or a short name
	receiverName := ""
	if len(receiverTypeName) > 0 {
		receiverName = string(receiverTypeName[0]) // First letter of the type name, ensure not empty
	} else {
		// This case should ideally be caught by receiverTypeName == "" check above, but as a safeguard:
		log.Printf("VisitMethodImpl: Warning: receiverTypeName is empty, cannot generate receiver name for method %s", methodName)
		// Decide on a default or error out. For now, let's use a default to avoid panic.
		receiverName = "r"
	}

	goReceiverType := ast.NewIdent(receiverTypeName) // Use Go's ast.NewIdent for the type
	// By default we use a pointer receiver for methods that modify state
	// This could be a configuration option or determined by method semantics
	receiver := &ast.FieldList{List: []*ast.Field{
		{
			Names: []*ast.Ident{ast.NewIdent(receiverName)},
			Type:  &ast.StarExpr{X: goReceiverType},
		},
	}}

	// Parameters
	var params *ast.FieldList
	if pCtx := ctx.Parameters(); pCtx != nil { // Use specific getter
		paramsInterface := v.VisitParameters(pCtx.(*parser.ParametersContext))
		if pl, okP := paramsInterface.(*ast.FieldList); okP {
			params = pl
		} else {
			v.addError("Internal error: Parameter processing for method \""+methodName+"\" (type \""+receiverTypeName+"\") returned unexpected type.", pCtx.GetStart())
			return nil
		}
	} else {
		params = &ast.FieldList{List: []*ast.Field{}} // No parameters
	}

	// Return Type
	var results *ast.FieldList
	if rtCtx := ctx.TypeAnnotation(); rtCtx != nil { // Use specific getter
		returnTypeInterface := v.VisitTypeAnnotation(rtCtx.(*parser.TypeAnnotationContext))
		if returnTypeExpr, okRt := returnTypeInterface.(ast.Expr); okRt {
			field := &ast.Field{Type: returnTypeExpr}
			results = &ast.FieldList{List: []*ast.Field{field}}
		} else {
			v.addError("Invalid return type for method \""+methodName+"\" (type \""+receiverTypeName+"\").", rtCtx.GetStart())
			// Allow methods with no explicit return type (void)
			results = nil
		}
	}

	// Handle error indicator '!'
	if ctx.EXCLAMATION() != nil {
		// Add error type to results
		errorType := ast.NewIdent("error") // Standard Go error type
		errorField := &ast.Field{Type: errorType}
		if results == nil {
			results = &ast.FieldList{List: []*ast.Field{errorField}}
		} else {
			results.List = append(results.List, errorField)
		}
	}

	// Function Body
	var body *ast.BlockStmt
	if cbCtx := ctx.CodeBlock(); cbCtx != nil { // Use specific getter
		bodyInterface := v.VisitCodeBlock(cbCtx.(*parser.CodeBlockContext))
		if b, okB := bodyInterface.(*ast.BlockStmt); okB {
			body = b
		} else {
			log.Printf("VisitMethodImpl: Expected *ast.BlockStmt for body, got %T", bodyInterface)
			return nil // Method must have a body
		}
	} else {
		log.Printf("VisitMethodImpl: No code block found for method '%s.%s'", receiverTypeName, methodName)
		return nil // Method must have a body
	}

	return &ast.FuncDecl{
		Recv: receiver,
		Name: ast.NewIdent(methodName),
		Type: &ast.FuncType{
			Params:  params,
			Results: results,
		},
		Body: body,
	}
}
