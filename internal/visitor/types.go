package visitor

import (
	"fmt"
	"go/ast"
	"log"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// VisitTypeAnnotation handles type annotations, including modifiers for array, map, and set.
// It should return an ast.Expr representing the Go type.
func (v *ManuscriptAstVisitor) VisitTypeAnnotation(ctx *parser.TypeAnnotationContext) interface{} {
	log.Printf("VisitTypeAnnotation: Called for '%s'", ctx.GetText())

	children := ctx.GetChildren()
	if len(children) == 0 {
		log.Printf("VisitTypeAnnotation: No children found for '%s'", ctx.GetText())
		return nil
	}

	// First child must be BaseTypeAnnotationContext
	baseTypeAntlrCtx, ok := children[0].(*parser.BaseTypeAnnotationContext)
	if !ok || baseTypeAntlrCtx == nil {
		log.Printf("VisitTypeAnnotation: Expected first child to be BaseTypeAnnotationContext, got %T for '%s'", children[0], ctx.GetText())
		return nil
	}

	baseTypeInterface := v.VisitBaseTypeAnnotation(baseTypeAntlrCtx)
	currentAstExpr, ok := baseTypeInterface.(ast.Expr)
	if !ok || currentAstExpr == nil {
		// If baseType is void (which returns nil), and there are no modifiers, this is okay.
		// If there are modifiers, applying them to a nil base type is an error.
		if len(children) > 1 && baseTypeInterface == nil { // Modifiers present after a void base type
			log.Printf("VisitTypeAnnotation: Cannot apply modifiers to 'void' base type for '%s'", ctx.GetText())
			return nil
		}
		// If it's not ok, but not nil, it's an unexpected type from VisitBaseTypeAnnotation
		if !ok && baseTypeInterface != nil {
			log.Printf("VisitTypeAnnotation: Expected ast.Expr from VisitBaseTypeAnnotation, got %T for '%s'", baseTypeInterface, baseTypeAntlrCtx.GetText())
			return nil
		}
		// If it's nil and no modifiers, it could be a valid 'void' type indication if allowed by caller
		if currentAstExpr == nil && len(children) == 1 {
			return nil // e.g. a void return type in a function signature
		}
	}

	// Process modifiers if any (children after the first one)
	i := 1 // Start processing children from the second element (index 1)
	for i < len(children) {
		child := children[i]
		node, isTerminal := child.(antlr.TerminalNode)

		if !isTerminal {
			log.Printf("VisitTypeAnnotation: Expected a terminal node (modifier token) at child index %d, got %T for '%s'", i, child, ctx.GetText())
			return nil // Error: unexpected context instead of token
		}

		symbolType := node.GetSymbol().GetTokenType()

		if currentAstExpr == nil { // Should have been caught earlier if base was nil with modifiers
			log.Printf("VisitTypeAnnotation: Base type resolved to nil, cannot apply modifiers for '%s'", ctx.GetText())
			return nil
		}

		switch symbolType {
		case parser.ManuscriptLSQBR: // Start of array `[]` or map `[K:V]`
			if i+1 >= len(children) {
				log.Printf("VisitTypeAnnotation: Incomplete LSQBR modifier for '%s'", ctx.GetText())
				return nil
			}
			nextTokenNode, nextIsTerminal := children[i+1].(antlr.TerminalNode)
			if !nextIsTerminal {
				log.Printf("VisitTypeAnnotation: Expected COLON or RSQBR after LSQBR, found %T for '%s'", children[i+1], ctx.GetText())
				return nil
			}

			nextTokenSymbolType := nextTokenNode.GetSymbol().GetTokenType()
			if nextTokenSymbolType == parser.ManuscriptCOLON { // Map: [KeyTypeFromCurrent: ValueType]
				mapKeyType := currentAstExpr
				if i+2 >= len(children) {
					log.Printf("VisitTypeAnnotation: Incomplete map modifier (missing value type or RSQBR) for '%s'", ctx.GetText())
					return nil
				}
				mapValueTypeAntlrCtx, isValueCtx := children[i+2].(*parser.TypeAnnotationContext)
				if !isValueCtx || mapValueTypeAntlrCtx == nil {
					log.Printf("VisitTypeAnnotation: Expected TypeAnnotationContext for map value, got %T for '%s'", children[i+2], ctx.GetText())
					return nil
				}
				mapValueInterface := v.VisitTypeAnnotation(mapValueTypeAntlrCtx)
				mapValueAstExpr, okVal := mapValueInterface.(ast.Expr)
				if !okVal || mapValueAstExpr == nil {
					log.Printf("VisitTypeAnnotation: Map value type did not resolve to ast.Expr for '%s'", mapValueTypeAntlrCtx.GetText())
					return nil
				}

				if i+3 >= len(children) || children[i+3].(antlr.TerminalNode).GetSymbol().GetTokenType() != parser.ManuscriptRSQBR {
					log.Printf("VisitTypeAnnotation: Map modifier missing closing RSQBR for '%s'", ctx.GetText())
					return nil
				}
				currentAstExpr = &ast.MapType{Key: mapKeyType, Value: mapValueAstExpr}
				i += 4 // Consumed LSQBR, COLON, TypeAnnotationContext, RSQBR

			} else if nextTokenSymbolType == parser.ManuscriptRSQBR { // Array: [] (base type is element)
				currentAstExpr = &ast.ArrayType{Elt: currentAstExpr}
				i += 2 // Consumed LSQBR, RSQBR
			} else {
				log.Printf("VisitTypeAnnotation: Unexpected token after LSQBR: %s for '%s'", nextTokenNode.GetText(), ctx.GetText())
				return nil
			}

		case parser.ManuscriptLT: // Start of set `<>`
			if i+1 >= len(children) || children[i+1].(antlr.TerminalNode).GetSymbol().GetTokenType() != parser.ManuscriptGT {
				log.Printf("VisitTypeAnnotation: Incomplete LT GT (set) modifier for '%s'", ctx.GetText())
				return nil
			}
			// Set<T> becomes map[T]struct{}
			currentAstExpr = &ast.MapType{
				Key:   currentAstExpr,
				Value: &ast.StructType{Fields: &ast.FieldList{List: []*ast.Field{}}}, // struct{}
			}
			i += 2 // Consumed LT, GT

		default:
			log.Printf("VisitTypeAnnotation: Unexpected modifier token %s for '%s'", node.GetText(), ctx.GetText())
			return nil
		}
	}

	log.Printf("VisitTypeAnnotation: Successfully processed to type %T for input '%s'", currentAstExpr, ctx.GetText())
	return currentAstExpr
}

// VisitBaseTypeAnnotation handles the base part of a type annotation.
// It should return an ast.Expr representing the Go type.
func (v *ManuscriptAstVisitor) VisitBaseTypeAnnotation(ctx *parser.BaseTypeAnnotationContext) interface{} {
	log.Printf("VisitBaseTypeAnnotation: Called for '%s'", ctx.GetText())
	if ctx.ID() != nil { // Simple type (identifier)
		typeName := ctx.ID().GetText()
		// Map Manuscript basic types to Go types
		switch typeName {
		case "string":
			return ast.NewIdent("string")
		case "int":
			return ast.NewIdent("int64") // Default to int64 for broader compatibility
		case "float":
			return ast.NewIdent("float64") // Default to float64
		case "bool":
			return ast.NewIdent("bool")
		case "any":
			return ast.NewIdent("interface{}")
		case "void":
			log.Printf("VisitBaseTypeAnnotation: Manuscript 'void' type encountered. Representing as nil type expression.")
			return nil
		default:
			return ast.NewIdent(typeName)
		}
	}
	if ctx.TupleType() != nil {
		log.Printf("VisitBaseTypeAnnotation: TupleType '%s' encountered, calling VisitTupleType.", ctx.TupleType().GetText())
		return v.VisitTupleType(ctx.TupleType().(*parser.TupleTypeContext))
	}
	if ctx.FunctionType() != nil {
		log.Printf("VisitBaseTypeAnnotation: FunctionType '%s' encountered, calling VisitFunctionType.", ctx.FunctionType().GetText())
		return v.VisitFunctionType(ctx.FunctionType().(*parser.FunctionTypeContext))
	}

	log.Printf("VisitBaseTypeAnnotation: Unhandled base type annotation for '%s'", ctx.GetText())
	return nil
}

// VisitFunctionType handles function type signatures.
// Returns *ast.FuncType
func (v *ManuscriptAstVisitor) VisitFunctionType(ctx *parser.FunctionTypeContext) interface{} {
	log.Printf("VisitFunctionType: Called for '%s'", ctx.GetText())

	params := &ast.FieldList{List: []*ast.Field{}}
	if len(ctx.GetParamTypes()) > 0 {
		for _, paramTypeCtxInterface := range ctx.GetParamTypes() {
			if paramTypeCtx, okAssert := paramTypeCtxInterface.(*parser.TypeAnnotationContext); okAssert {
				paramTypeInterfaceVisit := v.VisitTypeAnnotation(paramTypeCtx)
				if paramTypeExpr, ok := paramTypeInterfaceVisit.(ast.Expr); ok {
					params.List = append(params.List, &ast.Field{Type: paramTypeExpr})
				} else {
					log.Printf("VisitFunctionType: Expected ast.Expr for parameter type, got %T for '%s'", paramTypeInterfaceVisit, paramTypeCtx.GetText())
					return nil
				}
			} else {
				log.Printf("VisitFunctionType: Failed to assert *parser.TypeAnnotationContext for parameter type '%s'", paramTypeCtxInterface.GetText())
				return nil
			}
		}
	}

	var results *ast.FieldList
	if ctx.GetReturnType() != nil {
		if returnTypeActualCtx, okAssert := ctx.GetReturnType().(*parser.TypeAnnotationContext); okAssert {
			returnTypeInterface := v.VisitTypeAnnotation(returnTypeActualCtx)
			if returnTypeExpr, ok := returnTypeInterface.(ast.Expr); ok {
				results = &ast.FieldList{List: []*ast.Field{{Type: returnTypeExpr}}}
			} else {
				log.Printf("VisitFunctionType: Expected ast.Expr for return type, got %T for '%s'", returnTypeInterface, ctx.GetReturnType().GetText())
				return nil
			}
		} else {
			log.Printf("VisitFunctionType: Failed to assert *parser.TypeAnnotationContext for return type '%s'", ctx.GetReturnType().GetText())
			return nil
		}
	} else {
		results = nil
	}

	return &ast.FuncType{
		Params:  params,
		Results: results,
	}
}

// VisitTupleType handles tuple type signatures.
// e.g., (Type1, Type2, Type3)
// Returns *ast.StructType representing the tuple.
func (v *ManuscriptAstVisitor) VisitTupleType(ctx *parser.TupleTypeContext) interface{} {
	log.Printf("VisitTupleType: Called for '%s'", ctx.GetText())

	fields := []*ast.Field{}
	typeAnnotations := ctx.GetTypes() // This should be []parser.ITypeAnnotationContext

	for i, typeAntlrCtxInterface := range typeAnnotations {
		if typeAntlrCtx, okAssert := typeAntlrCtxInterface.(*parser.TypeAnnotationContext); okAssert {
			fieldTypeInterface := v.VisitTypeAnnotation(typeAntlrCtx)
			if fieldTypeExpr, ok := fieldTypeInterface.(ast.Expr); ok && fieldTypeExpr != nil {
				fieldName := fmt.Sprintf("_%d", i) // Generates field names like _0, _1, etc.
				fields = append(fields, &ast.Field{
					Names: []*ast.Ident{ast.NewIdent(fieldName)},
					Type:  fieldTypeExpr,
				})
			} else {
				log.Printf("VisitTupleType: Element type at index %d did not resolve to ast.Expr for tuple '%s', got %T", i, ctx.GetText(), fieldTypeInterface)
				return nil // Error in resolving one of the tuple's element types
			}
		} else {
			log.Printf("VisitTupleType: Element at index %d is not a TypeAnnotationContext for tuple '%s', got %T", i, ctx.GetText(), typeAntlrCtxInterface)
			return nil // Should not happen if grammar is correctly parsed
		}
	}

	if len(fields) == 0 {
		log.Printf("VisitTupleType: Empty tuple '%s' encountered, representing as struct{}", ctx.GetText())
		return &ast.StructType{
			Fields:     &ast.FieldList{List: []*ast.Field{}},
			Incomplete: false,
		}
	}

	return &ast.StructType{
		Fields:     &ast.FieldList{List: fields},
		Incomplete: false,
	}
}

// VisitIfaceDecl handles interface declarations.
// ifaceDecl: IFACE name=ID (EXTENDS baseIface+=baseTypeAnnotation (COMMA baseIface+=baseTypeAnnotation)*)? LBRACE (methodDecl SEMICOLON?)* RBRACE;
