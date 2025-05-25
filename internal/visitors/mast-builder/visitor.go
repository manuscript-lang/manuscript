package mastb

import (
	"strings"

	"manuscript-co/manuscript/internal/ast"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// ParseTreeToAST is the main visitor that converts ANTLR parse tree to manuscript AST
type ParseTreeToAST struct {
	*parser.BaseManuscriptVisitor
}

// NewParseTreeToAST creates a new visitor instance
func NewParseTreeToAST() *ParseTreeToAST {
	return &ParseTreeToAST{
		BaseManuscriptVisitor: &parser.BaseManuscriptVisitor{},
	}
}

// Helper function to extract position from ANTLR context
func (v *ParseTreeToAST) getPosition(ctx antlr.ParserRuleContext) ast.Position {
	token := ctx.GetStart()
	if token == nil {
		return ast.Position{}
	}
	return ast.Position{
		Line:   token.GetLine(),
		Column: token.GetColumn(),
		Offset: token.GetStart(),
	}
}

func (v *ParseTreeToAST) VisitProgram(ctx *parser.ProgramContext) interface{} {
	if ctx == nil {
		return nil
	}

	program := &ast.Program{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	// Collect all declarations
	for _, declCtx := range ctx.AllDeclaration() {
		if decl := declCtx.Accept(v); decl != nil {
			if declaration, ok := decl.(ast.Declaration); ok {
				program.Declarations = append(program.Declarations, declaration)
			}
		}
	}

	return program
}

func (v *ParseTreeToAST) VisitDeclaration(ctx *parser.DeclarationContext) interface{} {
	// Delegate to the specific declaration type
	if ctx.ImportDecl() != nil {
		return ctx.ImportDecl().Accept(v)
	}
	if ctx.ExportDecl() != nil {
		return ctx.ExportDecl().Accept(v)
	}
	if ctx.ExternDecl() != nil {
		return ctx.ExternDecl().Accept(v)
	}
	if ctx.LetDecl() != nil {
		return ctx.LetDecl().Accept(v)
	}
	if ctx.TypeDecl() != nil {
		return ctx.TypeDecl().Accept(v)
	}
	if ctx.InterfaceDecl() != nil {
		return ctx.InterfaceDecl().Accept(v)
	}
	if ctx.FnDecl() != nil {
		return ctx.FnDecl().Accept(v)
	}
	if ctx.MethodsDecl() != nil {
		return ctx.MethodsDecl().Accept(v)
	}
	return nil
}

// Helper function to extract string value from StringLiteral
func (v *ParseTreeToAST) extractStringValue(strLit *ast.StringLiteral) string {
	var result strings.Builder
	for _, part := range strLit.Parts {
		if content, ok := part.(*ast.StringContent); ok {
			result.WriteString(content.Content)
		}
		// For interpolations, we would need to handle them differently
		// For now, we'll just skip them for module paths
	}
	return result.String()
}

// TypedID and related

func (v *ParseTreeToAST) VisitTypedIDList(ctx *parser.TypedIDListContext) interface{} {
	var typedIDs []ast.TypedID
	for _, idCtx := range ctx.AllTypedID() {
		if typedID := idCtx.Accept(v); typedID != nil {
			typedIDs = append(typedIDs, typedID.(ast.TypedID))
		}
	}
	return typedIDs
}

func (v *ParseTreeToAST) VisitTypedID(ctx *parser.TypedIDContext) interface{} {
	typedID := ast.TypedID{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}

	if ctx.TypeAnnotation() != nil {
		if typeAnn := ctx.TypeAnnotation().Accept(v); typeAnn != nil {
			typedID.Type = typeAnn.(ast.TypeAnnotation)
		}
	}

	return typedID
}
