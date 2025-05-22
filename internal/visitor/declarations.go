package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitImportDecl handles import declarations and lowers them to Go imports and variable assignments
func (v *ManuscriptAstVisitor) VisitImportDecl(ctx *parser.ImportDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *ManuscriptAstVisitor) VisitLetDecl(ctx *parser.LetDeclContext) interface{} {
	if ctx.LetSingle() != nil {
		return v.Visit(ctx.LetSingle())
	}
	if ctx.LetBlock() != nil {
		return v.Visit(ctx.LetBlock())
	}
	if ctx.LetDestructuredObj() != nil {
		return v.Visit(ctx.LetDestructuredObj())
	}
	if ctx.LetDestructuredArray() != nil {
		return v.Visit(ctx.LetDestructuredArray())
	}
	return &ast.BadDecl{}
}

func (v *ManuscriptAstVisitor) VisitLetBlock(ctx *parser.LetBlockContext) interface{} {
	return v.VisitChildren(ctx)
}

// VisitExportDecl expects the exported item visitor methods to be implemented and return Go AST nodes.
func (v *ManuscriptAstVisitor) VisitExportDecl(ctx *parser.ExportDeclContext) interface{} {
	if ctx == nil || ctx.ExportedItem() == nil {
		v.addError("Export declaration is missing an exported item.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	// Use Accept to visit the exported item, leveraging the grammar structure
	visitedNode := ctx.ExportedItem().Accept(v)
	// Capitalize identifiers for Go export
	if decl, ok := visitedNode.(*ast.FuncDecl); ok && decl.Name != nil {
		decl.Name = ast.NewIdent(capitalize(decl.Name.Name))
		return decl
	}
	if decl, ok := visitedNode.(*ast.GenDecl); ok && len(decl.Specs) > 0 {
		for _, spec := range decl.Specs {
			switch s := spec.(type) {
			case *ast.TypeSpec:
				s.Name = ast.NewIdent(capitalize(s.Name.Name))
			case *ast.ValueSpec:
				for i, n := range s.Names {
					s.Names[i] = ast.NewIdent(capitalize(n.Name))
				}
			}
		}
		return decl
	}
	return visitedNode
}

// capitalize returns the string with the first letter uppercased (for Go export)
func capitalize(s string) string {
	if len(s) == 0 {
		return s
	}
	r := []rune(s)
	r[0] = toUpper(r[0])
	return string(r)
}

// toUpper converts a rune to upper case if it's a lower case ASCII letter
func toUpper(r rune) rune {
	if r >= 'a' && r <= 'z' {
		return r - 'a' + 'A'
	}
	return r
}

func (v *ManuscriptAstVisitor) VisitExternDecl(ctx *parser.ExternDeclContext) interface{} {
	return v.VisitChildren(ctx)
}
