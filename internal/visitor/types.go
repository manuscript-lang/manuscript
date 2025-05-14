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
		v.addError("Invalid empty type annotation: "+ctx.GetText(), ctx.GetStart())
		return nil
	}

	// First child must be BaseTypeAnnotationContext
	baseTypeAntlrCtx, ok := children[0].(*parser.BaseTypeAnnotationContext)
	if !ok || baseTypeAntlrCtx == nil {
		v.addError("Internal error: Expected base type annotation, got unexpected type for: "+ctx.GetText(), ctx.GetStart())
		return nil
	}

	baseTypeInterface := v.VisitBaseTypeAnnotation(baseTypeAntlrCtx)
	currentAstExpr, ok := baseTypeInterface.(ast.Expr)
	if !ok || currentAstExpr == nil {
		// If baseType is void (which returns nil), and there are no modifiers, this is okay.
		// If there are modifiers, applying them to a nil base type is an error.
		if len(children) > 1 && baseTypeInterface == nil { // Modifiers present after a void base type
			v.addError("Cannot apply type modifiers (e.g., [], <>) to 'void' type: "+ctx.GetText(), baseTypeAntlrCtx.GetStart())
			return nil
		}
		// If it's not ok, but not nil, it's an unexpected type from VisitBaseTypeAnnotation
		if !ok && baseTypeInterface != nil {
			v.addError("Internal error: Base type annotation did not resolve to a valid expression for: "+baseTypeAntlrCtx.GetText(), baseTypeAntlrCtx.GetStart())
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
			cTOKEN := children[i-1].(antlr.TerminalNode).GetSymbol() // Previous token for context
			v.addError("Invalid type modifier sequence: expected a token (like '[', ']', ':', '<', '>') but found complex structure after: "+cTOKEN.GetText(), cTOKEN)
			return nil // Error: unexpected context instead of token
		}

		symbolType := node.GetSymbol().GetTokenType()

		if currentAstExpr == nil { // Should have been caught earlier if base was nil with modifiers
			v.addError("Internal error: Cannot apply modifiers to a nil base type: "+ctx.GetText(), node.GetSymbol())
			return nil
		}

		switch symbolType {
		case parser.ManuscriptLSQBR: // Start of array `[]` or map `[K:V]`
			if i+1 >= len(children) {
				v.addError("Incomplete type modifier: '[' not followed by ']' or ':': "+ctx.GetText(), node.GetSymbol())
				return nil
			}
			nextTokenNode, nextIsTerminal := children[i+1].(antlr.TerminalNode)
			if !nextIsTerminal {
				v.addError("Invalid type modifier: expected ':' or ']' after '[', but found complex structure for: "+ctx.GetText(), node.GetSymbol())
				return nil
			}

			nextTokenSymbolType := nextTokenNode.GetSymbol().GetTokenType()
			if nextTokenSymbolType == parser.ManuscriptCOLON { // Map: [KeyTypeFromCurrent: ValueType]
				mapKeyType := currentAstExpr
				if i+2 >= len(children) {
					v.addError("Incomplete map type: missing value type or ']' after ':': "+ctx.GetText(), nextTokenNode.GetSymbol())
					return nil
				}
				mapValueTypeAntlrCtx, isValueCtx := children[i+2].(*parser.TypeAnnotationContext)
				if !isValueCtx || mapValueTypeAntlrCtx == nil {
					v.addError("Invalid map type: expected a type for map value for: "+ctx.GetText(), nextTokenNode.GetSymbol())
					return nil
				}
				mapValueInterface := v.VisitTypeAnnotation(mapValueTypeAntlrCtx)
				mapValueAstExpr, okVal := mapValueInterface.(ast.Expr)
				if !okVal || mapValueAstExpr == nil {
					v.addError("Map value type is invalid or void: "+mapValueTypeAntlrCtx.GetText(), mapValueTypeAntlrCtx.GetStart())
					return nil
				}

				if i+3 >= len(children) || children[i+3].(antlr.TerminalNode).GetSymbol().GetTokenType() != parser.ManuscriptRSQBR {
					// Attempt to get the last token for error reporting, or fallback to current node
					lastToken := node.GetSymbol()
					if i+2 < len(children) && children[i+2].(antlr.ParseTree).GetChildCount() > 0 {
						// This is a heuristic, trying to get a token from the map value type
						// It might not always be the most accurate, but better than `node.GetSymbol()` which is `[`
						// A more robust way would be to get stop token of children[i+2]
						// For now, we'll use the start of the mapValueTypeAntlrCtx or the colon.
						lastToken = mapValueTypeAntlrCtx.GetStart()
					} else {
						lastToken = nextTokenNode.GetSymbol() // The colon token
					}
					v.addError("Map type missing closing ']': "+ctx.GetText(), lastToken)
					return nil
				}
				currentAstExpr = &ast.MapType{Key: mapKeyType, Value: mapValueAstExpr}
				i += 4 // Consumed LSQBR, COLON, TypeAnnotationContext, RSQBR

			} else if nextTokenSymbolType == parser.ManuscriptRSQBR { // Array: [] (base type is element)
				currentAstExpr = &ast.ArrayType{Elt: currentAstExpr}
				i += 2 // Consumed LSQBR, RSQBR
			} else {
				v.addError("Invalid token \""+nextTokenNode.GetText()+"\" after '[' in type. Expected ':' or ']'.", nextTokenNode.GetSymbol())
				return nil
			}

		case parser.ManuscriptLT: // Start of set `<>`
			if i+1 >= len(children) || children[i+1].(antlr.TerminalNode).GetSymbol().GetTokenType() != parser.ManuscriptGT {
				v.addError("Incomplete set type: '<' not followed by '>': "+ctx.GetText(), node.GetSymbol())
				return nil
			}
			// Set<T> becomes map[T]struct{}
			currentAstExpr = &ast.MapType{
				Key:   currentAstExpr,
				Value: &ast.StructType{Fields: &ast.FieldList{List: []*ast.Field{}}}, // struct{}
			}
			i += 2 // Consumed LT, GT

		default:
			v.addError("Unexpected type modifier token \""+node.GetText()+"\" for: "+ctx.GetText(), node.GetSymbol())
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
	v.addError("Unhandled base type annotation: "+ctx.GetText(), ctx.GetStart())
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
					v.addError("Invalid parameter type in function type signature: "+paramTypeCtx.GetText(), paramTypeCtx.GetStart())
					return nil
				}
			} else {
				// Safely try to get a token if possible, otherwise fallback to parent context start token
				token := ctx.GetStart()
				if pTree, isPTree := paramTypeCtxInterface.(antlr.ParseTree); isPTree {
					if rNode, isRNode := pTree.(antlr.RuleNode); isRNode {
						if prc, okAssertPrc := rNode.(antlr.ParserRuleContext); okAssertPrc {
							token = prc.GetStart()
						}
					}
				}
				v.addError("Internal error: Unexpected structure for parameter type in function type: "+paramTypeCtxInterface.GetText(), token)
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
				token := ctx.GetStart()
				if prc, okAssertPrc := ctx.GetReturnType().(antlr.ParserRuleContext); okAssertPrc {
					token = prc.GetStart()
				}
				v.addError("Internal error: Unexpected structure for return type in function type: "+ctx.GetReturnType().GetText(), token)
				return nil
			}
		} else {
			token := ctx.GetStart()
			if prc, okAssertPrc := ctx.GetReturnType().(antlr.ParserRuleContext); okAssertPrc {
				token = prc.GetStart()
			}
			v.addError("Internal error: Unexpected structure for return type in function type: "+ctx.GetReturnType().GetText(), token)
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
				token := ctx.GetStart()
				if pTree, isPTree := typeAntlrCtxInterface.(antlr.ParseTree); isPTree {
					if rNode, isRNode := pTree.(antlr.RuleNode); isRNode {
						if prc, okAssertPrc := rNode.(antlr.ParserRuleContext); okAssertPrc {
							token = prc.GetStart()
						}
					}
				}
				v.addError(fmt.Sprintf("Internal error: Unexpected structure for tuple element at index %d: %s", i, typeAntlrCtxInterface.GetText()), token)
				return nil // Should not happen if grammar is correctly parsed
			}
		} else {
			token := ctx.GetStart()
			if pTree, isPTree := typeAntlrCtxInterface.(antlr.ParseTree); isPTree {
				if rNode, isRNode := pTree.(antlr.RuleNode); isRNode {
					if prc, okAssertPrc := rNode.(antlr.ParserRuleContext); okAssertPrc {
						token = prc.GetStart()
					}
				}
			}
			v.addError(fmt.Sprintf("Internal error: Unexpected structure for tuple element at index %d: %s", i, typeAntlrCtxInterface.GetText()), token)
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
